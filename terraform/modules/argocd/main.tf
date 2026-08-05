# ─────────────────────────────────────────────────────────────────────────────
# Módulo ArgoCD
#
# Instala o ArgoCD via Helm e registra o App of Apps para que o ArgoCD
# monitore o repositório GitOps e sincronize automaticamente as mudanças.
#
# Dependência de aplicação em dois passos (first-time):
#   1. terraform apply -target=module.eks
#   2. terraform apply          ← aplica ArgoCD + App of Apps
#
# Após o apply, recupere a senha inicial do ArgoCD com:
#   kubectl -n argocd get secret argocd-initial-admin-secret \
#     -o jsonpath="{.data.password}" | base64 -d
# ─────────────────────────────────────────────────────────────────────────────

# ─── Namespace argocd ─────────────────────────────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ─── ArgoCD via Helm ──────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_chart_version

  # Aguarda todos os Pods ficarem Ready antes de retornar
  wait    = true
  timeout = 600

  values = [<<-YAML
    server:
      service:
        type: LoadBalancer
      # Desabilita TLS para simplificar o acesso em lab
      # Em produção, use cert-manager + HTTPS
      extraArgs:
        - --insecure

    configs:
      params:
        server.insecure: "true"

    global:
      image:
        pullPolicy: IfNotPresent
  YAML
  ]
}

# ─── App of Apps — Application raiz que gerencia as demais ────────────────────
#
# Usa null_resource + local-exec em vez de kubernetes_manifest para evitar
# o problema de bootstrap: kubernetes_manifest valida o CRD Application
# durante o plan, mas o CRD só existe após o helm_release.argocd ser aplicado.
# ─────────────────────────────────────────────────────────────────────────────
resource "null_resource" "app_of_apps" {
  triggers = {
    repo_url        = var.gitops_repo_url
    target_revision = var.gitops_target_revision
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configurar kubectl para acessar o cluster EKS
      echo "🔧 Configurando kubectl para cluster ${var.cluster_name}..."
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      
      # Aguardar cluster estar pronto
      echo "⏳ Aguardando cluster estar acessível..."
      for i in {1..30}; do
        if kubectl get nodes &>/dev/null; then
          echo "✅ Cluster acessível!"
          break
        fi
        echo "Tentativa $i/30..."
        sleep 10
      done
      
      # Aplicar App of Apps
      echo "📦 Aplicando ArgoCD App of Apps..."
      kubectl apply -f - <<EOF
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: feature-flags-apps
        namespace: argocd
        finalizers:
          - resources-finalizer.argocd.argoproj.io
      spec:
        project: default
        source:
          repoURL: ${var.gitops_repo_url}
          targetRevision: ${var.gitops_target_revision}
          path: gitops/argocd/applications
        destination:
          server: https://kubernetes.default.svc
          namespace: argocd
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
            - CreateNamespace=true
      EOF
      
      echo "✅ App of Apps aplicado com sucesso!"
    EOT
  }

  depends_on = [helm_release.argocd]
}
