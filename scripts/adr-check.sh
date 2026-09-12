#!/usr/bin/env bash
# Verifica se o codigo ainda cumpre o que os ADRs de docs/adr/ decidiram.
#
# uso: scripts/adr-check.sh [alvo]
#   scripts/adr-check.sh              # docs + 0001 + 0002 + 0003 + pendencias
#   scripts/adr-check.sh 0001         # so um ADR
#   scripts/adr-check.sh docs         # higiene dos ADRs (links, indice, conflitos)
#   scripts/adr-check.sh banco        # invariantes no banco (exige DATABASE_URL e psql)
#   scripts/adr-check.sh pendencias   # relatorio das pendencias (nunca falha)
#
# Duas categorias, deliberadamente separadas:
#
#   invariante  decisao ja materializada no codigo. Quebrar significa que o
#               codigo contradiz um ADR aceito sem um ADR novo que o substitua.
#               Derruba o build.
#
#   pendencia   o que o ADR registra como nao feito. Aparece no relatorio e nao
#               derruba o build. Em quatro graus, que nao sao a mesma coisa:
#
#                 DIFERIDA  decidido e fora do escopo do MVP de proposito. O
#                           contrato ja esta escrito na suite de integracao.
#                 BLOQUEIA  a feature foi declarada pronta e nao esta. Defeito.
#                 DIVIDA    funciona, com custo registrado para depois.
#                 ABERTA    questao que o ADR levanta e nao decide.
#
# A segunda categoria existe porque um ADR honesto documenta o que falta. Se o
# que falta derrubasse o build, o pipeline nasceria vermelho e ninguem olharia.
# E DIFERIDA nao pode ser lida como BLOQUEIA: escopo cortado de propriedade nao
# e a mesma coisa que promessa nao cumprida.
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$RAIZ/backend/prisma/schema.prisma"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ALVO="${1:-all}"
FALHAS=0
OKS=0
PENDENTES=0
RESOLVIDAS=0

if [ -t 1 ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  V=$'\033[32m'; R=$'\033[31m'; A=$'\033[33m'; C=$'\033[36m'; Z=$'\033[0m'
else
  V=""; R=""; A=""; C=""; Z=""
fi

RESUMO="$TMP/resumo.md"
: > "$RESUMO"

# ------------------------------------------------------------------ saida

titulo() {
  printf "\n%s== %s%s\n" "$C" "$1" "$Z"
  echo "## $1" >> "$RESUMO"
  echo >> "$RESUMO"
}

ok() { # <ref> <descricao>
  OKS=$((OKS + 1))
  printf "  %s✓%s %-12s %s\n" "$V" "$Z" "$1" "$2"
}

falha() { # <ref> <descricao> <arquivo>
  FALHAS=$((FALHAS + 1))
  printf "  %s✗%s %-12s %s\n" "$R" "$Z" "$1" "$2"
  printf -- "- ❌ \`%s\` %s — \`%s\`\n" "$1" "$2" "$3" >> "$RESUMO"
  # Anotacao do GitHub: a falha aparece na linha do arquivo, dentro do diff do
  # PR, em vez de so no log do job.
  [ -n "${GITHUB_ACTIONS:-}" ] && printf "::error file=%s,title=%s::%s\n" "$3" "$1" "$2"
  return 0
}

# ------------------------------------------------------------------ helpers

# Resolve o alvo de grep: aceita arquivo ou diretorio, sempre relativo a raiz.
_existe() { [ -e "$RAIZ/$1" ]; }

# `grep -rq` nao serve: no BSD grep do macOS ele devolve 0 em diretorio sem
# match nenhum (o CI, com GNU grep, nao reproduz — o script mentiria so na
# maquina de quem escreve o codigo). Entao testamos a lista de arquivos.
_casa() { # <caminho absoluto> <regex> [-i]
  [ -n "$(grep -rlE ${3:-} --exclude-dir=node_modules --exclude-dir=.terraform \
    --exclude-dir=dist --exclude-dir=.dart_tool -- "$2" "$1" 2>/dev/null | head -n1)" ]
}

exige() { # <ref> <caminho> <regex> <descricao>
  if ! _existe "$2"; then
    falha "$1" "$4 (caminho ausente: $2)" "$2"
    return
  fi
  if _casa "$RAIZ/$2" "$3"; then ok "$1" "$4"; else falha "$1" "$4" "$2"; fi
}

proibe() { # <ref> <caminho> <regex> <descricao>
  if ! _existe "$2"; then ok "$1" "$4 (caminho ausente)"; return; fi
  if _casa "$RAIZ/$2" "$3" -i; then falha "$1" "$4" "$2"; else ok "$1" "$4"; fi
}

# Isola um bloco `model X { ... }` ou `enum X { ... }` do schema.prisma. Sem
# isso, uma checagem sobre CartItem casaria com qualquer linha do arquivo.
bloco() { # <model|enum> <Nome>
  awk -v t="$1" -v n="$2" '$1==t && $2==n {d=1} d {print} d && /^}/ {exit}' "$SCHEMA"
}

exige_modelo() { # <ref> <Modelo> <regex> <descricao>
  local b="$TMP/m_$2"
  bloco model "$2" > "$b"
  if [ ! -s "$b" ]; then falha "$1" "$4 (model $2 nao existe)" "backend/prisma/schema.prisma"; return; fi
  if grep -qE -- "$3" "$b"; then ok "$1" "$4"; else falha "$1" "$4" "backend/prisma/schema.prisma"; fi
}

proibe_modelo() { # <ref> <Modelo> <regex> <descricao>
  local b="$TMP/m_$2"
  bloco model "$2" > "$b"
  if [ ! -s "$b" ]; then falha "$1" "$4 (model $2 nao existe)" "backend/prisma/schema.prisma"; return; fi
  if grep -qiE -- "$3" "$b"; then falha "$1" "$4" "backend/prisma/schema.prisma"; else ok "$1" "$4"; fi
}

# Igualdade de conjunto, nao continencia: o ADR 0001 diz que a decisao "nao
# inventa estado novo". Valor a mais e tao violacao quanto valor a menos.
enum_igual() { # <ref> <Enum> <descricao> <valor>...
  local ref="$1" nome="$2" desc="$3"; shift 3
  local esperado atual
  esperado="$(printf '%s\n' "$@" | sort | tr '\n' ' ')"
  atual="$(bloco enum "$nome" | awk 'NR>1 && NF && $1!="}" {print $1}' | sort | tr '\n' ' ')"
  if [ "$esperado" = "$atual" ]; then
    ok "$ref" "$desc"
  else
    falha "$ref" "$desc (esperado: $esperado| encontrado: $atual)" "backend/prisma/schema.prisma"
  fi
}

