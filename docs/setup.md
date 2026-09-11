# Setup local

## Estrutura do monorepo

```
achou-marketplace/
├── docker-compose.yml    # orquestra todos os servicos
├── docs/                 # documentacao do projeto
├── backend/              # API Node.js/NestJS
│   ├── src/
│   ├── prisma/
│   └── package.json
└── frontend/             # app Flutter (ainda nao criado)
```

## Subir tudo

O compose roda da **raiz**; os comandos do Prisma rodam de **`backend/`**.

```bash
# 1. crie o .env a partir do exemplo (ele NAO vai para o git)
cp backend/.env.example backend/.env
# preencha os valores -- os defaults de desenvolvimento estao na tabela abaixo

# 2. na raiz
docker compose up -d --build

# em backend/
cd backend
npx prisma migrate deploy     # aplica as migrations
npx ts-node prisma/seed.ts    # dados de exemplo
```

API em `http://localhost:3001`, Swagger em `/docs`.

### Valores de desenvolvimento para o `.env`

```env
NODE_ENV=development
PORT=3000
DATABASE_URL="postgresql://achou:achou_dev@localhost:5433/achou_marketplace?schema=public"
REDIS_HOST=localhost
REDIS_PORT=6380
JWT_SECRET=dev_secret_trocar_em_producao
JWT_ACCESS_EXPIRES=15m
JWT_REFRESH_EXPIRES=7d
CACHE_TTL_PRODUCT=300
CACHE_TTL_LIST=120
OUTBOX_POLL_INTERVAL_MS=5000
OUTBOX_BATCH_SIZE=100
NOTIFICATION_MOCK_FAILURE_RATE=0
```

> `DATABASE_URL` e `REDIS_HOST` acima usam `localhost` porque servem aos comandos
> rodados **da sua maquina** (Prisma CLI, seed). O container da API sobrescreve os
> dois pelo `docker-compose.yml`, apontando para os hostnames da rede Docker.

## Portas

As portas padrao (5432 e 6379) ja estavam ocupadas por outros projetos nesta
maquina, entao o compose expoe em portas alternativas. **Dentro** da rede Docker
os servicos continuam nas portas normais.

| Servico | Host | Container |
|---|---|---|
| API | **3001** | 3000 (metricas em 9464, so na rede interna) |
| Worker | — | metricas em 9465, so na rede interna |
| PostgreSQL | **5433** | 5432 |
| Redis | **6380** | 6379 |
| Prometheus | **9090** | 9090 |
| Grafana | **3002** | 3000 — login `admin` / `achou_dev` |

O `worker` usa a mesma imagem da API com outro entrypoint (`src/worker.ts`):
roda o relay do outbox e o consumidor da fila de notificacoes. Nao atende HTTP;
so serve `/metrics` para o Prometheus. Fora do Docker: `npm run start:worker:dev`
em `backend/`.

Metricas, dashboard e alertas: [observabilidade.md](observabilidade.md).

## Usuarios do seed

| E-mail | Senha | Papel |
|---|---|---|
| `lojista@achou.com` | `senha123` | LOJISTA |
| `comprador@achou.com` | `senha123` | COMPRADOR |

## Migrations escritas a mao

> Todos os comandos `prisma` rodam de dentro de `backend/`.

Nunca use `prisma migrate dev` direto para criar migration -- ele gera o SQL
sozinho. O fluxo e sempre em dois passos:

```bash
npx prisma migrate dev --create-only --name nome_da_migration   # gera, nao aplica
# edite backend/prisma/migrations/<timestamp>_nome/migration.sql
npx prisma migrate dev                                          # aplica
```

Para mudancas que o Prisma nao deriva do schema (extensoes, funcoes, colunas
geradas, indices parciais), o `--create-only` gera um arquivo vazio e voce
escreve o SQL inteiro. Foi assim que nasceu `busca_sem_acento`.

## Verificar drift antes de aplicar

```bash
npx prisma migrate diff \
  --from-schema-datasource prisma/schema.prisma \
  --to-schema-datamodel prisma/schema.prisma \
  --script
```

