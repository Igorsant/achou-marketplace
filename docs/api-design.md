# Design da API — Achou! Marketplace

Stack: **Node.js + NestJS + PostgreSQL + Prisma + Redis**, orquestrados via Docker Compose no ambiente local.

Documento de referência para a implementação. Complementa a arquitetura descrita no [README](../README.md).

---

## 1. Princípios de Design

| Princípio | Decisão |
|---|---|
| Prefixo de versão | Todas as rotas sob `/v1` |
| Separação por audiência | `/v1/products` é público e cacheável; `/v1/seller/*` exige role `LOJISTA` |
| Dinheiro | Sempre `Int` em **centavos**. Nunca `Float` |
| Identificadores | UUID v4 (`gen_random_uuid()`), nunca ID sequencial exposto |
| Datas | ISO 8601 em UTC (`timestamptz`) |
| Nomes | Recursos no plural, `snake_case` no banco, `camelCase` no JSON |
| Idempotência | Header `Idempotency-Key` obrigatório no checkout |

### Envelope de erro

Formato único em toda a API:

```json
{
  "error": {
    "code": "ESTOQUE_INSUFICIENTE",
    "message": "O produto 'Tênis Runner 42' possui apenas 2 unidades disponíveis.",
    "details": { "productId": "uuid", "requested": 5, "available": 2 }
  }
}
```

| Status | Uso |
|---|---|
| `400` | Payload malformado |
| `401` | Token ausente ou inválido |
| `403` | Autenticado, mas sem permissão (comprador tentando rota de lojista) |
| `404` | Recurso inexistente |
| `409` | Conflito de estado (estoque insuficiente, pedido já pago) |
| `422` | Validação de negócio falhou |
| `429` | Rate limit estourado |

---

## 2. Mapa de Rotas

### 2.1 Autenticação — `/v1/auth`

| Método | Rota | Auth | Descrição |
|---|---|---|---|
| `POST` | `/auth/register` | — | ✅ Cria conta. Body define `role`. `storeName` exigido para LOJISTA |
| `POST` | `/auth/login` | — | ✅ Retorna `accessToken` (15min) + `refreshToken` (7d). Rate limit 5/min |
| `POST` | `/auth/refresh` | — | ✅ Renova o access token |
| `GET` | `/auth/me` | JWT | ✅ Dados do usuário logado |

O `role` vai como claim dentro do JWT — é o que o app Flutter usa para alternar a navegação e o que o guard do NestJS usa para proteger `/seller/*`.

### 2.2 Catálogo público — `/v1/products`

Rotas de leitura, sem autenticação, servidas pelo cache Redis.

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/products` | Busca e listagem por relevância |
| `GET` | `/products/:id` | Detalhe do produto |
| `GET` | `/categories` | Lista de categorias |

**Query params de `GET /products`:**

| Param | Tipo | Default | Descrição |
|---|---|---|---|
| `q` | string | — | Termo de busca. Ausente = vitrine (ordena por popularidade) |
| `category` | string | — | Slug da categoria |
| `minPrice` / `maxPrice` | int | — | Faixa de preço em centavos |
| `sort` | enum | `relevance` | `relevance` · `price_asc` · `price_desc` · `newest` |
| `page` | int | `1` | Paginação |
| `limit` | int | `20` | Máximo 50 |

**Resposta:**

```json
{
  "data": [
    {
      "id": "uuid",
      "title": "Tênis Runner 42",
      "priceCents": 24990,
      "imageUrl": "https://cdn.../p.jpg",
      "inStock": true,
      "seller": { "id": "uuid", "storeName": "Corrida Já" }
    }
  ],
  "pagination": { "page": 1, "limit": 20, "total": 137, "totalPages": 7 }
}
```

### 2.3 Painel do Lojista — `/v1/seller`

Todas exigem JWT com `role: LOJISTA`. O guard valida também **posse**: um lojista só altera produto próprio.

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/seller/products` | ✅ Lista os produtos da própria loja (inclui arquivados) |
| `POST` | `/seller/products` | ✅ Cadastra produto e invalida o cache |
| `PATCH` | `/seller/products/:id` | ✅ Atualiza dados |
| `PATCH` | `/seller/products/:id/stock` | ✅ Ajusta estoque |
| `DELETE` | `/seller/products/:id` | ✅ Soft delete (`status = ARCHIVED`) |
| `GET` | `/seller/orders` | ✅ Pedidos recebidos, agrupados, só com itens da loja |