pendencia() { # <ref> <diferida|bloqueante|divida|aberta> <descricao> <teste de resolucao>
  local marca
  case "$2" in
    # Decidido e fora do escopo do MVP de proposito. Nao e defeito: o ADR
    # registra a decisao e a suite de integracao ja tem o contrato escrito.
    diferida)   marca="DIFERIDA" ;;
    # A feature foi declarada pronta e nao esta. Isso, sim, e defeito.
    bloqueante) marca="BLOQUEIA" ;;
    divida)     marca="DIVIDA" ;;
    *)          marca="ABERTA" ;;
  esac
  if eval "$4" >/dev/null 2>&1; then
    RESOLVIDAS=$((RESOLVIDAS + 1))
    printf "  %s↑%s %-12s %s\n" "$V" "$Z" "$1" "$3"
    printf "      %sresolvida — promova a invariante e atualize o ADR%s\n" "$V" "$Z"
    printf -- "- ✅ \`%s\` **%s** %s — *resolvida: promova a invariante e atualize o ADR*\n" "$1" "$marca" "$3" >> "$RESUMO"
  else
    PENDENTES=$((PENDENTES + 1))
    printf "  %s·%s %-12s [%s] %s\n" "$A" "$Z" "$1" "$marca" "$3"
    printf -- "- ⏳ \`%s\` **%s** %s\n" "$1" "$marca" "$3" >> "$RESUMO"
  fi
}

# ============================================================ higiene dos ADRs

