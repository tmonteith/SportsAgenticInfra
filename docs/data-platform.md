# Data Platform on OKE: Kafka and Airflow

The lakehouse's always-on pieces run in namespace `data` on the existing single OKE node: a one-node Kafka cluster (Strimzi, KRaft) and Airflow with the LocalExecutor. Everything is installed by OpenTofu through `module.data_platform` (`modules/data-platform`), using Helm values and a small local chart under `k8s/data/`.

| Piece | How it is installed | Version |
| --- | --- | --- |
| Namespace `data` (pod security `baseline`) | `kubernetes_namespace_v1.data` | |
| Service accounts `extractor`, `spark-drain`, `airflow` | `kubernetes_service_account_v1.workload` | |
| Role `airflow-pod-launcher` (pods, pods/log, events in `data` only) | `kubernetes_role_v1` + `kubernetes_role_binding_v1` | |
| OCIR repos `sportsagentic/extractor`, `sportsagentic/poller`, `sportsagentic/spark-drain` (private) | `oci_artifacts_container_repository.data` | |
| Strimzi cluster operator (watches `data` only) | `helm_release.strimzi`, values `k8s/data/strimzi/values.yaml` | chart 1.3.1 |
| Kafka `sa-kafka`, node pool `dual-role`, topics | `helm_release.kafka`, local chart `k8s/data/kafka` | Kafka 4.3.2 |
| Airflow (scheduler, API server, DAG processor, Postgres) | `helm_release.airflow`, values `k8s/data/airflow/values.yaml` + module values | chart 1.22.0, Airflow 3.2.2 |

Shared-contract names used here: Kafka bootstrap `sa-kafka-kafka-bootstrap.data:9092`, topics `cfb.live_games` and `agent.events` (1 partition, 7 days), env vars `GOOGLE_APPLICATION_CREDENTIALS=/var/secrets/gcp/key.json`, `GCP_PROJECT`, `ICEBERG_CATALOG=sa_catalog`, `KAFKA_BOOTSTRAP`, key Secret `gcp-key-airflow`.

---

## 1. Images

Every image is pinned by tag and published for both `linux/amd64` (the node today) and `linux/arm64`. Checked with `docker buildx imagetools inspect`:

| Image | Used by | Platforms |
| --- | --- | --- |
| `quay.io/strimzi/operator:1.3.1` | cluster operator, topic operator | amd64, arm64, ppc64le, s390x |
| `quay.io/strimzi/kafka:1.3.1-kafka-4.3.2` | Kafka broker/controller | amd64, arm64, ppc64le, s390x |
| `apache/airflow:3.2.2` (Python 3.13) | scheduler, API server, DAG processor, migration job, log groomers | amd64, arm64 |
| `registry.k8s.io/git-sync/git-sync:v4.4.2` | DAG sync sidecars | amd64, arm64, arm/v7, ppc64le, s390x |
| `bitnamilegacy/postgresql:16.1.0-debian-11-r15` | Airflow metadata DB | amd64, arm64 |

The official Airflow image already contains `apache-airflow-providers-google`, `apache-airflow-providers-cncf-kubernetes` and `apache-airflow-providers-fab` (its default `AIRFLOW_EXTRAS` include `google`, `cncf-kubernetes` and `fab`), so there is no custom Airflow image. Confirm on the running pod with `kubectl -n data exec deploy/airflow-scheduler -c scheduler -- airflow providers list`.

The Postgres image comes from Bitnami's `bitnamilegacy` repository, which no longer receives updates. It is what the Airflow chart's bundled Postgres subchart pins; the database is reachable only inside the cluster. Moving the metadata DB to a maintained image is a follow-up, not part of this build.

---

## 2. Before the first install

Do these in order. Nothing here is automated, on purpose.