**`POST /seller/products`:**

```json
{
  "title": "Tênis Runner 42",
  "description": "Tênis de corrida, solado em EVA",
  "priceCents": 24990,
  "stock": 15,
  "categoryId": "uuid",
  "imageUrl": "https://cdn.../p.jpg"
}
```

### 2.4 Carrinho — `/v1/cart`

Exige JWT `COMPRADOR`. Um carrinho ativo por usuário.

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/cart` | Carrinho atual com totais recalculados |
| `POST` | `/cart/items` | Adiciona item (`{ productId, quantity }`) |
| `PATCH` | `/cart/items/:itemId` | Altera quantidade |
| `DELETE` | `/cart/items/:itemId` | Remove item |
| `DELETE` | `/cart` | Esvazia |

O carrinho **não reserva estoque**. Ele guarda apenas `productId` e `quantity`; preço e disponibilidade são resolvidos na leitura e revalidados no checkout.

### 2.5 Pedidos e Pagamento — `/v1/orders`

| Método | Rota | Descrição |
|---|---|---|
| `POST` | `/orders` | Checkout: converte carrinho em pedido. **Requer `Idempotency-Key`** |
| `GET` | `/orders` | Histórico do comprador |
| `GET` | `/orders/:id` | Detalhe |
| `POST` | `/orders/:id/payment` | Dispara autorização (mock) |
| `POST` | `/orders/:id/cancel` | Cancela e devolve estoque (só se `PENDING_PAYMENT`) |

**Máquina de estados do pedido:**

```
PENDING_PAYMENT ──payment ok──► PAID ──► FULFILLED
       │
       ├──payment recusado──► PAYMENT_FAILED ──retry──► PENDING_PAYMENT
       │
       └──cancel / timeout──► CANCELLED
```

Transições fora desse grafo retornam `409`.

---

## 3. Decisões Técnicas

### 3.1 Relevância na busca

O ranking usa **full-text search nativo do Postgres** — sem Elasticsearch, que seria peso desnecessário no MVP.

Coluna gerada, com peso maior para o título que para a descrição:

```sql
CREATE EXTENSION IF NOT EXISTS unaccent;

-- unaccent() e STABLE, nao IMMUTABLE. Coluna gerada exige IMMUTABLE, entao
-- envelopamos fixando o dicionario, o que torna o resultado deterministico.
CREATE OR REPLACE FUNCTION f_unaccent(text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $$ SELECT public.unaccent('public.unaccent', $1) $$;

ALTER TABLE products ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('portuguese', f_unaccent(coalesce(title, ''))), 'A') ||
    setweight(to_tsvector('portuguese', f_unaccent(coalesce(description, ''))), 'B')
  ) STORED;

CREATE INDEX idx_products_search ON products USING GIN (search_vector);
```

> **Acento e obrigatorio tratar.** Sem `unaccent`, `tenis` gera o lexema `'ten'`
> e `tenis` com acento gera `'ten'` acentuado -- nao casam. Como a maioria dos
> usuarios busca sem acento, o produto simplesmente nao aparece. A normalizacao
> precisa acontecer **nos dois lados**: na coluna gerada e no termo da query.

O score final combina o texto com sinais de negócio:

```sql
SELECT
  p.*,
  ts_rank_cd(p.search_vector, q) * 1.0
    + log(1 + p.sales_count) * 0.3
    + CASE WHEN p.stock > 0 THEN 0.5 ELSE 0 END   -- esgotado afunda
  AS relevance
