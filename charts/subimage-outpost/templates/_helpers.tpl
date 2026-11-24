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
app.kubernetes.io/version: {{ include "subimage-outpost.appVersion" . | quote }}
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

{{/*
Validate and return rbac.configMaps.
*/}}
{{- define "subimage-outpost.configMapScope" -}}
{{- /* Only an absent key falls back to "all": helm upgrade --reuse-values from a chart older than 1.6.0 has no rbac.configMaps. */ -}}
{{- $scope := "all" -}}
{{- if hasKey .Values.rbac "configMaps" -}}
{{- $scope = .Values.rbac.configMaps -}}
{{- end -}}
{{- if not (has $scope (list "all" "awsAuth" "none")) -}}
{{- fail (printf "rbac.configMaps must be one of all, awsAuth, none (got %v)" (toJson $scope)) -}}
{{- end -}}
{{- $scope -}}
{{- end }}

{{/*
Pod template labels: selector labels plus podLabels. Selector labels are
immutable on a Deployment, so overriding one would orphan the running pod.
*/}}
{{- define "subimage-outpost.podLabels" -}}
{{- $selector := include "subimage-outpost.selectorLabels" . | fromYaml -}}
{{- range $key, $value := .Values.podLabels -}}
{{- if hasKey $selector $key -}}
{{- fail (printf "podLabels cannot set the selector label %s" $key) -}}
{{- end -}}
{{- end -}}
{{- include "subimage-outpost.selectorLabels" . }}
{{- range $key, $value := .Values.podLabels }}
{{ $key }}: {{ $value | toString | quote }}
{{- end }}
{{- end }}

{{/*
Container image reference. The default image.digest belongs to the appVersion
image, so a user-set image.tag runs that tag alone instead of pairing it with
a digest of a different image.
*/}}
{{- define "subimage-outpost.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $tag := .Values.image.tag | default "" | toString -}}
{{- $digest := .Values.image.digest | default "" | toString -}}
{{- if and (contains "@" $tag) (not (regexMatch "@sha256:[a-f0-9]{64}$" $tag)) -}}
{{- fail (printf "image.tag with a digest must end in @sha256:<64 hex characters> (got %q)" $tag) -}}
{{- end -}}
{{- if $tag -}}
{{- printf "%s:%s" $repository $tag -}}
{{- else if $digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $digest) -}}
{{- fail (printf "image.digest must look like sha256:<64 hex characters> (got %q)" $digest) -}}
{{- end -}}
{{- printf "%s:%s@%s" $repository .Chart.AppVersion $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository .Chart.AppVersion -}}
{{- end -}}
{{- end }}

{{/*
Version of the image the pod runs, for the app.kubernetes.io/version label.
A tag may carry its own digest ("1.2.6@sha256:..."), which a label value
cannot hold.
*/}}
{{- define "subimage-outpost.appVersion" -}}
{{- $tag := .Values.image.tag | default "" | toString | splitList "@" | first -}}
{{- regexReplaceAll "[^A-Za-z0-9]+$" ($tag | default .Chart.AppVersion | trunc 63) "" -}}
{{- end }}