checar_docs() {
  titulo "Higiene dos ADRs"

  # Marcador de conflito em qualquer arquivo versionado. Nao e uma regra de ADR,
  # e o pre-requisito de todas: um arquivo com conflito nao compila nem descreve
  # decisao nenhuma.
  local conflitos
  conflitos="$(cd "$RAIZ" && git grep -lE '^(<{7}|={7}|>{7})( |$)' -- . 2>/dev/null \
    | grep -vE '^scripts/adr-check\.sh$' || true)"
  if [ -n "$conflitos" ]; then
    while read -r f; do
      [ -n "$f" ] && falha "git" "marcador de conflito de merge nao resolvido em $f" "$f"
    done <<< "$conflitos"
  else
    ok "git" "nenhum marcador de conflito de merge versionado"
  fi

  local dir="$RAIZ/docs/adr" indice="$RAIZ/docs/adr/README.md"
  [ -f "$indice" ] || falha "adr" "docs/adr/README.md (indice) nao existe" "docs/adr/README.md"

  local esperado=1 f base num
  for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
    base="$(basename "$f")"
    num="${base%%-*}"

    # Numeracao contigua: um ADR pulado e um ADR perdido.
    if [ "$num" != "$(printf '%04d' "$esperado")" ]; then
      falha "adr" "numeracao fora de sequencia: esperado $(printf '%04d' "$esperado"), achei $num" "docs/adr/$base"
    else
      ok "adr" "$base numerado em sequencia"
    fi
    esperado=$((esperado + 1))

    # Cabecalho e tabela de metadados: sem Status e Data um ADR nao diz se vale.
    grep -qE "^# ADR $num — " "$f" \
      && ok "adr" "$base tem cabecalho \"# ADR $num — ...\"" \
      || falha "adr" "$base sem cabecalho \"# ADR $num — <titulo>\"" "docs/adr/$base"

    local campo
    for campo in Status Data Decisores; do
      grep -qE "^\| \*\*$campo\*\* \|" "$f" \
        && ok "adr" "$base declara $campo" \
        || falha "adr" "$base nao declara $campo na tabela de metadados" "docs/adr/$base"
    done

    # Aceito, Proposto, Substituido: qualquer outra coisa e status inventado.
    local status
    status="$(grep -E '^\| \*\*Status\*\* \|' "$f" | sed -E 's/.*\| \*\*Status\*\* \| ([^|]*) \|.*/\1/' | awk '{print $1}')"
    case "$status" in
      Aceito|Proposto|Rejeitado|Substituido|Substituído|Depreciado)
        ok "adr" "$base com status conhecido ($status)" ;;
      *)
        falha "adr" "$base com status desconhecido: '$status'" "docs/adr/$base" ;;
    esac

    grep -q "$base" "$indice" \
      && ok "adr" "$base listado no indice" \
      || falha "adr" "$base nao esta na tabela de docs/adr/README.md" "docs/adr/README.md"
  done

  # Link relativo quebrado e o sintoma de ADR que envelheceu: o arquivo que a
  # decisao citava foi movido ou apagado e a decisao nao foi revisitada.
  local quebrados=0 alvo destino
  for f in "$dir"/*.md; do
    while read -r alvo; do
      case "$alvo" in http*|\#*|mailto*) continue ;; esac
      destino="${alvo%%#*}"
      [ -z "$destino" ] && continue
      if [ ! -e "$dir/$destino" ]; then
        falha "adr" "link quebrado em $(basename "$f"): $alvo" "docs/adr/$(basename "$f")"
        quebrados=$((quebrados + 1))
      fi
    done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
  done
  [ "$quebrados" -eq 0 ] && ok "adr" "todos os links relativos dos ADRs resolvem"
}

# ================================================= ADR 0001 — interface REST

checar_0001() {
  titulo "ADR 0001 — REST sobre recursos, versionada no path"

  local controllers rotas

  # §2.2 — todo controller do contrato do cliente vive sob /v1. `health` fica
  # de fora de proposito: e sonda de infraestrutura, e os manifestos do
  # Kubernetes apontam para ela sem versao.
  controllers="$(grep -rhoE "@Controller\('[^']*'\)" "$RAIZ/backend/src" --include='*.ts' \
    | sed -E "s/@Controller\('([^']*)'\)/\1/" | sort -u)"
  if [ -z "$controllers" ]; then
    falha "§2.2" "nenhum @Controller encontrado em backend/src" "backend/src"
  else
    local fora=""
    while read -r c; do
      [ -z "$c" ] && continue
      case "$c" in
        v1/*|health) ;;
        *) fora="$fora $c" ;;
      esac
    done <<< "$controllers"
    if [ -n "$fora" ]; then
      falha "§2.2" "controller fora de /v1 (e nao e a sonda health):$fora" "backend/src"
    else
      ok "§2.2" "todo controller do contrato vive sob /v1 (health fora, por ser sonda)"
    fi
  fi

  # §2.1 — o recurso esta no path e a acao no metodo. Verbo no caminho e o
  # sintoma de RPC sobre HTTP: se a acao esta na URL, o metodo deixa de
  # significar algo e cache, retry e idempotencia viram convencao local.
  #
  # A allowlist e a excecao declarada no §2.1: auth/login, register e refresh
  # sao acoes porque a sessao nao existe como recurso (ADR 0003 §2.1). Rota de
  # acao *nova* continua falhando aqui.
  rotas="$(grep -rhoE "@(Get|Post|Patch|Put|Delete)\('[^']*'\)" "$RAIZ/backend/src" --include='*.ts' \
    | sed -E "s/@[A-Za-z]+\('([^']*)'\)/\1/" | sort -u)"
  local verbos=""
  while read -r r; do
    [ -z "$r" ] && continue
    case "$r" in
      login|register|refresh) continue ;;
    esac
    if printf '%s' "$r" | grep -qiE '(criar|listar|buscar|atualizar|deletar|remover|salvar|^get[A-Z]?|^create|^update|^delete|^list|^fetch|^add|^set)'; then
      verbos="$verbos $r"
    fi
  done <<< "$rotas"
  if [ -n "$verbos" ]; then
    falha "§2.1" "verbo no path (RPC sobre HTTP):$verbos" "backend/src"
  else
    ok "§2.1" "nenhum verbo no path fora da allowlist de auth"
  fi

  # §2.3 — o resultado vai no status. Envelope de sucesso que carrega falha
  # desliga retry por classe, alerta por taxa de 5xx e cache negativo.
  proibe "§2.3" backend/src '(success *: *(true|false)|"success" *:)' \
    "nenhuma resposta decide sucesso por campo do corpo"

  # §2.4 — o envelope de erro e unico porque um filtro global normaliza tudo,
  # inclusive a saida do ValidationPipe.
  exige "§2.4" backend/src/main.ts 'useGlobalFilters\(new HttpExceptionFilter' \
    "filtro de excecao global registrado (sem ele o ValidationPipe fura o contrato)"
  exige "§2.4" backend/src/common/filters/http-exception.filter.ts 'error: \{' \
    "o filtro devolve o envelope { error: { code, message } }"
  exige "§2.4" backend/src/common/filters/http-exception.filter.ts 'VALIDACAO_FALHOU' \
    "erro de validacao entra no mesmo envelope, com details"

  # §2.4 — `code` e identificador estavel consumido pelo app; `message` e texto
  # de tela. Codigo em minuscula ou com espaco quebra essa separacao.
  local codigos ruins=""
  codigos="$(grep -rhoE "code: '[^']*'" "$RAIZ/backend/src" --include='*.ts' \
    | sed -E "s/code: '([^']*)'/\1/" | sort -u)"
  while read -r c; do
    [ -z "$c" ] && continue
    printf '%s' "$c" | grep -qE '^[A-Z][A-Z0-9_]*$' || ruins="$ruins $c"
  done <<< "$codigos"
  if [ -n "$ruins" ]; then
    falha "§2.4" "code de erro fora de SCREAMING_SNAKE_CASE:$ruins" "backend/src"
  else
    ok "§2.4" "todo code de erro e identificador estavel ($(printf '%s' "$codigos" | grep -c .) codigos)"
  fi

  # §2.5 — POST nao e idempotente por definicao do metodo; o header e a
  # compensacao, e quem gera e o cliente.
  exige "§2.5" app_achou/lib/features/checkout/checkout_page.dart 'idempotencyKey' \
    "o cliente gera a chave de idempotencia da escrita cobravel"

  # §2.6 — a separacao de audiencia esta no prefixo, que e o vocabulario do
  # gateway e da CDN; nao em campo do corpo.
  exige "§2.6" backend/src/seller/seller-products.controller.ts "@Controller\('v1/seller'\)" \
    "o painel do lojista vive sob o prefixo /v1/seller"
  exige "§2.6" backend/src/seller/seller-products.controller.ts '@Roles\(Role.LOJISTA\)' \
    "o prefixo privado carrega a exigencia de papel"
  proibe "§2.6" backend/src/products/products.controller.ts '@UseGuards' \
    "a vitrine publica nao exige credencial (e o que a torna cacheavel na borda)"

  # A decisao de estilo nao pode ser revertida por dependencia nova sem um ADR
  # que substitua este.
  proibe "§3" backend/package.json '(@nestjs/graphql|apollo-server|type-graphql|@grpc/|nice-grpc)' \
    "nenhuma dependencia de GraphQL ou gRPC entrou sem ADR que substitua este"
}

# ======================================================= ADR 0002 — carrinho

checar_0002() {
  titulo "ADR 0002 — carrinho no servidor, multi-lojista, sem reserva"

  # §2.1: o carrinho nao congela valor nem imobiliza estoque. O schema e onde
  # essa decisao vive — a ausencia da coluna e a propria decisao.
  proibe_modelo "§2.2" CartItem '(price|preco|valor|reserv|expira|ttl)' \
    "cart_items nao tem preco, reserva nem validade"
  exige_modelo "§2.2" CartItem 'quantity +Int' "cart_items guarda apenas productId e quantity"
  exige_modelo "§2.2" CartItem '@@unique\(\[cartId, productId\]\)' "uma linha por produto no carrinho"

  # §2.2: um carrinho por usuario, e nao existe carrinho sem usuario.
  exige_modelo "§2.2" Cart 'userId +String +@unique' "carts.user_id e UNIQUE: um carrinho por usuario, sempre"
  proibe_modelo "§2.2" Cart 'userId +String\?' "carts.user_id nao e opcional"
  proibe "§2.2" backend/prisma/schema.prisma '(guestId|deviceId|anonymousId|visitanteId)' \
    "nenhuma identidade de convidado: carrinho anonimo fica para §5.3"
  exige "§2.2" backend/src/auth/auth.service.ts 'cart: \{ create: \{\} \}' \
    "register cria o carrinho do comprador (rota de carrinho nunca trata carrinho ausente)"

  # §2.3: o split por lojista depende de order_items carregar sellerId.
  exige_modelo "§2.3" OrderItem 'sellerId +String' "order_items carrega seller_id: e o que permite um pedido por lojista"
  exige_modelo "§2.3" OrderItem '@@index\(\[sellerId\]\)' "indice por sellerId: o painel do lojista le por ele"

  if [ -d "$RAIZ/backend/src/cart" ]; then
    exige "§2.2" backend/src/cart 'COMPRADOR' "rotas de carrinho exigem o papel COMPRADOR"
    proibe "§2.2" backend/src/cart '(priceCents *: *dto|unitPriceCents)' "o carrinho nunca aceita preco do cliente"
    exige "§4"   backend/src/cart '(status *: *(ProductStatus\.)?ACTIVE|indisponivel|unavailable)' \
      "GET /cart marca item indisponivel em vez de sumir com ele"
  else
    printf "  %s·%s %-12s modulo backend/src/cart ainda nao existe: 3 checagens armadas para quando existir\n" "$A" "$Z" "§2"
  fi

  if [ -d "$RAIZ/backend/src/orders" ]; then
    exige "§2.3" backend/src/orders '(groupBy|sellerId)' "checkout agrupa o carrinho por lojista"
    exige "§2.3" backend/src/orders '\$\{.*sellerId\}|:\$\{seller' "Idempotency-Key derivada por lojista ({key}:{sellerId})"
  fi
}

# ======================================================== ADR 0003 — sessao

checar_0003() {
  titulo "ADR 0003 — sessao JWT stateless com par access/refresh"

  local strat=backend/src/auth/jwt.strategy.ts
  local serv=backend/src/auth/auth.service.ts
  local guard=backend/src/auth/guards/roles.guard.ts

  # §2.2: esta e a checagem que sustenta o ADR inteiro. Sem ela, o refresh de 7
  # dias vale como access e a janela de 15 minutos e decorativa.
  exige "§2.2" "$strat" "payload\.type === 'refresh'" \
    "JwtStrategy recusa refresh token usado como access token"
  exige "§2.2" "$serv" "payload\.type !== 'refresh'" \
    "/auth/refresh recusa access token usado como refresh"

  # §2.1: validar sem I/O. Um SELECT aqui quebra a validacao na borda.
  exige "§2.1" "$strat" 'ignoreExpiration: false' "sem tolerancia de expiracao"
  proibe "§2.1" "$strat" '(PrismaService|prisma\.)' "JwtStrategy valida sem ir ao banco"
  proibe "§2.1" "$guard" '(PrismaService|prisma\.)' "RolesGuard autoriza sem ir ao banco"
  proibe "§2.1" backend/prisma/schema.prisma '(model +Session|model +Sessao|@@map\("sessions"\))' \
    "nenhuma tabela de sessao: a sessao e o proprio token"

  # §2.2: os dois tokens saem da mesma chave e se distinguem pelo campo type.
  exige "§2.2" "$serv" "type: 'access'" "access token declara type: access"
  exige "§2.2" "$serv" "type: 'refresh'" "refresh token declara type: refresh"
  exige "§2.2" "$serv" "'JWT_ACCESS_EXPIRES', *'15m'" "access token: 15 min por padrao"
  exige "§2.2" "$serv" "'JWT_REFRESH_EXPIRES', *'7d'" "refresh token: 7 dias por padrao"
  exige "§2.2" backend/.env.example 'JWT_ACCESS_EXPIRES' "as duracoes sao configuraveis e estao documentadas"
  exige "§2.2" backend/.env.example 'JWT_REFRESH_EXPIRES' "duracao do refresh documentada no .env.example"

  # §2.3: role e sellerId no payload sao o que torna /v1/seller/* barato.
  exige "§2.3" "$strat" 'role: UsuarioLogado' "role viaja no payload do token"
  exige "§2.3" "$strat" 'sellerId\?: string' "sellerId viaja no payload do token"
  exige "§2.3" "$guard" 'user\.role' "RolesGuard autoriza lendo o role do payload"

  # §2.4: mensagem distinta por causa de falha permite enumerar contas.
  exige "§2.4" "$serv" 'CREDENCIAIS_INVALIDAS' "login devolve CREDENCIAIS_INVALIDAS"
  proibe "§2.4" "$serv" '(EMAIL_NAO_ENCONTRADO|EMAIL_INEXISTENTE|USUARIO_NAO_ENCONTRADO|SENHA_INVALIDA|SENHA_INCORRETA)' \
    "erro de login e o mesmo para e-mail inexistente e senha errada"

  # §2.2 tambem vale para o que sobe: duracao divergente no cluster faz o ADR
  # descrever um sistema que nao e o que roda.
  exige "§2.2" deploy/k8s/base/kustomization.yaml 'JWT_ACCESS_EXPIRES=15m' \
    "o cluster usa o access token de 15 min da decisao"
  exige "§2.2" deploy/k8s/base/kustomization.yaml 'JWT_REFRESH_EXPIRES=7d' \
    "o cluster usa o refresh token de 7 dias da decisao"

  # Divida tecnica do §4: segredo de assinatura em arquivo versionado vale o
  # mesmo que o fallback 'dev_secret' — qualquer um forja token de lojista.
  proibe "divida" deploy/k8s/overlays/oci 'JWT_SECRET *[=:]' \
    "overlay de producao nao carrega JWT_SECRET versionado (vem do Secret do Terraform)"

  # §5.3: HS256 basta enquanto o mesmo processo emite e valida. O ADR manda
  # migrar para RS256 *antes* de o gateway validar na borda — quem valida com a
  # chave compartilhada tambem consegue assinar.
  local gateway="" manifestos
  if [ -n "$(grep -rl --include='*.tf' -- 'oci_apigateway' "$RAIZ/infra" 2>/dev/null | head -n1)" ]; then
    gateway="Terraform (oci_apigateway)"
  fi
  manifestos="$(grep -rlE 'kind: *(Ingress|Gateway|HTTPRoute)' "$RAIZ/deploy/k8s" 2>/dev/null || true)"
  if [ -n "$manifestos" ] && printf '%s\n' "$manifestos" | xargs grep -liE 'jwt' 2>/dev/null | grep -q .; then
    gateway="manifesto de Ingress/Gateway com JWT"
  fi
  if [ -n "$gateway" ]; then
    exige "§5.3" backend/src/auth 'RS256' \
      "$gateway valida na borda: a decisao exige RS256 antes desse passo"
  else
    ok "§5.3" "nenhum gateway valida JWT na borda ainda: HS256 segue suficiente"
  fi
}

# ====================================================== invariantes no banco

# Grep no schema.prisma prova intencao; isto prova resultado. Roda depois de
# `prisma migrate deploy` e pergunta ao Postgres se as constraints que os ADRs
# dependem existem de fato.
checar_banco() {
  titulo "Invariantes no banco (pos migrate deploy)"

  if ! command -v psql >/dev/null 2>&1; then
    falha "banco" "psql nao esta no PATH" "scripts/adr-check.sh"
    return
  fi
  if [ -z "${DATABASE_URL:-}" ]; then
    falha "banco" "DATABASE_URL nao definida" "scripts/adr-check.sh"
    return
  fi

  # `?schema=public` e parametro do Prisma: a libpq recusa a URL inteira por
  # causa dele. Tiramos so esse par, preservando sslmode e companhia.
  local url
  url="$(printf '%s' "$DATABASE_URL" | sed -E 's/([?&])schema=[^&]*&?/\1/; s/[?&]$//')"

  q() { psql "$url" -tAX -c "$1" 2>/dev/null | tr -d '[:space:]'; }

  vazio() { # <ref> <sql> <descricao>
    local r; r="$(q "$2")"
    if [ -z "$r" ] || [ "$r" = "0" ]; then ok "$1" "$3"; else falha "$1" "$3 (encontrei: $r)" "backend/prisma/schema.prisma"; fi
  }
  nao_vazio() { # <ref> <sql> <descricao>
    local r; r="$(q "$2")"
    if [ -n "$r" ] && [ "$r" != "0" ]; then ok "$1" "$3"; else falha "$1" "$3" "backend/prisma/schema.prisma"; fi
  }

  # ADR 0002 §2.1 — o carrinho nao congela valor: nenhuma coluna de preco.
  vazio "0002 §2.1" \
    "SELECT count(*) FROM information_schema.columns WHERE table_name='cart_items' AND (column_name LIKE '%price%' OR column_name LIKE '%preco%' OR column_name LIKE '%valor%')" \
    "cart_items nao tem coluna de preco no banco"

  # ADR 0002 §2.2 — um carrinho por usuario.
  nao_vazio "0002 §2.2" \
    "SELECT count(*) FROM pg_indexes WHERE tablename='carts' AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%user_id%'" \
    "indice UNIQUE em carts(user_id)"
  nao_vazio "0002 §2.1" \
    "SELECT count(*) FROM pg_indexes WHERE tablename='cart_items' AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%cart_id%' AND indexdef LIKE '%product_id%'" \
    "indice UNIQUE em cart_items(cart_id, product_id)"
  vazio "0002 §2.2" \
    "SELECT count(*) FROM information_schema.columns WHERE table_name='carts' AND column_name='user_id' AND is_nullable='YES'" \
    "carts.user_id e NOT NULL: nao existe carrinho anonimo"

  # ADR 0001 §3.3 — idempotencia e responsabilidade do banco, nao do app.
  nao_vazio "0001 §3.3" \
    "SELECT count(*) FROM pg_indexes WHERE tablename='orders' AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%idempotency_key%'" \
    "indice UNIQUE em orders(idempotency_key)"

  # ADR 0001 §3.4 — snapshot de preco.
  nao_vazio "0001 §3.4" \
    "SELECT count(*) FROM information_schema.columns WHERE table_name='order_items' AND column_name IN ('unit_price_cents','title_snapshot') HAVING count(*)=2" \
    "order_items tem unit_price_cents e title_snapshot"

  # ADR 0001 divida tecnica — provider continua texto, nao enum.
  nao_vazio "0001 divida" \
    "SELECT count(*) FROM information_schema.columns WHERE table_name='payments' AND column_name='provider' AND data_type='text'" \
    "payments.provider e text (aceita o nome do PSP sem migration de enum)"

  # ADR 0003 §2.1 — stateless: nenhuma tabela de sessao.
  vazio "0003 §2.1" \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('sessions','sessoes')" \
    "nenhuma tabela de sessao no banco"
}

# ============================================================== pendencias

# O que os proprios ADRs registram como nao feito. O quarto argumento e o teste
# que passa quando a pendencia for resolvida — e ai o script cobra a atualizacao
# do ADR, que e como um ADR deixa de envelhecer em silencio.
relatorio_pendencias() {
  titulo "Pendencias declaradas nos ADRs (relatorio, nao derruba o build)"

  printf "\n  %sADR 0001%s\n" "$C" "$Z"
  pendencia "0001 §4"   divida     "nenhuma rota emite ETag ou Cache-Control: o cache HTTP do estilo nao foi usado" \
    "grep -rqE 'ETag|Cache-Control' '$RAIZ/backend/src'"
  pendencia "0001 §5.1" aberta     "paginacao por limit/offset; cursor nao foi decidido explicitamente" false
  pendencia "0001 §5.2" aberta     "recurso agregado para a home, se as N requisicoes virarem problema medido" false
  pendencia "0001 §5.3" aberta     "PUT nao e usado em lugar nenhum — regra ou caso a caso?" false

  printf "\n  %sADR 0002%s\n" "$C" "$Z"
  pendencia "0002 §7"   diferida   "/v1/cart nao implementado — escopo diferido, contrato em test/adr-0002-*" \
    "[ -d '$RAIZ/backend/src/cart' ]"
  pendencia "0002 §7"   diferida   "CartController ainda e a fonte da verdade (sacola em memoria)" \
    "grep -rqE 'class (Http)?CartRepository' '$RAIZ/app_achou/lib'"
  pendencia "0002 §4"   divida     "flatShippingCents = 2490 continua no cliente" \
    "! grep -q 'flatShippingCents' '$RAIZ/app_achou/lib/state/cart_controller.dart'"
  pendencia "0002 §4"   divida     "cart_items sem indice por productId" \
    "bloco model CartItem | grep -qE '@@index\\(\\[productId\\]\\)'"
  pendencia "0002 §5.1" aberta     "sem teto de quantidade por item no carrinho" false
  pendencia "0002 §5.2" aberta     "sem TTL de carrinho (item de um ano atras ainda aparece)" false
  pendencia "0002 §5.3" aberta     "carrinho anonimo com merge no login nao decidido" false

  printf "\n  %sADR 0003%s\n" "$C" "$Z"
  pendencia "0003 §5.1" bloqueante "sessao nao sobrevive a fechar o app (refresh token nao persistido)" \
    "grep -q 'flutter_secure_storage' '$RAIZ/app_achou/pubspec.yaml'"
  pendencia "0003 §5.2" bloqueante "SessionController recusa COMPRADOR — bloqueia o ADR 0002 §2.2" \
    "! grep -q 'nao e de lojista\|não é de lojista' '$RAIZ/app_achou/lib/state/session_controller.dart'"
  pendencia "0003 §4"   divida     "JWT_SECRET tem fallback 'dev_secret': deve virar falha de boot em producao" \
    "! grep -rq \"?? 'dev_secret'\" '$RAIZ/backend/src'"
  pendencia "0003 §5.3" aberta     "RS256 ainda nao adotado (obrigatorio antes do gateway validar na borda)" \
    "grep -rq 'RS256' '$RAIZ/backend/src'"
  pendencia "0003 §6.1" aberta     "recuperacao de senha nao existe" \
    "grep -rqiE 'forgot|recuperar-senha|reset-password' '$RAIZ/backend/src/auth'"
  pendencia "0003 §6.2" aberta     "rate limit proprio no /auth/login" \
    "grep -q 'Throttle' '$RAIZ/backend/src/auth/auth.controller.ts'"
  pendencia "0003 §6.3" aberta     "cost 10 do bcrypt e default, nao medicao" false
}

# ==================================================================== main

case "$ALVO" in
  docs)       checar_docs ;;
  0001)       checar_0001 ;;
  0002)       checar_0002 ;;
  0003)       checar_0003 ;;
  banco)      checar_banco ;;
  pendencias) relatorio_pendencias ;;
  all)
    checar_docs
    checar_0001
    checar_0002
    checar_0003
    relatorio_pendencias
    ;;
  *)
    echo "alvo desconhecido: $ALVO (use docs, 0001, 0002, 0003, banco, pendencias ou all)" >&2
    exit 64
    ;;
esac

printf "\n%s──%s %d invariantes ok, %s%d quebradas%s" "$C" "$Z" "$OKS" "$([ "$FALHAS" -gt 0 ] && echo "$R" || echo "$V")" "$FALHAS" "$Z"
[ $((PENDENTES + RESOLVIDAS)) -gt 0 ] && printf ", %d pendencias abertas, %d prontas para promover" "$PENDENTES" "$RESOLVIDAS"
printf "\n"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Conformidade com os ADRs — \`$ALVO\`"
    echo
    echo "| invariantes ok | invariantes quebradas | pendencias abertas | prontas para promover |"
    echo "|---|---|---|---|"
    echo "| $OKS | $FALHAS | $PENDENTES | $RESOLVIDAS |"
    echo
    cat "$RESUMO"
  } >> "$GITHUB_STEP_SUMMARY"
fi

[ "$FALHAS" -eq 0 ] || exit 1
exit 0
