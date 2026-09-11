# OCI Queue: a fila de notificacoes, gerenciada e fora do cluster.
# 1 milhao de requisicoes gratis por mes; depois, US$ 0,22 por milhao.
resource "oci_queue_queue" "notificacoes" {
  compartment_id = local.compartimento
  display_name   = "${var.nome}-notificacoes"

  # 7 dias (o maximo): da tempo de inspecionar a dead-letter depois da demo.
  retention_in_seconds = 7 * 24 * 3600
  # Mensagem entregue fica invisivel por 30s; sem confirmacao, reaparece.
  visibility_in_seconds = 30
  # Long polling padrao do GetMessages.
  timeout_in_seconds = 20
  # Entregas antes da dead-letter. Tem que bater com MAX_TENTATIVAS em
  # backend/src/fila/fila.ts.
  dead_letter_queue_delivery_count = 5
}

# ------------------------------------------------------------ identidade dos pods
# O OKE Basic nao tem Workload Identity (so o Enhanced, que e pago). Os pods
# acessam a fila com a identidade do node em que rodam (instance principal):
# todo node do compartimento entra neste grupo.
#
# Consequencia: qualquer pod do cluster tem estas permissoes. Aceitavel aqui,
# com uma aplicacao so; com varios times no cluster, Enhanced + Workload
# Identity daria permissao por ServiceAccount.
resource "oci_identity_dynamic_group" "nodes" {
  compartment_id = var.tenancy_ocid
  name           = "${var.nome}-nodes"
  description    = "Nodes do OKE ${var.nome}: pods usam esta identidade para acessar a fila"
  matching_rule  = "ALL {instance.compartment.id = '${local.compartimento}'}"
}

resource "oci_identity_policy" "fila" {
  compartment_id = var.tenancy_ocid
  name           = "${var.nome}-fila"
  description    = "Worker do ${var.nome}: publicar, consumir e ler estatisticas da fila"
  statements = [
    # PutMessages (relay do outbox)
    "Allow dynamic-group ${oci_identity_dynamic_group.nodes.name} to use queue-push in compartment id ${local.compartimento}",
    # GetMessages, UpdateMessage, DeleteMessage (consumidor)
    "Allow dynamic-group ${oci_identity_dynamic_group.nodes.name} to use queue-pull in compartment id ${local.compartimento}",
    # GetStats (metrica achou_fila_jobs e escala do worker)
    "Allow dynamic-group ${oci_identity_dynamic_group.nodes.name} to read queues in compartment id ${local.compartimento}",
  ]
}