O esperado e `-- This is an empty migration.`. Qualquer `DROP INDEX` ou
`DROP DEFAULT` no resultado significa que o Prisma vai destruir SQL manual no
proximo `migrate dev`.

## Se o migrate travar com P1002

Um `migrate dev` interrompido a forca deixa a conexao segurando o advisory lock
do Prisma, e os proximos comandos ficam na fila ate dar timeout:

```bash
docker exec -i achou_postgres psql -U achou -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
   WHERE datname='achou_marketplace' AND pid <> pg_backend_pid();"
```

## Testar a busca

```bash
curl 'http://localhost:3001/v1/products?q=tenis'          # sem acento
curl 'http://localhost:3001/v1/products?q=corrida'
curl 'http://localhost:3001/v1/products?sort=price_asc'
curl 'http://localhost:3001/v1/products?category=calcados&maxPrice=30000'
```

## Verificar o cache

```bash
# 1a chamada popula o cache
curl 'http://localhost:3001/v1/products?q=tenis'
docker exec achou_redis redis-cli KEYS '*'
docker exec achou_redis redis-cli TTL products:list:<hash>

# prova que o cache serve: altera o banco por fora e a API nao ve
docker exec -i achou_postgres psql -U achou -d achou_marketplace -c \
  "UPDATE products SET title='TESTE' WHERE title='Tenis Trail X';"
curl 'http://localhost:3001/v1/products?q=tenis'    # ainda mostra o titulo antigo

# limpar tudo
docker exec achou_redis redis-cli FLUSHALL
```

Com o Redis parado (`docker compose stop redis`) a API continua respondendo
`200`, servindo direto do Postgres.

## Fluxo de autenticacao

```bash
API=http://localhost:3001/v1

# registrar lojista (storeName so e exigido para LOJISTA)
curl -X POST $API/auth/register -H 'Content-Type: application/json' -d '{
  "email":"loja@teste.com","password":"senha12345",
  "name":"Maria","role":"LOJISTA","storeName":"Esportes Ja"
}'

# login devolve accessToken (15min) e refreshToken (7d)
TOKEN=$(curl -s -X POST $API/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"lojista@achou.com","password":"senha123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")

# cadastrar produto
curl -X POST $API/seller/products -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Chuteira Campo","priceCents":19990,"stock":10}'

# o produto ja aparece na busca publica: o cache foi invalidado
curl "$API/products?q=chuteira"
```

> **Atencao ao testar:** `/auth/login` tem rate limit de **5 requisicoes por
> minuto**. Scripts que fazem login repetido levam `429`. Reaproveite o token,
> ou reinicie a API (`docker compose restart api`) para zerar o contador --
> o throttler guarda estado em memoria.

## Testar a fila de notificacoes

Todo cadastro grava um evento `usuario.cadastrado` no outbox, e o worker
manda um e-mail de boas-vindas (mock -- so aparece no log).

```bash
curl -X POST $API/auth/register -H 'Content-Type: application/json' -d '{
  "email":"novo@teste.com","password":"senha12345","name":"Novo","role":"COMPRADOR"
}'

docker logs -f achou_worker
# [OutboxRelayService] 1 evento(s) publicados na fila
# [EmailMock] enviado mock-... para=novo@teste.com assunto="Bem-vindo(a) ao Achou!"
```

Helper: [`scripts/fila.sh`](../scripts/fila.sh)

```bash
./scripts/fila.sh stats     # pendentes no outbox + jobs por estado
./scripts/fila.sh falhas    # jobs que esgotaram as 5 tentativas, com o motivo
./scripts/fila.sh retry     # reprocessa os jobs em failed
./scripts/fila.sh logs      # log do worker
```

**Simular falha do provedor de e-mail** (a variavel so vale para este container):

