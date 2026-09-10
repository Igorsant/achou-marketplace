#!/usr/bin/env bash
# Inspeciona o cache Redis do Achou! Marketplace.
set -euo pipefail

R="docker exec achou_redis redis-cli"

case "${1:-ls}" in
  ls)
    total=$($R DBSIZE | tr -d '\r')
    echo "chaves em cache: $total"
    [ "$total" = "0" ] && exit 0
    printf "\n%-46s %-8s %s\n" "CHAVE" "TTL" "TAMANHO"
    printf -- "-%.0s" {1..70}; echo
    $R --scan ${2:+--pattern "$2"} | tr -d '\r' | sort | while read -r k; do
      printf "%-46s %-8s %s B\n" "$k" "$($R TTL "$k" | tr -d '\r')s" "$($R STRLEN "$k" | tr -d '\r')"
    done
    ;;

  get)
    [ $# -lt 2 ] && { echo "uso: $0 get <chave>"; exit 1; }
    $R GET "$2" | python3 -m json.tool
    ;;

  show)
    # Resumo legivel de todas as listagens em cache
    $R --scan --pattern 'products:list:*' | tr -d '\r' | while read -r k; do
      echo "── $k (TTL $($R TTL "$k" | tr -d '\r')s)"
      $R GET "$k" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(f\"   {d['pagination']['total']} resultados\")
for p in d['data'][:5]:
    print(f\"   · {p['title']}\")
" || echo "   (nao e JSON de listagem)"
    done
    ;;

  stats)
    echo "=== hit rate ==="
    $R INFO stats | grep -E 'keyspace_(hits|misses)' | tr -d '\r'
    $R INFO stats | tr -d '\r' | awk -F: '
      /keyspace_hits/   {h=$2}
      /keyspace_misses/ {m=$2}
      END { t=h+m; if (t>0) printf "hit_rate:%.1f%% (%d de %d)\n", 100*h/t, h, t;
            else print "hit_rate:sem dados ainda" }'
    echo ""
    echo "=== memoria ==="
    $R INFO memory | grep -E 'used_memory_human|maxmemory_human' | tr -d '\r'
    ;;

  watch)
    echo "monitorando comandos no Redis (Ctrl+C para sair)..."
    $R MONITOR
    ;;

  flush)
    $R FLUSHALL
    echo "cache limpo"
    ;;

  *)
    cat <<USO
uso: $0 <comando>

  ls [padrao]   lista chaves com TTL e tamanho  (ex: $0 ls 'products:list:*')
  show          resumo legivel das listagens em cache
  get <chave>   imprime o valor em JSON formatado
  stats         hit rate e uso de memoria
  watch         acompanha comandos em tempo real
  flush         limpa o cache
USO
    exit 1
    ;;
esac
