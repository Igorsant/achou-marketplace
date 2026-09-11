#!/usr/bin/env bash
# Inspeciona a fila local (FILA_DRIVER=postgres) e o outbox do Achou! Marketplace.
# Na nuvem a fila e a OCI Queue: estado no painel "Fila" do Grafana ou no
# console da OCI (Developer Services > Queues).
set -euo pipefail

PG="docker exec -i achou_postgres psql -U achou -d achou_marketplace -At"

case "${1:-stats}" in
  stats)
    echo "=== outbox ==="
    $PG -c "SELECT 'pendentes:        ' || count(*) FILTER (WHERE published_at IS NULL) || E'\npublicados:       ' || count(*) FILTER (WHERE published_at IS NOT NULL) FROM outbox_events"
    echo ""
    echo "=== fila notificacoes ==="
    $PG -c "SELECT 'aguardando:       ' || count(*) FILTER (WHERE NOT morta AND visivel_em <= now()) || E'\nem_processamento: ' || count(*) FILTER (WHERE NOT morta AND visivel_em > now()) || E'\nmortas:           ' || count(*) FILTER (WHERE morta) FROM fila_mensagens"
    ;;

  falhas)
    # Dead-letter: esgotaram as 5 tentativas.
    $PG -F ' | ' -c "SELECT to_char(criada_em, 'YYYY-MM-DD HH24:MI:SS'), tipo, conteudo->'payload'->>'email', tentativas || ' tentativas', ultimo_erro FROM fila_mensagens WHERE morta ORDER BY criada_em DESC LIMIT 20" \
      | sed 's/^/  /'
    [ "$($PG -c "SELECT count(*) FROM fila_mensagens WHERE morta")" = 0 ] && echo "nenhuma mensagem na dead-letter"
    ;;

  retry)
    # Devolve a dead-letter para a fila, com as tentativas zeradas.
    $PG -c "WITH r AS (UPDATE fila_mensagens SET morta = false, tentativas = 0, visivel_em = now(), ultimo_erro = NULL WHERE morta RETURNING 1) SELECT count(*) || ' mensagem(ns) devolvida(s) para a fila' FROM r"
    ;;

  logs)
    docker logs -f --since 5m achou_worker
    ;;

  *)
    cat <<USO
uso: $0 <comando>

  stats    eventos pendentes no outbox e mensagens por estado na fila
  falhas   mensagens na dead-letter (esgotaram as tentativas), com o motivo
  retry    devolve a dead-letter para a fila
  logs     acompanha o log do worker
USO
    exit 1
    ;;
esac
