data "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = "gateway"
  }

  depends_on = [helm_release.traefik]
}

output "url_publica" {
  description = "Endereco da API (HTTP, via Network Load Balancer)."
  value       = "http://${data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip}"
}

output "grafana_senha" {
  description = "Senha do usuario admin do Grafana (acesso por scripts/oci.sh grafana)."
  value       = random_password.grafana.result
  sensitive   = true
}
