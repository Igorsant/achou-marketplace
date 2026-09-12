#!/usr/bin/env bash
# Testes de integracao do backend: sobe o AppModule contra um Postgres real.
#
# uso: scripts/test-e2e.sh [argumentos do jest]
#   scripts/test-e2e.sh                       # tudo
#   scripts/test-e2e.sh adr-0003              # so a suite do ADR 0003
#   scripts/test-e2e.sh -t 'refresh token'    # so um caso
#
# O banco e criado a partir das migrations, nunca do seed: teste que depende de
# dado de seed passa a falhar quando alguem edita o seed por outro motivo.
#
# DATABASE_URL_TEST sobrescreve o destino. O padrao aponta para o Postgres do
# docker-compose (porta 5433) em um banco separado — `achou_test`, nunca
# `achou_marketplace`. O harness de teste recusa banco cujo nome nao termine em
# `_test`, mas a primeira linha de defesa e esta.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
URL="${DATABASE_URL_TEST:-postgresql://achou:achou_dev@localhost:5433/achou_test?schema=public}"
BANCO="$(printf '%s' "$URL" | sed -E 's#.*/([^/?]+).*#\1#')"

case "$BANCO" in
  *_test) ;;
  *) echo "recusando: o banco '$BANCO' nao termina em _test" >&2; exit 1 ;;
esac

# Cria o banco se ainda nao existe. `createdb` falharia se existisse, e o
# `|| true` de sempre esconderia erro de conexao junto — daí o SELECT antes.
ADMIN="$(printf '%s' "$URL" | sed -E "s#/$BANCO(\?.*)?\$#/postgres#")"
ADMIN_LIBPQ="$(printf '%s' "$ADMIN" | sed -E 's/([?&])schema=[^&]*&?/\1/; s/[?&]$//')"
if ! psql "$ADMIN_LIBPQ" -tAXc "SELECT 1 FROM pg_database WHERE datname='$BANCO'" | grep -q 1; then
  echo "criando banco $BANCO"
  psql "$ADMIN_LIBPQ" -qc "CREATE DATABASE \"$BANCO\""
fi

cd "$RAIZ/backend"
export DATABASE_URL="$URL"

echo "aplicando migrations em $BANCO"
npx prisma migrate deploy >/dev/null

npx jest --config test/jest-e2e.config.ts "$@"