FROM products p, websearch_to_tsquery('portuguese', $1) q
WHERE p.search_vector @@ q
  AND p.status = 'ACTIVE'
ORDER BY relevance DESC
LIMIT $2 OFFSET $3;
```

Três pontos:

- **`websearch_to_tsquery`** aceita a sintaxe que o usuário já conhece (`"aspas"`, `-exclusão`) sem estourar erro em input malformado — ao contrário de `to_tsquery`.
- **`sales_count` é desnormalizado** na tabela `products`, incrementado pelo worker quando o pedido é pago. Evita `JOIN` de agregação na rota mais quente da API.
- **Sem `q`**, a vitrine ordena só por `sales_count` e recência.

> **Atencao com o Prisma -- verificado na implementacao:** `tsvector` nao e um
> tipo suportado. Declare como `Unsupported("tsvector")` e busque via `$queryRaw`.
>
> So isso **nao basta**. Sem declaracoes extras no schema, todo `prisma migrate dev`
> tenta desfazer o trabalho manual:
>
> ```sql
> DROP INDEX "idx_products_search";
> ALTER TABLE "products" ALTER COLUMN "search_vector" DROP DEFAULT;
> ```
>
> O Prisma le a expressao `GENERATED ALWAYS AS` como um "default" que sobra, e o
> indice GIN como um objeto orfao. As duas linhas abaixo eliminam o drift:
>
> ```prisma
> searchVector Unsupported("tsvector")? @default(dbgenerated()) @map("search_vector")
>
> @@index([searchVector(ops: raw("tsvector_ops"))], map: "idx_products_search", type: Gin)
> ```
>
> Indices **parciais** (`WHERE ...`) nao sofrem disso -- o Prisma nao os introspecta,
> entao `idx_outbox_pendentes` e `idx_products_vitrine` sobrevivem sem declaracao.

### 3.2 Concorrência no estoque

O risco documentado no README (dois compradores levando a última unidade) é resolvido com **decremento condicional atômico**, dentro da transação do checkout:

```sql
UPDATE products
   SET stock = stock - $1
 WHERE id = $2
   AND stock >= $1
RETURNING stock;
```

Se o `UPDATE` afeta **zero linhas**, o estoque acabou entre a leitura do carrinho e o commit. A transação inteira sofre rollback e a API responde `409 ESTOQUE_INSUFICIENTE`.

Isso é preferível ao lock otimista com coluna `version` neste caso: resolve em uma única ida ao banco, sem round-trip de leitura prévia, e o próprio `WHERE` é a validação.

### 3.3 Idempotência do checkout

Sem isso, um duplo-toque no botão ou um retry do app gera dois pedidos.

```
POST /v1/orders
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

A chave é gravada com constraint `UNIQUE` na tabela `orders`. Requisição repetida com a mesma chave retorna **o pedido já criado** (`200`) em vez de criar outro (`201`).

### 3.4 Snapshot de preço

`order_items` guarda `unit_price_cents` e `title_snapshot` **copiados no momento da compra**. Se o lojista reajustar o preço amanhã, o pedido de hoje preserva o valor cobrado. Nunca renderize um pedido histórico fazendo `JOIN` com o preço atual do produto.

### 3.5 Transação do checkout

Tudo abaixo em **uma única transação**:

```
BEGIN
  1. valida carrinho (produtos ativos, preços atuais)
  2. UPDATE condicional de estoque para cada item
  3. INSERT order + order_items (com snapshot de preço)
  4. INSERT outbox ('pedido.criado')
  5. limpa o carrinho
COMMIT
```

O passo 4 é o padrão outbox: o evento nasce durável junto ao pedido. Um relay (`@nestjs/schedule`) drena a tabela para o BullMQ.

