#!/usr/bin/env bash
# Deploy do Achou! no Kubernetes, na ordem que importa:
#   1. migration (Job)  ->  2. aplicacao (rolling update)  ->  3. monitoramento
#
# uso: scripts/deploy.sh <local|producao> <tag>
#   scripts/deploy.sh local dev
#   scripts/deploy.sh producao 1.4.0
#
# Usa o contexto atual do kubectl (ou $KUBECONFIG). Confira antes de rodar.
set -euo pipefail

AMBIENTE="${1:?uso: $0 <local|producao> <tag>}"
TAG="${2:?uso: $0 <local|producao> <tag>}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$RAIZ/deploy/k8s/overlays/$AMBIENTE"
NS=achou
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -d "$OVERLAY" ] || { echo "overlay inexistente: $OVERLAY"; exit 1; }
echo "contexto: $(kubectl config current-context) | ambiente: $AMBIENTE | tag: $TAG"

# Server-side apply: sem a anotacao last-applied (o JSON do dashboard passaria
# do limite dela) e com conflito explicito se outro dono mexeu no mesmo campo.
aplicar() { kubectl apply --server-side --field-manager=deploy-achou "$@"; }

# ------------------------------------------------------------ 0. renderiza
# Os overlays definem o nome da imagem; a tag e a da versao sendo publicada.
kubectl kustomize "$OVERLAY" \
  | sed -E "s#^([[:space:]]*image:[[:space:]]*[^[:space:]]*achou-backend(-migrate)?)(:[^[:space:]]+)?\$#\1:$TAG#" \
  > "$TMP/manifests.yaml"

# ------------------------------------------------------------ 1. migration
# O rotulo deploy.achou/etapa separa as fases: "pre-requisito" (namespace,
# config, segredo e, no cluster local, Postgres e Redis), "migracao" (o Job).
# Sem rotulo e a aplicacao.
aplicar -f "$TMP/manifests.yaml" -l 'deploy.achou/etapa=pre-requisito' >/dev/null
if kubectl get deploy -A -l deploy.achou/etapa=pre-requisito -o name | grep -q .; then
  kubectl wait deploy -A -l deploy.achou/etapa=pre-requisito --for=condition=Available --timeout=3m >/dev/null
fi

kubectl get secret -n "$NS" -o name | grep -q achou-secrets \
  || { echo "Secret achou-secrets nao existe em $NS (em producao, quem cria e o Terraform)"; exit 1; }

# O template de um Job e imutavel: a execucao anterior sai antes da nova.
kubectl delete job migracao -n "$NS" --ignore-not-found --wait >/dev/null
aplicar -f "$TMP/manifests.yaml" -l 'deploy.achou/etapa=migracao' >/dev/null

echo "migration: rodando..."
for _ in $(seq 1 150); do
  ok=$(kubectl get job migracao -n "$NS" -o jsonpath='{.status.succeeded}')
  falhou=$(kubectl get job migracao -n "$NS" -o jsonpath='{.status.failed}')
  [ "${ok:-0}" -ge 1 ] && break
  if [ "${falhou:-0}" -ge 1 ]; then
    echo "migration FALHOU -- a aplicacao nao foi alterada. Log:"
    kubectl logs job/migracao -n "$NS" --tail=50
    exit 1
  fi
  sleep 2
done
[ "${ok:-0}" -ge 1 ] || { echo "migration nao terminou em 5 min"; exit 1; }
kubectl logs job/migracao -n "$NS" --tail=3 | sed 's/^/  /'

# ------------------------------------------------------------ 2. aplicacao
# "!=" tambem casa recursos sem o rotulo: aplica tudo menos o Job.
aplicar -f "$TMP/manifests.yaml" -l 'deploy.achou/etapa!=migracao' >/dev/null
kubectl rollout status deploy/api deploy/worker -n "$NS" --timeout=5m

# ------------------------------------------------------------ 3. monitoramento
# Alertas e dashboard saem de observability/, a mesma fonte do docker-compose.
if kubectl api-resources --api-group=monitoring.coreos.com -o name | grep -q prometheusrules; then
  {
    cat <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: achou-alertas
  namespace: $NS
  labels:
    app.kubernetes.io/part-of: achou
spec:
EOF
    sed 's/^/  /' "$RAIZ/observability/prometheus/alertas.yml"
  } > "$TMP/alertas.yaml"
  aplicar -f "$TMP/alertas.yaml" >/dev/null

  # O sidecar do Grafana do kube-prometheus-stack carrega todo ConfigMap com
  # o rotulo grafana_dashboard=1.
  kubectl create configmap achou-dashboard -n "$NS" \
    --from-file="$RAIZ/observability/grafana/dashboards/achou-marketplace.json" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - grafana_dashboard=1 app.kubernetes.io/part-of=achou -o yaml \
    > "$TMP/dashboard.yaml"
  aplicar -f "$TMP/dashboard.yaml" >/dev/null
  echo "monitoramento: regras de alerta e dashboard aplicados"
else
  echo "monitoramento: CRDs do Prometheus Operator ausentes, pulando alertas e dashboard"
fi

echo "deploy concluido: $AMBIENTE @ $TAG"
