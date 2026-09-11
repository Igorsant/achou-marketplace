#!/usr/bin/env bash
# Inspeciona a fila de notificacoes (BullMQ) e o outbox do Achou! Marketplace.
set -euo pipefail

C="${WORKER_CONTAINER:-achou_worker}"
FILA="notificacoes"
PG="docker exec -i achou_postgres psql -U achou -d achou_marketplace -At"

# Roda um trecho JS dentro do container, com a fila ja aberta em `q`.
# Usa a API do BullMQ em vez de ler as chaves do Redis na mao: o layout
# interno das chaves muda entre versoes, a API nao.
bull() {
  docker exec -i "$C" node -e "
const { Queue } = require('bullmq');
const q = new Queue('$FILA', { connection: { host: process.env.REDIS_HOST, port: +process.env.REDIS_PORT } });
(async () => { $1 })().finally(() => q.close());
"
}

case "${1:-stats}" in
  stats)
    echo "=== outbox ==="
    $PG -c "SELECT 'pendentes:  ' || count(*) FILTER (WHERE published_at IS NULL) || E'\npublicados: ' || count(*) FILTER (WHERE published_at IS NOT NULL) FROM outbox_events"
    echo ""
    echo "=== fila $FILA ==="
    bull "const c = await q.getJobCounts('waiting','active','delayed','completed','failed');
          for (const [k, v] of Object.entries(c)) console.log(k.padEnd(10), v);"
    ;;

  falhas)
    bull "const jobs = await q.getFailed(0, 19);
          if (!jobs.length) return console.log('nenhum job em failed');
          for (const j of jobs) console.log(
            new Date(j.finishedOn).toISOString(), j.data.type,
            j.data.payload?.email ?? '-', '(' + j.attemptsMade + ' tentativas):', j.failedReason);"
    ;;

  retry)
    # Devolve os jobs em failed para a fila, com as tentativas zeradas.
    bull "const n = await q.getJobCountByTypes('failed');
          await q.retryJobs({ state: 'failed' });
          console.log(n + ' job(s) devolvidos para a fila');"
    ;;

  logs)
    docker logs -f --since 5m "$C"
    ;;

  *)
    cat <<USO
uso: $0 <comando>

  stats    eventos pendentes no outbox e jobs por estado na fila
  falhas   ultimos jobs que esgotaram as tentativas, com o motivo
  retry    reprocessa todos os jobs em failed
  logs     acompanha o log do worker

Container usado: $C (troque com WORKER_CONTAINER=...)
USO
    exit 1
    ;;
esac