### 3.6 Cache do catálogo

| Chave | TTL | Invalidação | Status |
|---|---|---|---|
| `product:{id}` | 5 min (`CACHE_TTL_PRODUCT`) | Pontual, via `invalidar()` | ✅ implementado |
| `products:list:{hash}` | 2 min (`CACHE_TTL_LIST`) | Por padrão, via `SCAN` | ✅ implementado |
| `categories:all` | 1 h | Ao criar categoria | ⬜ pendente |

O hash da chave de listagem ordena os parâmetros antes de gerar o SHA-1, senão
`?q=a&sort=b` e `?sort=b&q=a` criariam entradas distintas para a mesma consulta.

**O termo `q` é normalizado antes de entrar no hash** (`normalizarTermoBusca` em
`backend/src/common/texto.util.ts`): remove acentos, passa para minúsculas e
colapsa espaços repetidos. A busca no Postgres já é insensível a caixa
(`to_tsvector`) e a acento (`f_unaccent`), então `tenis`, `Tenis`, `TENIS` e
`tênis` devolvem resultado idêntico — sem normalizar, cada variação ocupava uma
entrada de cache própria apontando para o mesmo conteúdo.

Medido: 6 variações do mesmo termo passaram de **6 chaves para 1**. Além da
memória, isso reduz o custo da invalidação por `SCAN`, que é proporcional ao
número de chaves.

Termo vazio ou só com espaços vira `undefined` e cai na vitrine, em vez de montar
um `tsquery` vazio.

**Invalidação de listagens:** a varredura usa `SCAN`, nunca `KEYS` — `KEYS`
bloqueia o Redis inteiro enquanto percorre o keyspace, e sob pico isso derruba o
cache do catálogo justamente quando ele mais importa. Ainda assim, invalidar por
padrão custa proporcional ao número de chaves; se o volume de variações de query
crescer muito, voltar ao TTL puro é a saída.

**O cache é otimização, nunca dependência.** Toda leitura e escrita no Redis está
sob `try/catch` que devolve `null` em falha, e o chamador segue para o Postgres.
Redis fora do ar degrada latência, não disponibilidade — verificado derrubando o
container: a API continuou respondendo `200`.

### 3.7 Notificações assíncronas (outbox + fila)

✅ Implementado para o evento `usuario.cadastrado` (e-mail de boas-vindas). O
mesmo caminho serve para `pedido.criado` quando o checkout existir.

```
POST /auth/register                         processo worker (separado da API)
┌──────────────────────────────┐    ┌──────────────────────────────────────────────┐
│ BEGIN                        │    │ relay (a cada 5s)        processor           │
│   INSERT users               │    │ SELECT ... FOR UPDATE    ┌──────────────────┐│
│   INSERT outbox_events ──────┼───►│   SKIP LOCKED  ──addBulk─► fila notificacoes││
│ COMMIT                       │    │ UPDATE published_at      └────────┬─────────┘│
└──────────────────────────────┘    │                                   ▼          │
                                    │     processed_events? ─não─► e-mail (mock)   │
                                    └──────────────────────────────────────────────┘
```

| Peça | Arquivo | Papel |
|---|---|---|
| Catálogo de eventos | `src/outbox/eventos.ts` | Tipos, payloads e `registrarEvento(tx, ...)` |
| Rotas | `src/queue/filas.ts` | Qual fila recebe cada tipo de evento |
| Relay | `src/outbox/outbox-relay.service.ts` | Drena o outbox para o BullMQ |
| Consumidor | `src/notifications/notifications.processor.ts` | Idempotência + envio |
| Provedor | `src/notifications/email-mock.service.ts` | E-mail falso com latência e falha simulada |
| Processo | `src/worker.ts` | Entrypoint separado; a API nem conecta no BullMQ |

**Garantias, cada uma verificada na implementação:**

