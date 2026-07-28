# ─── Repositórios ECR ─────────────────────────────────────────────────────────
# Cria um repositório para cada serviço da aplicação.
# Os nomes seguem o padrão já usado nas imagens K8s: pos2/<serviço>
resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  # Habilita criptografia com chave gerenciada pela AWS
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = each.value
    Project = var.project_name
  }
}

# ─── Lifecycle Policy (mantém apenas as 10 últimas imagens) ───────────────────
resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = aws_ecr_repository.repos

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantém apenas as 10 imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
