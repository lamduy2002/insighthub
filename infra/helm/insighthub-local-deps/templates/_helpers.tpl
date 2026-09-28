{{- define "localdeps.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Chart chỉ dùng cho local nên tên resource bám thẳng release name, tránh
chuỗi lặp kiểu <release>-insighthub-local-deps-postgres và rủi ro tràn 63 ký tự. */}}
{{- define "localdeps.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 55 | trimSuffix "-" }}
{{- end }}

{{- define "localdeps.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "localdeps.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: insighthub
{{- end }}

{{- define "localdeps.selectorLabels" -}}
app.kubernetes.io/name: {{ include "localdeps.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "localdeps.postgresName" -}}
{{- printf "%s-postgres" (include "localdeps.fullname" .) }}
{{- end }}

{{- define "localdeps.redisName" -}}
{{- printf "%s-redis" (include "localdeps.fullname" .) }}
{{- end }}

{{- define "localdeps.image" -}}
{{- $img := . -}}
{{- printf "%s:%s@%s" $img.repository ($img.tag | toString) $img.digest -}}
{{- end }}