```bash
docker compose stop worker
docker compose run --rm -e NOTIFICATION_MOCK_FAILURE_RATE=1 worker
# cadastre alguem e veja as tentativas 1/5 ... 5/5 com backoff de 2s, 4s, 8s, 16s
# Ctrl+C, depois:
docker compose start worker
./scripts/fila.sh retry     # agora o envio passa
```

**Simular a fila fora do ar:**

```bash
docker compose stop redis
# cadastre alguem: a API responde 201 e o evento fica pendente
./scripts/fila.sh stats     # (falha: o script precisa do Redis)
docker exec achou_postgres psql -U achou -d achou_marketplace -c \
  "SELECT type, created_at FROM outbox_events WHERE published_at IS NULL;"
docker compose start redis
# em ate ~10s o worker publica o evento e o e-mail sai
```

## Collection do Postman

[`docs/achou-marketplace.postman_collection.json`](achou-marketplace.postman_collection.json)
— 27 requisicoes em 5 pastas, no formato Collection v2.1.

**Importar:** Postman > Import > selecione o arquivo. A variavel `baseUrl` ja
aponta para `http://localhost:3001`.

**Uso:** rode qualquer login e o `accessToken` e salvo automaticamente numa
variavel da colecao; as rotas protegidas o consomem sozinhas. Cada pasta comeca
com o login do perfil correto, entao dá para rodar a colecao inteira ou so uma
pasta.

**Rodar por linha de comando** (nao precisa do Postman):

```bash
npx newman run docs/achou-marketplace.postman_collection.json
```

> A colecao faz **4 chamadas** a `/auth/login` numa execucao completa, e o limite
> e **5 por minuto por IP**. Rodar duas vezes seguidas leva `429` -- espere um
> minuto ou reinicie a API (`docker compose restart api`) para zerar o contador.

A pasta **Segurança** contem requisicoes que devem falhar de proposito (401, 403,
400). Os testes afirmam o codigo de erro esperado, entao "sucesso" ali significa
que a protecao funcionou.

## Inspecionar o cache

Helper: [`scripts/cache.sh`](../scripts/cache.sh)

```bash
./scripts/cache.sh ls                      # chaves com TTL e tamanho
./scripts/cache.sh ls 'products:list:*'    # filtra por padrao
./scripts/cache.sh show                    # resumo legivel das listagens
./scripts/cache.sh get products:list:<hash>  # valor em JSON formatado
./scripts/cache.sh stats                   # hit rate e memoria
./scripts/cache.sh watch                   # comandos em tempo real
./scripts/cache.sh flush                   # limpa tudo
```

### Direto no redis-cli

```bash
R="docker exec achou_redis redis-cli"

$R DBSIZE                                  # quantas chaves
$R --scan                                  # lista todas
$R --scan --pattern 'product:*'            # so os detalhes de produto
$R GET products:list:<hash> | python3 -m json.tool
$R TTL products:list:<hash>                # segundos restantes (-2 = expirou)
$R INFO stats | grep keyspace              # hits e misses acumulados
```

> **Use `--scan`, nunca `KEYS *`.** `KEYS` percorre o keyspace inteiro
> bloqueando o Redis; sob pico isso derruba o cache do catalogo justamente
> quando ele mais importa. `--scan` percorre em lotes sem bloquear.

### Chaves usadas

| Padrao | Conteudo | TTL |
|---|---|---|
| `products:list:<sha1>` | Resposta completa de `GET /v1/products` | 120s |
| `product:<uuid>` | Resposta de `GET /v1/products/:id` | 300s |

O `<sha1>` sao 16 caracteres do hash dos parametros da query **ordenados**, entao
`?q=a&sort=b` e `?sort=b&q=a` caem na mesma chave.

> `keyspace_hits`/`keyspace_misses` do `INFO stats` sao contadores **do servidor
> inteiro e acumulados desde que o container subiu** -- servem para uma leitura
> aproximada, nao para medir uma rota especifica. O hit rate da aplicacao, por
> tipo de chave, esta na metrica `achou_cache_consultas_total` e no painel
> "Cache hit rate" do Grafana ([observabilidade.md](observabilidade.md)).