1. **Resize the node** (section 6). The data platform does not fit on the 6 GB node: its memory requests (3,552 Mi) plus what already runs (842 Mi) exceed the 4,236 Mi allocatable, so pods would stay Pending.
2. **Pin the node pool to one availability domain** before cycling the node, or the new node can land where the existing volume cannot follow (section 7).
3. **Create the namespace, then the Airflow credentials Secret.** The Secret must exist before the Airflow release, or its pods cannot start and `tofu apply` times out:

   ```bash
   tofu apply -target=module.data_platform.kubernetes_namespace_v1.data
   ```

   Then create the Secret. Values are generated locally and never printed. The Postgres password is hex so it needs no URL encoding inside the connection string.

   ```bash
   PG_PASSWORD="$(openssl rand -hex 24)"
   kubectl -n data create secret generic airflow-credentials \
     --from-literal=fernet-key="$(openssl rand -base64 32 | tr '+/' '-_')" \
     --from-literal=api-secret-key="$(openssl rand -hex 32)" \
     --from-literal=jwt-secret="$(openssl rand -hex 64)" \
     --from-literal=postgres-password="${PG_PASSWORD}" \
     --from-literal=connection="postgresql://postgres:${PG_PASSWORD}@airflow-postgresql.data:5432/postgres?sslmode=disable"
   unset PG_PASSWORD
   ```

4. **Apply the rest** with `tofu apply` (show the plan to the owner first). The Airflow release can take several minutes the first time (image pull and DB migration).

### Which secrets come from where

| Secret / value | Created by | Notes |
| --- | --- | --- |
| Fernet key, API secret key, JWT secret, metadata DB connection, Postgres password | You, once (Secret `airflow-credentials`, step 3) | The chart is told to use this Secret for all five, so it generates none. Left to itself it would regenerate the API and JWT secrets on every upgrade and use the password `postgres`. Nothing goes into Git, OpenTofu state or Helm values. |
| Airflow admin user | You, after install (below) | The chart's create-user job is disabled because it takes the password from values. |
| `gcp-key-airflow` (GCP key) | External Secrets from OCI Vault (WS1) | Mounted read-only at `/var/secrets/gcp` as an optional volume, so pods start before it exists. The Secret's data key must be `key.json`. |
| `ocir-pull` (image pull) | Not created here; see section 5 | Referenced by the three service accounts. |

The Postgres password is set when the volume is first initialized. Changing it later means `ALTER USER postgres PASSWORD ...` inside Postgres and updating both `postgres-password` and `connection` in the Secret.

### Create the Airflow admin user

Airflow uses the FAB auth manager (chart default). The command prompts for the password, so it never appears in shell history, logs or values:

```bash
kubectl -n data exec -it deploy/airflow-scheduler -c scheduler -- \
  airflow users create --role Admin --username admin \
  --email <your-email> --firstname <first> --lastname <last>
```

### Open the UI

There is no Ingress or load balancer. Use a port-forward:

```bash
kubectl -n data port-forward svc/airflow-api-server 8080:8080
# then open http://localhost:8080
```

### Check Kafka

