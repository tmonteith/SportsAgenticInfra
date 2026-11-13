{{/* Image reference: <registry>/<namespace>/sportsagentic/spark-drain:<tag> */}}
{{- define "drain.image" -}}
{{- $img := .Values.image -}}
{{- printf "%s/%s/sportsagentic/spark-drain:%s" $img.registry (required "image.namespace (OCIR tenancy namespace) is required" $img.namespace) (required "image.tag is required" (toString $img.tag)) -}}
{{- end -}}

{{- define "drain.labels" -}}
app.kubernetes.io/name: spark-drain
app.kubernetes.io/component: spark-drain
app.kubernetes.io/part-of: sportsagentic
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Drain pod spec (contract H8). Shared by the one-off Job and, in Phase 4, the Airflow
KubernetesPodOperator.
*/}}
{{- define "drain.podSpec" -}}
{{- $d := .Values.drain -}}
serviceAccountName: {{ $d.serviceAccountName }}
automountServiceAccountToken: false
restartPolicy: Never
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
securityContext:
  {{- toYaml $d.podSecurityContext | nindent 2 }}
containers:
  - name: drain
    image: {{ include "drain.image" . }}
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    {{- with $d.args }}
    args:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    env:
      - name: GCP_PROJECT
        value: {{ required "gcpProject is required" .Values.gcpProject | quote }}
      - name: ICEBERG_CATALOG
        value: {{ required "icebergCatalog is required" .Values.icebergCatalog | quote }}
      - name: KAFKA_BOOTSTRAP
        value: {{ required "kafkaBootstrap is required" .Values.kafkaBootstrap | quote }}
      - name: GOOGLE_APPLICATION_CREDENTIALS
        value: /var/secrets/gcp/key.json
      - name: SPARK_DRIVER_MEMORY
        value: {{ $d.driverMemory | quote }}
      {{- with $d.knownTools }}
      - name: KNOWN_TOOLS
        value: {{ . | quote }}
      {{- end }}
    resources:
      {{- toYaml $d.resources | nindent 6 }}
    securityContext:
      {{- toYaml $d.containerSecurityContext | nindent 6 }}
    volumeMounts:
      - name: gcp-key
        mountPath: /var/secrets/gcp
        readOnly: true
      - name: tmp
        mountPath: /tmp
volumes:
  - name: gcp-key
    secret:
      secretName: {{ $d.gcpKeySecret }}
      defaultMode: 0440
  - name: tmp
    emptyDir:
      sizeLimit: {{ $d.tmpSizeLimit }}
{{- end -}}
