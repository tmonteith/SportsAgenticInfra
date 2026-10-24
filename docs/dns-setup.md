# Domain Delegation Guide: Porkbun → OCI Public DNS

This guide explains how to delegate `sportagentic.dev` from your registrar (**Porkbun**) to the Oracle Cloud Infrastructure (OCI) authoritative DNS zone managed by OpenTofu.

---

## 1. How OCI DNS Works with Porkbun

1. **Registrar vs. DNS Host**:
   * **Porkbun** acts as your **Domain Registrar** (owns the registration of `sportagentic.dev`).
   * **OCI Public DNS** acts as the **Authoritative DNS Host** (serves `A`, `CNAME`, and Let's Encrypt `TXT` verification records).

2. **Nameserver Delegation**:
   * When OpenTofu runs `module.platform`, it creates an authoritative public DNS zone named `sportagentic.dev` (`oci_dns_zone.main`).
   * OCI allocates 4 high-availability Anycast nameservers for your zone, typically formatted as:
     - `ns1.p<number>.dns.oraclecloud.net`
     - `ns2.p<number>.dns.oraclecloud.net`
     - `ns3.p<number>.dns.oraclecloud.net`
     - `ns4.p<number>.dns.oraclecloud.net`

---

## 2. Delegation Steps in Porkbun

1. **Retrieve the OCI Nameservers from OpenTofu**:
   After running `tofu apply` (locally or via GitHub Actions), run:
   ```bash
   tofu output -json dns_nameservers
   ```
   Note down the 4 hostnames listed.

2. **Log into Porkbun**:
   * Go to [porkbun.com](https://porkbun.com) and log in.
   * Go to **Domain Management** -> find `sportagentic.dev`.
   * Click **Details** to expand domain settings.

3. **Update Authoritative Nameservers**:
   * Under the **Authoritative Nameservers** section, click **Edit**.
   * Replace the default Porkbun nameservers with the 4 OCI nameservers retrieved in Step 1.
   * Click **Submit**.

4. **Verify Propagation**:
   DNS propagation typically takes 5–30 minutes. Verify the delegation from your terminal:
   ```bash
   dig +short NS sportagentic.dev
   ```
   Once the output returns the `*.oraclecloud.net` nameservers, your domain is live and pointing to OCI!

---

## 3. Automatic TLS via cert-manager

Once the nameservers are delegated:
1. `ingress-nginx` receives an external public IP from the OCI Flexible Load Balancer.
2. The `cluster-issuer` Helm release requests Let's Encrypt certificates using the HTTP-01 or DNS-01 challenge.
3. Let's Encrypt validates the domain through the ingress controller and automatically provisions trusted TLS certificates.