- **O cadastro não depende da fila.** Com o Redis parado, `POST /auth/register`
  responde `201` normalmente; o evento fica pendente no outbox e é entregue
  assim que o Redis volta.
- **Entrega at-least-once, efeito exactly-once.** Duas barreiras contra
  duplicata: o `jobId` do BullMQ é o id do evento (republicar é no-op) e o
  consumidor checa `processed_events` antes de enviar. Forçando a reentrega de
  um evento já notificado, o worker registra `ja notificado, ignorando duplicata`.
- **Retry com backoff exponencial.** 5 tentativas, esperas de 2s, 4s, 8s e 16s.
  Esgotadas, o job fica em `failed` por 7 dias para inspeção e reprocesso
  (`scripts/fila.sh retry`).
- **Réplicas concorrentes não disputam linhas.** `FOR UPDATE SKIP LOCKED` faz
  cada worker pegar um lote diferente do outbox.

**Detalhes que custaram a descobrir:**

- Com o Redis fora, o ioredis **não falha**: segura o comando na fila offline
  até reconectar. O relay ficava parado em silêncio segurando a transação. Agora
  o `addBulk` tem prazo de 5s; estourou, a transação desfaz e o evento continua
  pendente. Enquanto o comando preso não sai, o relay não tenta de novo — senão
  empilharia uma cópia por ciclo na fila offline.
- Sem listener de `'error'` na Queue e no Worker, o BullMQ imprime uma stack
  inteira **a cada tentativa de reconexão**. Os listeners logam no máximo uma
  linha a cada 30s.
- O `processed_events` é gravado **depois** do envio: se o worker cair no meio,
  o retry reenvia. E-mail duplicado é preferível a e-mail perdido.

**Simular falha do provedor:** `NOTIFICATION_MOCK_FAILURE_RATE` (0 a 1) no
`.env`. Com `1`, todo envio falha e dá para ver as 5 tentativas no log.

### 3.8 Rate limiting

| Escopo | Limite |
|---|---|
| Catálogo (`GET /products`) | 100 req/min por IP |
| Auth (`/auth/login`) | 5 req/min por IP |
| Escrita (`POST /orders`, `/seller/*`) | 20 req/min por usuário |

Via `@nestjs/throttler` com storage no Redis (o contador precisa ser compartilhado entre as réplicas).

---

## 4. Modelo de Dados

```
users ──1:1── sellers ──1:N── products ──N:1── categories
  │                              │
  │                              │
  ├──1:1── carts ──1:N── cart_items
  │
  └──1:N── orders ──1:N── order_items
                │
                └──1:1── payments

outbox_events        (independente)
processed_events     (idempotência dos workers)
```

**Tabelas e campos-chave:**

| Tabela | Campos relevantes |
|---|---|
| `users` | `id`, `email` UNIQUE, `password_hash`, `role` |
| `sellers` | `id`, `user_id`, `store_name`, `slug` UNIQUE |
| `products` | `id`, `seller_id`, `title`, `price_cents`, `stock`, `sales_count`, `status`, `search_vector` |
| `carts` / `cart_items` | `cart_id`, `product_id`, `quantity` — **sem preço** |
| `orders` | `id`, `buyer_id`, `status`, `total_cents`, `idempotency_key` UNIQUE |
| `order_items` | `unit_price_cents`, `title_snapshot`, `seller_id` |
| `payments` | `order_id`, `status`, `provider_ref`, `amount_cents` |
| `outbox_events` | `type`, `payload` JSONB, `published_at` NULL |
| `processed_events` | `event_id` + `handler` como PK composta |

**Índices que importam:**

```sql
CREATE INDEX idx_products_search   ON products USING GIN (search_vector);
CREATE INDEX idx_products_seller   ON products (seller_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_products_category ON products (category_id, price_cents);
CREATE INDEX idx_orders_buyer      ON orders (buyer_id, created_at DESC);
CREATE INDEX idx_outbox_pendentes  ON outbox_events (created_at) WHERE published_at IS NULL;
```

