{{/* Tên cơ sở và tên đầy đủ của release. */}}
{{- define "insighthub.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "insighthub.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "insighthub.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "insighthub.labels" -}}
helm.sh/chart: {{ include "insighthub.chart" . }}
{{ include "insighthub.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: insighthub
{{- end }}

{{- define "insighthub.selectorLabels" -}}
app.kubernetes.io/name: {{ include "insighthub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Nhãn/selector theo từng component. Dùng: (dict "ctx" $ "component" "api") */}}
{{- define "insighthub.componentLabels" -}}
{{ include "insighthub.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "insighthub.componentSelectorLabels" -}}
{{ include "insighthub.selectorLabels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Tham chiếu image: repo:tag hoặc repo:tag@digest (digest thắng khi có cả hai). */}}
{{- define "insighthub.image" -}}
{{- $img := .img -}}
{{- $ref := $img.repository -}}
{{- if $img.tag }}{{- $ref = printf "%s:%s" $ref ($img.tag | toString) -}}{{- end -}}
{{- if $img.digest }}{{- $ref = printf "%s@%s" $ref $img.digest -}}{{- end -}}
{{- if not (or $img.tag $img.digest) }}
{{- fail (printf "image cho component %s thiếu cả tag lẫn digest — truyền --set image.%s.tag=<git short sha>" .component .component) -}}
{{- end -}}
{{- $ref -}}
{{- end }}

{{- define "insighthub.serviceAccountName" -}}
{{- default (include "insighthub.fullname" .) .Values.serviceAccount.name }}
{{- end }}

{{- define "insighthub.configMapName" -}}
{{- printf "%s-config" (include "insighthub.fullname" .) }}
{{- end }}

{{- define "insighthub.webConfigMapName" -}}
{{- printf "%s-web-config" (include "insighthub.fullname" .) }}
{{- end }}

{{- define "insighthub.apiServiceName" -}}
{{- printf "%s-api" (include "insighthub.fullname" .) }}
{{- end }}

{{- define "insighthub.webServiceName" -}}
{{- printf "%s-web" (include "insighthub.fullname" .) }}
{{- end }}

{{- define "insighthub.secretProviderClassName" -}}
{{- printf "%s-aws-secrets" (include "insighthub.fullname" .) }}
{{- end }}

{{/*
DATABASE_URL/REDIS_URL luôn đến từ K8s Secret theo TÊN — local do chart
insighthub-local-deps tạo, dev do CSI secretObjects sync (DAY3-CHECKLIST N.1).
*/}}
{{- define "insighthub.secretEnv" -}}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.secretName }}
      key: {{ .Values.secrets.databaseUrlKey }}
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.secretName }}
      key: {{ .Values.secrets.redisUrlKey }}
{{- end }}

{{/*
Volume/volumeMount của Secrets Store CSI. K8s Secret sync CHỈ tồn tại khi có pod
mount volume này → api, worker và migration Job đều phải mount (N.1).
*/}}
{{- define "insighthub.csiVolume" -}}
{{- if .Values.secretsStore.enabled }}
- name: aws-secrets
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ include "insighthub.secretProviderClassName" . }}
{{- end }}
{{- end }}

{{- define "insighthub.csiVolumeMount" -}}
{{- if .Values.secretsStore.enabled }}
- name: aws-secrets
  mountPath: /mnt/secrets-store
  readOnly: true
{{- end }}
{{- end }}
