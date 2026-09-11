locals {
  kubeconfig = yamldecode(data.oci_containerengine_cluster_kube_config.achou.content)
}

output "regiao" {
  value = var.regiao
}

output "compartimento_id" {
  value = local.compartimento
}

output "cluster_id" {
  value = oci_containerengine_cluster.achou.id
}

output "kubernetes_host" {
  value = local.kubeconfig.clusters[0].cluster.server
}

output "kubernetes_ca" {
  value = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
}

output "versao_kubernetes" {
  value = local.versao_k8s
}

output "registro" {
  description = "Prefixo das imagens: <registro>/achou-backend:<tag>"
  value       = local.registro
}

output "registro_host" {
  value = local.registro_host
}

output "registro_usuario" {
  # Usuario do dominio de identidade padrao. Em conta federada (IDCS antiga)
  # o formato e <namespace>/oracleidentitycloudservice/<email>.
  value = "${data.oci_objectstorage_namespace.tenancy.namespace}/${data.oci_identity_user.eu.name}"
}

output "registro_senha" {
  value     = oci_identity_auth_token.ocir.token
  sensitive = true
}

output "postgres_host" {
  # FQDN, nao IP: o certificado do servidor e emitido para o nome, e o
  # Prisma valida o nome com sslaccept=strict.
  value = data.oci_psql_db_system_connection_detail.achou.primary_db_endpoint[0].fqdn
}

output "postgres_porta" {
  value = data.oci_psql_db_system_connection_detail.achou.primary_db_endpoint[0].port
}

output "postgres_usuario" {
  value = oci_psql_db_system.achou.credentials[0].username
}

output "postgres_senha" {
  value     = random_password.postgres.result
  sensitive = true
}

output "postgres_ca" {
  description = "Certificado da CA privada que assina o certificado do Postgres."
  value       = data.oci_psql_db_system_connection_detail.achou.ca_certificate
}

output "fila_id" {
  value = oci_queue_queue.notificacoes.id
}

output "fila_endpoint" {
  value = oci_queue_queue.notificacoes.messages_endpoint
}