O último é o índice parcial que mantém o relay do outbox rápido mesmo com histórico grande.

### Migrations à mão

Para escrever cada migration manualmente em vez de deixar o Prisma gerar:

```bash
npx prisma migrate dev --create-only --name cria_tabela_products
```

Isso gera `prisma/migrations/<timestamp>_cria_tabela_products/migration.sql` **sem aplicar**. Você edita o SQL livremente — necessário de qualquer forma para a coluna gerada `search_vector`, que o Prisma não sabe emitir. Depois:

```bash
npx prisma migrate dev     # aplica
npx prisma generate        # regenera o client tipado
```

---

## 5. Docker Compose

```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: achou
      POSTGRES_PASSWORD: achou_dev
      POSTGRES_DB: achou_marketplace
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U achou"]
      interval: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    command: redis-server --appendonly yes
    volumes: ["redisdata:/data"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 5

  api:
    build: ./backend          # monorepo: o contexto e a pasta do backend
    ports: ["3000:3000"]
    environment:
      DATABASE_URL: postgresql://achou:achou_dev@postgres:5432/achou_marketplace
      REDIS_URL: redis://redis:6379
      JWT_SECRET: dev_secret_trocar_em_prod
    depends_on:
      postgres: { condition: service_healthy }
      redis:    { condition: service_healthy }
    volumes: ["./backend/src:/app/src"]
    command: npm run start:dev

volumes:
  pgdata:
  redisdata:
```

Os `healthcheck` com `condition: service_healthy` existem porque a API sobe mais rápido que o Postgres aceita conexão — sem isso o container da API entra em crash loop no primeiro `up`.

---

## 6. Estrutura de Módulos

```
backend/src/
├── auth/          guards, estratégia JWT, decorator @Roles
├── users/
├── sellers/
├── products/      CRUD do lojista + busca pública
├── cart/
├── orders/        checkout (transação + outbox)
├── payments/      adapter mock com delay simulado
├── outbox/        catálogo de eventos + relay agendado
├── queue/         conexão BullMQ e rotas evento → fila
├── notifications/ consumidor da fila de notificações + e-mail mock
├── worker.ts      entrypoint do processo assíncrono
├── cache/         wrapper Redis
└── prisma/        PrismaService
```

---

## 7. Plano de Execução

Mapeado sobre o cronograma de 4 aulas do README.

**Aula 2 — Backend e Dados**

- [ ] `docker-compose.yml` no ar (Postgres + Redis)
- [ ] Projeto NestJS + Prisma conectado
- [ ] Migrations: `users`, `sellers`, `categories`, `products`
- [ ] `/auth/register`, `/auth/login`, guard de role
- [ ] CRUD `/seller/products`
- [ ] `GET /products` com full-text search e ranking
- [ ] Cache Redis na listagem

**Aula 3 — Frontend**

- [ ] Migrations: `carts`, `orders`, `payments`, `outbox`
- [ ] Rotas de carrinho
- [ ] Telas Flutter consumindo busca e carrinho

**Aula 4 — Checkout e Carga**

- [ ] `POST /orders` com transação, estoque condicional e idempotência
- [ ] Pagamento mock + máquina de estados
- [x] Relay do outbox + worker de notificação (hoje disparado pelo cadastro; falta plugar `pedido.criado`)
- [ ] Teste de carga com k6 em `GET /products`

### Ordem de implementação sugerida

O caminho que destrava mais cedo o trabalho do frontend:

```
1. compose + prisma  →  2. auth  →  3. produtos (lojista)
                                          ↓
        6. checkout  ←  5. carrinho  ←  4. busca
                ↓
        7. outbox + workers
```

Auth e produtos primeiro porque sem produtos cadastrados não há o que buscar, e sem busca não há tela para o Flutter consumir.