```bash
kubectl -n data get kafka sa-kafka            # READY True
kubectl -n data get kafkatopics               # cfb-live-games, agent.events: READY True
kubectl -n data exec sa-kafka-dual-role-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

`cfb.live_games` is managed by the KafkaTopic object `cfb-live-games`, because Kubernetes object names cannot contain `_`.

---

## 3. Memory and CPU budget

Gate (plan, phase 1): node allocatable memory minus the sum of all memory requests is at least 1.5 GiB with everything installed. CPU stays at 1 OCPU. Check it any time with:

```bash
scripts/capacity-check.sh                              # exits 1 if memory headroom < 1536Mi
scripts/capacity-check.sh --min-memory-headroom 2Gi    # different threshold
```

The script reads only `kubectl get` output and counts requests the way the scheduler does. metrics-server is not installed, so it shows requests, not actual use.

### Per pod

Requests and limits are per pod (all containers; init containers never exceed the main containers here).

| Pod | Containers | Memory request | Memory limit | CPU request | CPU limit |
| --- | --- | --- | --- | --- | --- |
| **Existing (measured)** | 15 pods | 842 Mi | 2,830 Mi | 590m | 2,960m |
| `strimzi-cluster-operator` | operator | 384 Mi | 384 Mi | 50m | 500m |
| `sa-kafka-dual-role-0` | Kafka (heap 768m) | 1,280 Mi | 1,280 Mi | 150m | 1,000m |
| `sa-kafka-entity-operator` | topic operator | 256 Mi | 256 Mi | 25m | 250m |
| `airflow-scheduler` | scheduler, git-sync, log groomer | 640 + 32 + 16 = 688 Mi | 1,024 + 64 + 32 = 1,120 Mi | 160m | 1,150m |
| `airflow-api-server` | API server (1 worker) | 320 Mi | 512 Mi | 50m | 500m |
| `airflow-dag-processor` | DAG processor, git-sync, log groomer | 320 + 32 + 16 = 368 Mi | 448 + 64 + 32 = 544 Mi | 60m | 650m |
| `airflow-postgresql-0` | Postgres | 256 Mi | 384 Mi | 50m | 500m |
| **This build, steady state** | | **3,552 Mi** | **4,480 Mi** | **545m** | |
| `airflow-run-airflow-migrations` | Job, install/upgrade only | 256 Mi | 448 Mi | 100m | 500m |
| External Secrets Operator (WS1, assumed) | 3 pods | 384 Mi | 384 Mi | 75m | |
| Drain pod (WS4b, assumed request = 2 GiB limit) | Spark local[2] | 2,048 Mi | 2,048 Mi | 250m | |
| Poller (WS3, assumed) | | 128 Mi | 128 Mi | 25m | |
| Extractor CronJob (WS3, assumed) | | 256 Mi | 256 Mi | 50m | |
| **Later phases** | | **2,816 Mi** | | **400m** | |
| **Everything** | | **7,210 Mi** (7,466 Mi during a migration) | | **1,535m** (1,635m) | |

Airflow memory limits (scheduler, API server, DAG processor, Postgres, both git-sync and both log-groomer sidecars) add up to 2,560 Mi, or 3,008 Mi while the migration job runs, under the plan's 3 GiB cap. The module recomputes this sum from `k8s/data/airflow/values.yaml` and refuses to plan if it goes over 3,072 Mi.

The drain pod is budgeted at its 2 GiB limit because its Spark driver really uses that much while it runs, every 15 minutes. If WS4b sets a lower request, the gate number improves on paper but not in practice.

### Choosing the node memory (N)

OKE sets the kubelet reservations itself. The OKE docs (Common Issues with Nodes and Pods, "kube-reserved") give: kube-reserved memory 1 GiB at 4 GiB and 8 GiB of node memory, 2 GiB at 16 GiB, 9 GiB at 128 GiB; system-reserved 100 Mi; CPU 70m + 100m on 2 cores. Plus the kubelet's 100 Mi hard-eviction threshold. The live node matches exactly: capacity 5,461 Mi, minus 1,024 + 100 + 100 = 4,237 Mi allocatable (observed 4,338,364 Ki), and 2,000m minus 170m = 1,830m CPU.

Assumptions for other sizes:

* The firmware and kernel take 683 Mi of the 6 GB node. Modelled as 587 Mi fixed plus 1.56% of RAM (the kernel's page table), so it grows slightly with N.
* kube-reserved between the documented points is interpolated linearly (8 GiB: 1,024 Mi, 16 GiB: 2,048 Mi). If OKE rounds up instead, 12 GB loses another 512 Mi; the result still holds.

| Node memory | Capacity (est.) | kube-reserved | Allocatable (est.) | Requests (everything) | Headroom | ≥ 1,536 Mi? |
| --- | --- | --- | --- | --- | --- | --- |
| 6 GB (today, measured) | 5,461 Mi | 1,024 Mi | 4,237 Mi | 842 Mi today | 3,395 Mi | (data platform does not fit) |
| 8 GB | 7,477 Mi | 1,024 Mi | 6,253 Mi | 7,210 Mi | -957 Mi | no |
| 10 GB | 9,493 Mi | 1,280 Mi | 8,013 Mi | 7,210 Mi | 803 Mi | no |
| **12 GB** | **11,509 Mi** | **1,536 Mi** | **9,773 Mi** | **7,210 Mi** | **2,563 Mi** | **yes** (2,307 Mi during a migration) |
| 14 GB | 13,525 Mi | 1,792 Mi | 11,533 Mi | 7,210 Mi | 4,323 Mi | yes |
| 16 GB | 15,541 Mi | 2,048 Mi | 13,293 Mi | 7,210 Mi | 6,083 Mi | yes |

**N = 12 GB** is the smallest even size that passes, so `production.auto.tfvars` sets `model_pool_memory_in_gbs = 12` with `model_pool_ocpus = 1`. 10 GB would pass only if the drain pod requested 1.25 GiB or less, which would under-count what it uses.

Cost: E5.Flex memory is billed per GB-hour (Oracle's list price is about $0.002 to $0.0026 per GB-hour; check the current OCI price list). Going from 6 GB to 12 GB adds roughly $9 to $11.50 a month; each 2 GB step is roughly $3 to $3.80 a month.

### CPU

All CPU requests together come to about 1,535m of 1,830m allocatable (1,635m while a migration runs), so everything schedules. The margin is thin, and real CPU use will contend while the drain pod runs: Spark `local[2]` wants both vCPUs for the length of each run, so Airflow and Kafka slow down during those minutes. That is acceptable for a batch drain but worth watching. If WS4b requests more than about 500m for the drain pod, pods stop scheduling, and the owner has to decide on a second OCPU.

---

## 4. Kafka details

* KRaft, one node with both controller and broker roles (`KafkaNodePool` `dual-role`), Kafka 4.3.2, metadata version 4.3-IV0.
* One listener: `plain`, port 9092, internal, no TLS. Strimzi also runs its own TLS listeners for replication and the operators; none of them is exposed outside the cluster.
* Every replication setting is 1. `auto.create.topics.enable` is false, so only the two contract topics exist.
* 50 Gi `oci-bv` volume (`deleteClaim: false`), KRaft metadata on the same volume.
* Disk cannot fill: each topic keeps 7 days or 10 GiB per partition, whichever comes first, in 256 MiB segments. Two topics at most reach about 21 GiB, plus small internal topics.
* Heap fixed at 768 MiB (`-Xms`/`-Xmx`), memory request and limit 1,280 Mi so the broker is the last pod evicted.
* Entity operator runs the topic operator only (no user operator).

Upgrading Strimzi: Helm installs CRDs on first install only and never upgrades them. Before raising `strimzi_chart_version`, apply the new release's CRDs by hand (`kubectl replace -f` the chart's `crds/` directory), then apply, following Strimzi's upgrade notes for the Kafka version.

---

## 5. Airflow details

* LocalExecutor: tasks run as processes inside the scheduler pod, at most 3 at once (`core.parallelism`). KubernetesPodOperator tasks start pods in `data` through the `airflow` service account. Restarting the scheduler kills running tasks; retries cover it.
* All Airflow pods run as service account `airflow`. Its Role allows pods (create, get, list, watch, patch, delete), pods/log (get, list) and events (get, list, watch) in `data` only. No `pods/exec`, so `do_xcom_push=True` on KubernetesPodOperator will not work until that is granted. Note that any account that can create pods in `data` can mount any Secret in `data`. Because the API server and DAG processor share the `airflow` account, they carry the same token although only the scheduler uses it (the chart has no per-pod switch to drop it).
* Postgres runs as the namespace's `default` service account, which has no permissions.
* DAGs: git-sync clones `https://github.com/tmonteith/SportsAgenticLakehouse.git`, branch `main`, every 60 s, and Airflow reads the `dags/` sub-path. Change with module variables `airflow_dags_repo_url`, `airflow_dags_branch`, `airflow_dags_sub_path`.
* Disabled: triggerer, statsd, Redis, Flower, PgBouncer, Celery workers, Ingress, create-user job. The API server service is ClusterIP. Task logs live on a 2 Gi emptyDir, cleaned after 7 days by the log-groomer sidecars.
* The migration job is a plain Kubernetes Job (not a Helm hook), as the chart requires for Terraform-style installs that wait for pods. It deletes itself 5 minutes after finishing. If an upgrade fails because the Job still exists, wait or delete the finished Job and apply again.

