variable "cluster_endpoint" {
  description = "Endpoint da API do cluster EKS"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Certificate Authority do cluster EKS (base64 encoded)"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "aws_region" {
  description = "Região AWS onde o cluster EKS está provisionado"
  type        = string
}

variable "gitops_repo_url" {
  description = "URL HTTPS do repositório GitHub que contém os manifestos GitOps"
  type        = string
}

variable "gitops_target_revision" {
  description = "Branch, tag ou commit do repositório GitOps que o ArgoCD deve monitorar"
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "Versão do chart Helm do ArgoCD (https://artifacthub.io/packages/helm/argo/argo-cd)"
  type        = string
  default     = "7.3.11"
}
