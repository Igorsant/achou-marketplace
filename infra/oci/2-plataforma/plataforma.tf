# Componentes de plataforma que os manifests de deploy/k8s pressupoem.
# Versoes fixas: um chart que muda sozinho na vespera da apresentacao e
# exatamente o tipo de surpresa que nao queremos.

# CPU dos pods para o autoscaling da API. O OKE Basic nao traz o
# metrics-server como add-on; a Oracle instala o manifest padrao, sem flags.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = "kube-system"

  values = [yamlencode({
    resources = {
      requests = { cpu = "20m", memory = "48Mi" }
      limits   = { memory = "128Mi" }
    }
  })]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.20.2"
  namespace        = "keda"
  create_namespace = true

  values = [file("${path.module}/values/keda.yaml")]
}

# CRDs do Gateway API (padrao v1.5.1). O chart principal do Traefik nao os
# instala; o chart irmao traefik-crds sim.
resource "helm_release" "gateway_api_crds" {
  name       = "gateway-api-crds"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik-crds"
  version    = "1.18.0"
  namespace  = "kube-system"

  values = [yamlencode({
    traefik    = false
    gatewayAPI = true
  })]
}

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "41.5.0"
  namespace        = "gateway"
  create_namespace = true
  # CRDs ja vieram do release acima.
  skip_crds = true

  values = [file("${path.module}/values/traefik.yaml")]

  # Espera o NLB ganhar IP publico: o output url_publica depende disso.
  wait    = true
  timeout = 600

  depends_on = [helm_release.gateway_api_crds]
}

resource "random_password" "grafana" {
  length  = 24
  special = false
}

# Nome e namespace fixos: o KEDA do worker consulta
# kube-prometheus-stack-prometheus.monitoring.svc (deploy/k8s/base/worker-escala.yaml).
resource "helm_release" "monitoramento" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "90.1.1"
  namespace        = "monitoring"
  create_namespace = true

  values = [
    file("${path.module}/values/monitoramento.yaml"),
    yamlencode({ grafana = { adminPassword = random_password.grafana.result } }),
  ]
}