### Image pull secret for later workloads

`ocir-pull` exists only in `sportsagentic` today. The `extractor`, `spark-drain` and `airflow` service accounts already list it, so pods using them pick it up as soon as it exists in `data`. Options, best first:

1. WS1's External Secrets syncs it into `data` from OCI Vault, like the GCP keys.
2. The owner creates it with an OCIR auth token: `kubectl -n data create secret docker-registry ocir-pull --docker-server=ord.ocir.io --docker-username='<tenancy-namespace>/<user>' --docker-password='<auth-token>'`.

The poller has no service account in the contract; its Deployment needs `imagePullSecrets: [{name: ocir-pull}]` itself. The drain pod should run as `spark-drain` (set `service_account_name` in the KubernetesPodOperator).

---

## 6. How the node memory change takes effect

Changing `model_pool_memory_in_gbs` and running `tofu apply` only updates the node pool's configuration. OKE does not resize the running node: it keeps 6 GB until it is replaced.

To replace it, cycle the node pool (Console: node pool, Cycle nodes, or `oci ce node-pool update` with node pool cycling details). A shape or memory change needs terminate-and-replace cycling; boot-volume replacement cannot change the shape. With maximum surge 1 and maximum unavailable 0:

1. OKE starts a second node with the new size (a few minutes; a second E5 node and boot volume are billed for that time, and the extra boot volume may briefly push block storage past the 200 GB Always Free allowance).
2. When it is Ready, OKE cordons and drains the old node, then terminates it.
3. Every pod restarts on the new node. Each app runs one replica, so expect a few minutes of downtime for the site and the agent. The ingress load balancer's backend changes to the new node.

