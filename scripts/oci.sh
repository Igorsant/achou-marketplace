#!/usr/bin/env bash
# Ciclo de vida do Achou! na Oracle Cloud (Always Free).
#
#   scripts/oci.sh subir            cria cluster + plataforma (terraform apply)
#   scripts/oci.sh publicar <tag>   builda, envia as imagens ao OCIR e faz o deploy
#   scripts/oci.sh url              endereco publico da API
#   scripts/oci.sh grafana          abre o Grafana em http://localhost:3003
#   scripts/oci.sh status           nodes e pods
#   scripts/oci.sh destruir         apaga tudo, na ordem certa
#
# Pre-requisitos e passo a passo: docs/deploy.md
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TF1="$RAIZ/infra/oci/1-cluster"
TF2="$RAIZ/infra/oci/2-plataforma"
export KUBECONFIG="$RAIZ/infra/oci/kubeconfig"
PERFIL="${OCI_CLI_PROFILE:-DEFAULT}"

saida1() { terraform -chdir="$TF1" output -raw "$1"; }
saida2() { terraform -chdir="$TF2" output -raw "$1"; }

exigir() {
  for c in "$@"; do
    command -v "$c" >/dev/null || { echo "falta instalar: $c (ver docs/deploy.md)"; exit 1; }
  done
}

gerar_kubeconfig() {
  # Arquivo proprio do projeto: o ~/.kube/config fica intocado.
  oci ce cluster create-kubeconfig --profile "$PERFIL" \
    --cluster-id "$(saida1 cluster_id)" --region "$(saida1 regiao)" \
    --file "$KUBECONFIG" --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT \
    --overwrite >/dev/null
  chmod 600 "$KUBECONFIG"
}

case "${1:-}" in
  subir)
    exigir terraform oci kubectl
    [ -f "$TF1/terraform.tfvars" ] || { echo "crie $TF1/terraform.tfvars a partir do .example"; exit 1; }
    terraform -chdir="$TF1" init -input=false >/dev/null
    terraform -chdir="$TF1" apply
    gerar_kubeconfig
    terraform -chdir="$TF2" init -input=false >/dev/null
    terraform -chdir="$TF2" apply -var "perfil_oci=$PERFIL"
    kubectl get nodes -o wide
    echo "cluster pronto. proximo passo: scripts/oci.sh publicar v1"
    ;;

  publicar)
    exigir docker kubectl oci
    TAG="${2:?uso: $0 publicar <tag>}"
    REGISTRO="$(saida1 registro)"
    [ -f "$KUBECONFIG" ] || gerar_kubeconfig

    # Token recem-criado pode levar um minuto para valer no OCIR.
    for tentativa in 1 2 3 4 5 6; do
      saida1 registro_senha | docker login "$(saida1 registro_host)" \
        -u "$(saida1 registro_usuario)" --password-stdin >/dev/null 2>&1 && break
      [ "$tentativa" = 6 ] && { echo "docker login no OCIR falhou"; exit 1; }
      echo "OCIR ainda nao aceitou o token, tentando de novo em 15s..."; sleep 15
    done

    # Nodes Ampere A1 sao ARM: a imagem precisa ser linux/arm64. Num Mac com
    # Apple Silicon isso e nativo; em maquina x86 o buildx emula (mais lento).
    for alvo in production migrate; do
      nome=achou-backend; [ "$alvo" = migrate ] && nome=achou-backend-migrate
      docker build --platform linux/arm64 --target "$alvo" -t "$REGISTRO/$nome:$TAG" "$RAIZ/backend"
      docker push "$REGISTRO/$nome:$TAG"
    done

    REGISTRO="$REGISTRO" "$RAIZ/scripts/deploy.sh" oci "$TAG"
    echo "API: $(saida2 url_publica)/health/live"
    ;;

  url)
    saida2 url_publica; echo
    ;;

  grafana)
    echo "usuario: admin | senha: $(saida2 grafana_senha)"
    echo "abrindo em http://localhost:3003 (Ctrl+C para fechar; a 3002 e do Grafana do compose)"
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3003:80
    ;;

  status)
    kubectl get nodes -o wide
    kubectl get pods -A -o wide | grep -Ev "kube-system"
    ;;

  destruir)
    exigir terraform oci
    # Lidos antes: depois do destroy da etapa 1 os outputs deixam de existir.
    COMPARTIMENTO="$(saida1 compartimento_id)"
    REGISTRO_HOST="$(saida1 registro_host)"

    # 1. Plataforma primeiro, com o cluster ainda de pe: desinstalar o Traefik
    #    apaga o Service, e so o cluster sabe pedir a OCI para apagar o
    #    Network Load Balancer que ele criou.
    terraform -chdir="$TF2" destroy -var "perfil_oci=$PERFIL"

    # 2. A OCI remove o NLB de forma assincrona. Se a rede for apagada antes,
    #    o destroy da etapa 1 falha com "subnet em uso".
    echo "esperando a OCI remover o load balancer..."
    for _ in $(seq 1 60); do
      nlb=$(oci nlb network-load-balancer list --profile "$PERFIL" --compartment-id "$COMPARTIMENTO" \
        --lifecycle-state ACTIVE --query 'length(data.items)' --raw-output 2>/dev/null || true)
      [ "${nlb:-0}" = 0 ] && break
      sleep 10
    done

    # 3. Cluster, Postgres gerenciado, fila, rede, registro e compartimento.
    #    O Postgres leva uns 10 minutos para ser apagado.
    terraform -chdir="$TF1" destroy
    rm -f "$KUBECONFIG"
    docker logout "$REGISTRO_HOST" >/dev/null 2>&1 || true
    echo "tudo removido"
    ;;

  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
