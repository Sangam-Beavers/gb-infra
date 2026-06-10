{{/*
앱 이름
*/}}
{{- define "wallet.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
풀네임
*/}}
{{- define "wallet.fullname" -}}
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
Chart 레이블
*/}}
{{- define "wallet.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{/*
공통 레이블
*/}}
{{- define "wallet.labels" -}}
helm.sh/chart: {{ include "wallet.chart" . }}
{{ include "wallet.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
{{/*
셀렉터 레이블
*/}}
{{- define "wallet.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wallet.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
