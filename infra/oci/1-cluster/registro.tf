# OCIR, o registro de imagens da propria OCI. Imagens privadas; o espaco
# conta no Object Storage, e as duas imagens (~250 MB comprimidas) ficam bem
# abaixo dos 20 GB gratuitos.
data "oci_objectstorage_namespace" "tenancy" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_user" "eu" {
  user_id = var.usuario_ocid
}

resource "oci_artifacts_container_repository" "imagens" {
  for_each = toset(["achou-backend", "achou-backend-migrate"])

  compartment_id = local.compartimento
  display_name   = "${var.nome}/${each.key}"
  is_public      = false
}

# Senha do `docker login` no OCIR e do imagePullSecret no cluster.
# A OCI permite no maximo 2 tokens por usuario: se o apply falhar aqui,
# apague um token antigo em Perfil > Tokens de autenticacao.
# Fica no state em texto puro -- mais um motivo para o state nao ir ao git.
resource "oci_identity_auth_token" "ocir" {
  user_id     = var.usuario_ocid
  description = "${var.nome}: push e pull de imagens no OCIR"
}

locals {
  registro_host = "${var.regiao}.ocir.io"
  registro      = "${local.registro_host}/${data.oci_objectstorage_namespace.tenancy.namespace}/${var.nome}"
}
