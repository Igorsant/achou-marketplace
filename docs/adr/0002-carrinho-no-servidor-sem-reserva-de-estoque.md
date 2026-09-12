# ADR 0002 — Carrinho: estado no servidor, sem preço congelado, split por lojista no commit

| | |
|---|---|
| **Status** | Aceito |
| **Data** | 2026-09-11 |
| **Implementação** | Decidido, não implementado — ver §7 |
| **Contexto de origem** | [`template-features.md`](../../template-features.md) — Feature 2, `Adicionar produto ao carrinho e visualizar carrinho` |
| **Decisores** | Equipe 4 |
| **Verificação** | [`scripts/adr-check.sh 0002`](../../scripts/adr-check.sh) · [`backend/test/adr-0002-carrinho.e2e-spec.ts`](../../backend/test/adr-0002-carrinho.e2e-spec.ts) |
| **Relacionado** | Resolve a questão em aberto §6.1 do [ADR 0001](0001-checkout-no-app-com-confirmacao-externa.md) |

---

## 1. Contexto

O carrinho parece a estrutura mais simples das três features e é a que mais
restringe as outras duas: ele define **o que** o commit do ADR 0001 congela e
**quantas** linhas de pedido esse commit produz.

Estado do repositório:

| Camada | Situação |
|---|---|
| Banco | `carts` e `cart_items` migrados. `carts.user_id` é `UNIQUE`; `cart_items` tem `@@unique([cartId, productId])` e **não tem coluna de preço** |
| Backend | `/v1/cart` especificado em [`api-design.md §2.4`](../api-design.md) e **não implementado** |
| Backend | `AuthService.register` já cria o carrinho junto com o comprador |
| App | [`cart_controller.dart`](../../app_achou/lib/state/cart_controller.dart) guarda a sacola **em memória**, com frete na constante `flatShippingCents = 2490` |

Três perguntas técnicas, e as três têm consequência no schema:

1. Onde mora o estado do carrinho — processo do cliente ou banco?
2. O carrinho guarda valor ou resolve valor na leitura?
3. Um carrinho com produtos de N lojistas vira quantos pedidos?

---

## 2. Decisão

### 2.1 O estado mora no servidor; o cliente é cache com atualização otimista

`/v1/cart` é a fonte da verdade. `CartController` deixa de ser um
`List<CartItem>` autônomo e vira cache local: o toque em "adicionar" pinta a
tela na hora e dispara a chamada; erro da API reverte o estado.

O que decide não é persistência — é **confiança**. Carrinho no cliente
significa que o checkout recebe itens e preços que o servidor nunca viu, e
precisa confiar no que o app mandou. Isso anula o snapshot do
[ADR 0001 §3.3](0001-checkout-no-app-com-confirmacao-externa.md): não adianta
congelar no commit um preço que o cliente propôs.

Com o estado no servidor, `POST /v1/orders` lê o carrinho do banco e o corpo da
requisição não carrega item nem valor nenhum.

### 2.2 `cart_items` não tem coluna de preço — e isso é a decisão, não um detalhe

O carrinho guarda `product_id` e `quantity`. Preço e disponibilidade são
resolvidos na leitura de `GET /cart` e revalidados no commit do checkout.

A ausência da coluna é o que garante que não existe segundo lugar onde o preço
vive. Coluna de preço no carrinho seria cache de um dado que terceiros editam,
sem invalidação possível: o lojista reajusta e nenhum evento avisa as N sacolas
que contêm o produto. O critério é o inverso do §3.3 do ADR 0001 — dado que
pode ser recalculado não deve ser guardado.

Pela mesma razão o carrinho **não reserva estoque**: reserva é estado derivado
com prazo de validade, que exige TTL, worker de expurgo e reconciliação. O
decremento condicional do ADR 0001 §3.2 já resolve o overselling no commit,
sem imobilizar nada.

Duas constraints sustentam o resto:

- `carts.user_id` `UNIQUE` — um carrinho por usuário é invariante do banco, não
  regra da aplicação. Como consequência, `user_id` é `NOT NULL` e **não existe
  carrinho anônimo**: não há onde pendurar o item sem usuário. Carrinho de
  visitante exigiria identidade de convidado, TTL de expurgo e regra de merge
  no login — três problemas que o MVP não compra (§5.3).
- `@@unique([cartId, productId])` — adicionar o mesmo produto duas vezes
  atualiza a quantidade da linha existente. Sem isso, "quantos deste produto
  há na sacola" vira um `SUM` sobre linhas duplicadas, e o `PATCH` de
  quantidade deixa de ter alvo único.

