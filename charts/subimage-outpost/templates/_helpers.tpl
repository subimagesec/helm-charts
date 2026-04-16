{{/*
Expand the name of the chart.
*/}}
{{- define "subimage-outpost.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "subimage-outpost.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "subimage-outpost.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "subimage-outpost.labels" -}}
helm.sh/chart: {{ include "subimage-outpost.chart" . }}
{{ include "subimage-outpost.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "subimage-outpost.selectorLabels" -}}
app.kubernetes.io/name: {{ include "subimage-outpost.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return the secret name for the auth key.
If authKey.secret.create is true, use the chart-generated name.
If false, use the user-provided authKey.secret.name.
*/}}
{{- define "subimage-outpost.authKeySecretName" -}}
{{- if .Values.outpost.authKey.secret.create -}}
{{- printf "%s-secrets" (include "subimage-outpost.fullname" .) -}}
{{- else -}}
{{- required "outpost.authKey.secret.name is required when outpost.authKey.secret.create is false" .Values.outpost.authKey.secret.name -}}
{{- end -}}
{{- end }}
