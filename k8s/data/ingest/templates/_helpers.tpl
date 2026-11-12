{{/* Image reference: <registry>/<namespace>/sportsagentic/<name>:<tag> */}}
{{- define "ingest.image" -}}
{{- $img := .root.Values.image -}}
{{- printf "%s/%s/sportsagentic/%s:%s" $img.registry (required "image.namespace (OCIR tenancy namespace) is required" $img.namespace) .name (required "image.tag is required" (toString $img.tag)) -}}
{{- end -}}

{{- define "ingest.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/component: {{ .name }}
app.kubernetes.io/part-of: sportsagentic
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end -}}

{{- define "ingest.cfbdEnv" -}}
- name: CFBD_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.cfbdApiKeySecret.name }}
      key: {{ .Values.cfbdApiKeySecret.key }}
- name: GCP_PROJECT
  value: {{ required "gcpProject is required" .Values.gcpProject | quote }}
{{- end -}}

{{/*
Extractor pod spec, shared by the nightly CronJob and the backfill Job.
Call with (dict "root" $ "args" <list>).
*/}}
{{- define "ingest.extractorPodSpec" -}}
{{- $v := .root.Values -}}
serviceAccountName: {{ $v.extractor.serviceAccountName }}
automountServiceAccountToken: false
restartPolicy: Never
{{- with $v.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
securityContext:
  {{- toYaml $v.podSecurityContext | nindent 2 }}
containers:
  - name: extractor
    image: {{ include "ingest.image" (dict "root" .root "name" "extractor") }}
    imagePullPolicy: {{ $v.image.pullPolicy }}
    args:
      {{- toYaml .args | nindent 6 }}
    env:
      {{- include "ingest.cfbdEnv" .root | nindent 6 }}
      - name: GOOGLE_APPLICATION_CREDENTIALS
        value: /var/secrets/gcp/key.json
      - name: GOMEMLIMIT
        value: {{ $v.extractor.goMemLimit | quote }}
    resources:
      {{- toYaml $v.extractor.resources | nindent 6 }}
    securityContext:
      {{- toYaml $v.containerSecurityContext | nindent 6 }}
    volumeMounts:
      - name: gcp-key
        mountPath: /var/secrets/gcp
        readOnly: true
volumes:
  - name: gcp-key
    secret:
      secretName: {{ $v.extractor.gcpKeySecret }}
      defaultMode: 0440
{{- end -}}