### 2.3 Um carrinho, N lojistas, N pedidos — com chave de idempotência derivada

Esta é a resposta à questão §6.1 do ADR 0001.

```
carrinho (1 usuário)
   ├── item · lojista A
   ├── item · lojista A
   └── item · lojista B
              │
              ▼  POST /v1/orders  (uma requisição, uma transação)
   ┌──────────┴──────────┐
   ▼                     ▼
 Order #1              Order #2
 lojista A             lojista B
 idem: {key}:A         idem: {key}:B
```

O agrupamento é `groupBy(sellerId)` sobre os itens do carrinho, dentro da
transação que já existe.

O detalhe que não é óbvio: `orders.idempotency_key` é `UNIQUE`, então N pedidos
na mesma requisição precisam de N chaves. Pedir N chaves ao cliente
transferiria para ele o conhecimento de quantos lojistas há no carrinho — algo
que só o servidor sabe, e que muda entre a montagem da tela e o commit. Por
isso a chave é **derivada** no servidor: `{key}:{sellerId}`. O cliente continua
mandando uma chave só, e a propriedade de idempotência continua valendo por
pedido.

A transação continua atômica: se o estoque de **um** item de **um** lojista
acabou, o checkout inteiro sofre rollback. Meio pedido não existe, e a resposta
`409` diz qual item faltou.

---

## 3. Alternativas consideradas

### A. Estado no cliente (situação atual)

| | |
|---|---|
| **Prós** | Já está pronto; zero latência; funciona sem rede |
| **Contras** | O servidor não vê o carrinho até o checkout, então o commit precisa confiar em item e preço vindos do app. Sacola some ao trocar de aparelho ou reiniciar o processo |
| **Por que não** | Abre o vetor que o snapshot do ADR 0001 §3.3 existe para fechar. Congelar no commit um valor que o cliente propôs não congela nada. |

### B. Carrinho anônimo com merge no login

| | |
|---|---|
| **Prós** | Não exige sessão para montar a sacola |
| **Contras** | Exige identidade de convidado (cookie ou device id), TTL de expurgo e uma regra de merge: visitante com 2 unidades, conta com 1 — soma, substitui ou pergunta? Cada resposta é um caso de borda com estado próprio |
| **Por que não** | Três estruturas novas para um ganho que só se mede com funil instrumentado, que também não existe. Nada nesta decisão impede depois (§5.3). |

### C. Um lojista por carrinho

| | |
|---|---|
| **Prós** | Elimina o split: um carrinho, um pedido, uma chave de idempotência |
| **Contras** | Ou o servidor rejeita item de outra loja, ou mantém N carrinhos paralelos — e `carts.user_id UNIQUE` teria de virar `UNIQUE(user_id, seller_id)`, com o cliente gerenciando qual sacola está ativa |
| **Por que não** | O custo do split é uma cláusula `groupBy` dentro de uma transação que já vai existir. O custo de N carrinhos é estado de seleção no cliente e uma constraint mais fraca. |

### D. Reserva de estoque ao adicionar

| | |
|---|---|
| **Prós** | O erro de estoque aparece ao adicionar, não no commit |
| **Contras** | Reserva é linha com prazo: exige TTL, worker de expurgo e reconciliação entre reservado e vendido. Carrinho abandonado imobiliza estoque real |
| **Por que não** | Duplica a autoridade sobre o estoque — passariam a existir dois lugares decidindo se há unidade disponível. O `UPDATE` condicional do ADR 0001 §3.2 já é autoridade única e não guarda estado. |

---

## 4. Consequências

### Positivas

- O checkout lê o carrinho do banco. O cliente não consegue propor preço,
  quantidade fora do que foi registrado, nem item que não passou por `/v1/cart`.
- A sacola sobrevive a reinício do processo e a troca de aparelho, sem nenhum
  código de sincronização — é consequência de onde o estado mora.
- Carrinho abandonado vira dado consultável sem instrumentação extra.
- O split por lojista mantém `order_items.seller_id` com um valor só por
  pedido, o que torna o painel do lojista uma consulta por índice e não um
  filtro sobre pedido de outro.

### Negativas e riscos assumidos

