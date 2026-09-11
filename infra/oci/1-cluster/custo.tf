# Com o Postgres gerenciado o projeto passa a gastar credito (~US$ 0,16/h,
# ~US$ 115/mes se ficar ligado direto). O orcamento avisa por e-mail antes de
# o credito acabar -- o lembrete de rodar scripts/oci.sh destruir.
resource "oci_budget_budget" "achou" {
  count = var.email_alerta_custo == "" ? 0 : 1

  compartment_id = var.tenancy_ocid
  display_name   = "${var.nome}-orcamento"
  amount         = var.orcamento_mensal_usd
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [local.compartimento]
}

resource "oci_budget_alert_rule" "gasto" {
  for_each = var.email_alerta_custo == "" ? {} : { metade = 50, total = 100 }

  budget_id      = oci_budget_budget.achou[0].id
  display_name   = "gasto-${each.key}"
  type           = "ACTUAL"
  threshold_type = "PERCENTAGE"
  threshold      = each.value
  recipients     = var.email_alerta_custo
  message        = "O compartimento ${var.nome} gastou ${each.value}% do orcamento de US$ ${var.orcamento_mensal_usd}. Se a apresentacao ja passou: scripts/oci.sh destruir."
}