Pods with volumes can only follow if the new node is in the same availability domain as the volume (next section). Do this before installing the data platform, so its two volumes are created in the new node's availability domain.

---

## 7. Availability-domain risk

OCI block volumes are local to one availability domain, and a volume can only attach to a node in that domain. The node pool's placement (`modules/oke`) lists every availability domain in the region, so a replacement node, whether from cycling, a resize or a failed host, can come up in any of them.

Today the node and the only volume (`llama-server-models`) are both in `US-CHICAGO-1-AD-3`. After this build there will be three volumes there (llama models, Kafka, Airflow Postgres). If a replacement node lands in AD-1 or AD-2, Kafka and Postgres stay Pending (Airflow is down, producers lose their broker) and llama-server cannot scale back up, until a node exists in AD-3 again.

**Recommended fix (needs a `modules/oke` change and the owner's approval):** add an optional variable to `modules/oke`, for example `node_availability_domain`, that limits `placement_configs` to the one availability domain whose name ends in `AD-3`, keeping all domains when it is unset. Set it in `production.auto.tfvars` and apply it before cycling the node for the memory change. The trade-off: if AD-3 has no E5 capacity at that moment, the replacement waits instead of landing elsewhere. Taking a block volume backup of the Postgres volume before any node change keeps a copy that can be restored into another domain if needed; Kafka's data is short-lived and already drained to the lakehouse.

---

## 8. Teardown

`tofu destroy -target=module.data_platform` uninstalls the Helm releases and deletes namespace `data`, which deletes the Kafka and Postgres volumes with it (reclaim policy Delete): all Kafka data and Airflow history are lost. Helm never deletes CRDs; remove Strimzi's afterwards with `kubectl delete crd -l app=strimzi` if nothing else uses them.