| Risco | Mitigação |
|---|---|
| **Cada alteração de quantidade é um round-trip.** O stepper dispara chamada por toque | Atualização otimista na UI + *debounce* no `PATCH`; a tela nunca espera a rede |
| **Sessão vira pré-requisito** de montar carrinho — consequência direta de `user_id NOT NULL` | Gatilho no primeiro item, não na abertura do app. Vitrine e busca seguem públicas |
| **Preço muda entre ver o carrinho e fechar** | Consequência aceita de não congelar: `GET /cart` devolve o preço atual e a diferença aparece antes do commit |
| **Produto arquivado sai do catálogo mas está na sacola** | `GET /cart` marca o item como indisponível em vez de deletar em silêncio — sumiço sem aviso é pior que erro visível |
| **Checkout multi-lojista falha por um item só** | Rollback total é deliberado (§2.3); o `409` identifica o item |

### Bloqueio conhecido

O `SessionController` do app hoje recusa qualquer conta que não seja lojista:

```dart
if (!sessao.isLojista) { _erro = 'Esta conta não é de lojista.'; }
```

Enquanto essa checagem existir, **nenhum comprador tem sessão**, e sem sessão
não há `carts.user_id`. A Feature 2 depende de uma mudança que pertence à
Feature 3 — tratada no [ADR 0003](0003-sessao-jwt-stateless-com-refresh.md) §5.2.

### Dívida técnica registrada

- `flatShippingCents = 2490` continua no cliente. Frete calculado está fora de
  escopo (ADR 0001 §3.6), mas a constante precisa migrar para o servidor antes
  de virar valor cobrado de alguém — valor de cobrança decidido no cliente é o
  mesmo problema do §2.1.
- `cart_items` não tem índice por `product_id`. Só importa quando alguém
  precisar responder "quantos carrinhos contêm este produto".

---

## 5. Questões em aberto

1. **Teto de quantidade por item.** Limitar pelo `stock` atual daria falsa
   sensação de reserva, que o §2.2 recusa; não limitar aceita 9.999 unidades.
   Provável saída: teto pelo estoque **na leitura**, com o `409` do commit
   continuando sendo a autoridade.
2. **TTL do carrinho.** Item de um ano atrás ainda deve aparecer? Expurgo
   exige decidir o que fazer com carrinho de conta inativa.
3. **Carrinho anônimo com merge** (§3-B) — quando houver funil medido.

---

## 6. Referências

- [`docs/api-design.md §2.4`](../api-design.md) — contrato de `/v1/cart`
- [`docs/data-model.md`](../data-model.md) — `carts`, `cart_items`
- [`backend/prisma/schema.prisma`](../../backend/prisma/schema.prisma) — as constraints citadas no §2.2
- [`app_achou/lib/state/cart_controller.dart`](../../app_achou/lib/state/cart_controller.dart) — o que vira cache
- [ADR 0001](0001-checkout-no-app-com-confirmacao-externa.md) §3.1–§3.3 — idempotência e snapshot que esta decisão sustenta
- [`template-features.md`](../../template-features.md) — Feature 2, entregas E2E 1 a 3

---

## 7. Estado da implementação

Como no ADR 0001, a incompletude é **de escopo**. A decisão vale porque o
schema já a materializou: `cart_items` sem preço e `carts.user_id UNIQUE` não
são planos, são constraints aplicadas — e são a metade da decisão que mais
custa reverter depois.

| Decisão | Estado | Onde é verificado |
|---|---|---|
| §2.2 `cart_items` sem coluna de preço nem reserva | ✅ migrado | `adr-check.sh 0002`, `adr-check.sh banco` |
| §2.2 `carts.user_id` `UNIQUE` e `NOT NULL` | ✅ migrado | `adr-check.sh 0002`, `adr-check.sh banco` |
| §2.2 `@@unique([cartId, productId])` | ✅ migrado | `adr-check.sh 0002`, `adr-check.sh banco` |
| §2.2 register cria o carrinho do comprador | ✅ implementado | `adr-0003-sessao.e2e-spec.ts` |
| §2.1 `/v1/cart` como fonte da verdade | ⏳ diferido | `adr-0002-carrinho.e2e-spec.ts` |
| §2.2 preço resolvido na leitura | ⏳ diferido | `adr-0002-carrinho.e2e-spec.ts` |
| §2.2 adicionar não mexe no estoque | ⏳ diferido | `adr-0002-carrinho.e2e-spec.ts` |
| §2.3 split por lojista e chave derivada | ⏳ diferido | `adr-0001-checkout.e2e-spec.ts` |
| §2.1 `CartController` como cache | ⏳ diferido | `cart_controller_test.dart` cobre o comportamento atual |

A suíte [`adr-0002-carrinho.e2e-spec.ts`](../../backend/test/adr-0002-carrinho.e2e-spec.ts)
tem os 11 casos escritos e se ativa quando `backend/src/cart/` existir.
