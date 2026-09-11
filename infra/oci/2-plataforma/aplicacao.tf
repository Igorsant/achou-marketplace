# O que a aplicacao recebe da infraestrutura: namespaces, credenciais e
# acesso ao registro. E o "Contrato com o Terraform" de docs/deploy.md.
# Os workloads (API, worker, Redis de cache) sao aplicados por
# scripts/deploy.sh a partir de deploy/k8s/overlays/oci.

resource "kubernetes_namespace_v1" "achou" {
  metadata {
    name = "achou"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }

  # O kustomize (deploy/k8s/base/namespace.yaml) acrescenta os proprios
  # rotulos; o Terraform nao briga com eles.
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# Sem a politica "restricted": a imagem oficial do Redis sobe como root.
resource "kubernetes_namespace_v1" "dependencias" {
  metadata {
    name = "achou-dependencias"
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# Sem caracteres especiais: as senhas entram em URLs de conexao.
resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}

locals {
  redis = "redis.achou-dependencias.svc:6379"

  # Onde os pods montam o certificado da CA do Postgres
  # (deploy/k8s/overlays/oci/kustomization.yaml).
  ca_postgres = "/etc/achou/postgres/ca.pem"

  database_url = join("", [
    "postgresql://${local.cluster.postgres_usuario}:${urlencode(local.cluster.postgres_senha)}",
    "@${local.cluster.postgres_host}:${local.cluster.postgres_porta}",
    # Banco "postgres": o que o servico cria. O admin nao e superusuario, e
    # usar o banco que ja existe dispensa um passo de CREATE DATABASE.
    "/postgres?schema=public",
    # Sem limite, o Prisma abre 2 x CPUs + 1 conexoes por pod (contando os
    # nucleos do node); com o KEDA multiplicando pods, esgotaria o banco.
    "&connection_limit=5",
    # O servico so aceita TLS. sslaccept=strict valida o certificado do
    # servidor contra a CA da Oracle -- o padrao do Prisma aceitaria qualquer um.
    "&sslmode=require&sslcert=${local.ca_postgres}&sslaccept=strict",
  ])
}

resource "kubernetes_secret_v1" "achou" {
  metadata {
    name      = "achou-secrets"
    namespace = kubernetes_namespace_v1.achou.metadata[0].name
  }

  data = {
    DATABASE_URL    = local.database_url
    REDIS_CACHE_URL = "redis://:${random_password.redis.result}@${local.redis}/0"
    JWT_SECRET      = random_password.jwt.result
    # Nao sao segredos, mas so existem depois do Terraform; ficam aqui para
    # o overlay nao precisar de mais uma fonte de configuracao.
    FILA_OCI_ID       = local.cluster.fila_id
    FILA_OCI_ENDPOINT = local.cluster.fila_endpoint
  }
}

resource "kubernetes_secret_v1" "postgres_ca" {
  metadata {
    name      = "postgres-ca"
    namespace = kubernetes_namespace_v1.achou.metadata[0].name
  }

  data = {
    "ca.pem" = local.cluster.postgres_ca
  }
}

resource "kubernetes_secret_v1" "dependencias" {
  metadata {
    name      = "credenciais"
    namespace = kubernetes_namespace_v1.dependencias.metadata[0].name
  }

  data = {
    REDIS_PASSWORD = random_password.redis.result
  }
}

# Pull das imagens privadas do OCIR.
resource "kubernetes_secret_v1" "ocir" {
  metadata {
    name      = "ocir"
    namespace = kubernetes_namespace_v1.achou.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.cluster.registro_host) = {
          username = local.cluster.registro_usuario
          password = local.cluster.registro_senha
          auth     = base64encode("${local.cluster.registro_usuario}:${local.cluster.registro_senha}")
        }
      }
    })
  }
}

# Todo pod do namespace usa a ServiceAccount default: com o segredo nela,
# nenhum manifest precisa declarar imagePullSecrets.
resource "kubernetes_default_service_account_v1" "achou" {
  metadata {
    namespace = kubernetes_namespace_v1.achou.metadata[0].name
  }

  image_pull_secret {
    name = kubernetes_secret_v1.ocir.metadata[0].name
  }
}
