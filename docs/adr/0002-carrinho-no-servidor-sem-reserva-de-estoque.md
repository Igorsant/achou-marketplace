# ADR 0002 — Carrinho no servidor, multi-lojista, sem reserva de estoque

| | |
|---|---|
| **Status** | Aceito |
| **Data** | 2026-09-11 |
| **Contexto de origem** | [`template-features.md`](../../template-features.md) — Feature 2, `Adicionar produto ao carrinho e visualizar carrinho` |
| **Decisores** | Equipe 4 |
| **Relacionado** | Resolve a questão em aberto §6.1 do [ADR 0001](0001-checkout-no-app-com-confirmacao-externa.md) |

---

## 1. Contexto

O carrinho parece a feature mais simples das três e é a que mais decide coisa
pelas outras duas: ele define **o que** o checkout vai congelar em pedido
(Feature 1) e **a partir de quando** o comprador precisa estar autenticado
(Feature 3).

Estado atual do repositório:

| Camada | Situação |
|---|---|
| App Flutter | [`cart_controller.dart`](../../app_achou/lib/state/cart_controller.dart) guarda a sacola **em memória**, com o comentário `Mantido em memória enquanto /v1/cart não existe` |
| App Flutter | Frete é a constante `flatShippingCents = 2490` |
| Backend | `/v1/cart` está especificado em [`api-design.md §2.4`](../api-design.md) e **não existe** em `backend/src/` |
| Banco | `carts` e `cart_items` já migrados. `cart_items` **não tem coluna de preço** — decisão já materializada no schema |
| Banco | `carts.userId` é `@unique`: um carrinho por usuário, sempre |
| Backend | `AuthService.register` já cria o carrinho junto com o comprador |

Três perguntas em aberto, e as três têm consequência larga:

1. O carrinho mora no app ou no servidor?
2. Adicionar ao carrinho exige login?
3. Um carrinho pode conter produtos de lojistas diferentes?

---

## 2. Decisão

### 2.1 O carrinho é do servidor. O app tem uma cópia, não a verdade.

`/v1/cart` é implementado e passa a ser a fonte da verdade.
`CartController` deixa de ser um `List<CartItem>` autônomo e vira **cache
local com atualização otimista**: o toque em "adicionar" pinta a tela na hora
e dispara a chamada; erro da API reverte o estado e avisa.

O carrinho **não guarda preço**. Preço e disponibilidade são resolvidos na
leitura de `GET /cart` e revalidados no commit do checkout — como já está
escrito em `api-design.md §2.4` e como o schema já impõe ao não ter a coluna.

### 2.2 Carrinho exige comprador autenticado.

Não existe carrinho anônimo no MVP. `carts.userId` é obrigatório e único;
sem usuário não há onde pendurar o item.

O gatilho de login é **adicionar o primeiro item**, não abrir o app: a vitrine
e a busca continuam públicas. Quem toca em "adicionar" sem sessão cai no
login e volta para o produto de onde saiu, com o item aplicado.

### 2.3 Um carrinho pode ter vários lojistas. O checkout quebra em um pedido por lojista.

Esta é a resposta à questão §6.1 do ADR 0001.

```
carrinho (1 usuário)
   ├── item · lojista A
   ├── item · lojista A
   └── item · lojista B
              │
              ▼  POST /v1/orders  (uma transação)
   ┌──────────┴──────────┐
   ▼                     ▼
 Order #1              Order #2
 lojista A             lojista B
 idem: {key}:A         idem: {key}:B
 WhatsApp de A         WhatsApp de B
```

Uma requisição de checkout, uma transação, **N pedidos** — um por lojista
presente no carrinho. A `Idempotency-Key` enviada pelo app é derivada por
lojista (`{key}:{sellerId}`) para respeitar o `UNIQUE` de
`orders.idempotency_key` sem pedir N chaves ao cliente.

A transação continua atômica: se o estoque de **um** item de **um** lojista
acabou, o checkout inteiro sofre rollback. Meio pedido não existe.

---

## 3. Alternativas consideradas

### A. Carrinho só no app (estado atual)

| | |
|---|---|
| **Prós** | Já está pronto; zero latência; funciona offline |
| **Contras** | Fechou o app, perdeu a sacola. Trocou de aparelho, perdeu a sacola. O lojista nunca sabe o que ficou no carrinho de ninguém — morre o dado que responde "onde perdemos a venda" |
| **Por que não** | A entrega E2E 3 da Feature 2 fala em "seguir para o checkout com os dados organizados". Se o carrinho vive só no cliente, o checkout recebe dados que o servidor nunca viu e precisa confiar em preço vindo do app — que é exatamente o vetor que o snapshot de preço do ADR 0001 existe para fechar. |

### B. Carrinho anônimo, com merge no login

| | |
|---|---|
| **Prós** | Menos atrito: o comprador só encara o login na hora de fechar |
| **Contras** | Exige identidade de convidado (cookie ou device id), TTL de expurgo, e uma regra de merge — o que acontece quando o visitante tem 2 unidades e a conta já tinha 1? Somar, substituir, perguntar? Três telas de caso de borda para um MVP de 3 dias |
| **Por que não** | É a decisão certa para conversão e a errada para agora. Fica registrada como evolução em §6 — nada nesta decisão a impede depois. |

### C. Um lojista por carrinho

| | |
|---|---|
| **Prós** | Handoff de WhatsApp trivialmente resolvido; um pedido, uma conversa; nenhuma chave derivada |
| **Contras** | Ou o app bloqueia adicionar produto de outra loja ("esvazie a sacola primeiro"), ou mantém N sacolas paralelas. A primeira opção é hostil; a segunda é mais complexa que o split no checkout |
| **Por que não** | Marketplace cujo carrinho não deixa comprar de duas lojas não é marketplace, é vitrine de lojas. O custo do split é uma cláusula `groupBy(sellerId)` dentro de uma transação que já vai existir. |

### D. Carrinho reserva estoque ao adicionar

| | |
|---|---|
| **Prós** | O comprador nunca leva um "acabou" na cara do checkout |
| **Contras** | Carrinho abandonado vira estoque morto. Exige TTL, worker de expurgo e uma conversa difícil com o lojista sobre produto que consta indisponível e está no depósito |
| **Por que não** | O `UPDATE` condicional de `api-design.md §3.2` já resolve o overselling no commit, sem imobilizar nada. O schema já declarou a escolha: `cart_items` não tem preço nem reserva. |

---

## 4. Consequências

### Positivas

- A sacola sobrevive a fechar o app e a trocar de aparelho — é o que a
  Feature 2 promete ao chamar o elefante de "carrinho persistente".
- O checkout passa a ler o carrinho do **banco**, não do corpo da requisição.
  O cliente não consegue mais propor preço.
- Carrinho abandonado vira dado consultável: é a métrica que diz se o
  problema do funil está no preço, no frete ou no handoff do ADR 0001.
- O split por lojista deixa o WhatsApp do ADR 0001 natural: uma conversa por
  lojista, cada uma com o pedido dela.

### Negativas e riscos assumidos

| Risco | Mitigação |
|---|---|
| **Toda alteração de quantidade vira round-trip.** Stepper de quantidade dispara chamada por toque | Atualização otimista na UI + *debounce* no `PATCH`; a tela nunca espera a rede |
| **Login vira obstáculo no meio da compra** — é a queda de funil clássica | Gatilho tardio (primeiro item, não abertura do app) e retorno ao ponto de origem. Merge anônimo fica mapeado em §6 |
| **Preço muda entre ver o carrinho e fechar** | Consequência aceita de não congelar: `GET /cart` sempre devolve o preço atual, e a diferença aparece antes do commit, não depois |
| **Item some do carrinho** (lojista arquiva o produto) | `GET /cart` marca o item como indisponível em vez de deletar em silêncio — sumiço sem aviso é pior que erro visível |
| **Checkout multi-lojista falha por um item só** | Rollback total é deliberado. A resposta `409` diz **qual** item faltou, para o app remover e reapresentar |

### Bloqueio conhecido

O `SessionController` do app hoje **recusa comprador**:

```dart
// O painel é do lojista. Um comprador autentica sem erro, mas receberia
// 403 na primeira chamada de `/v1/seller/*` — melhor barrar aqui.
if (!sessao.isLojista) { _erro = 'Esta conta não é de lojista.'; }
```

Enquanto essa checagem existir, **nenhum comprador consegue ter carrinho no
servidor**. Não é detalhe de implementação: a Feature 2 depende de uma
mudança que pertence à Feature 3. Tratado no
[ADR 0003](0003-sessao-jwt-stateless-com-refresh.md).

### Dívida técnica registrada

- `flatShippingCents = 2490` continua no cliente. Frete calculado é
  explicitamente fora de escopo (ADR 0001 §3), mas a constante precisa migrar
  para o servidor antes de virar valor cobrado de alguém.
- `cart_items` não tem índice por `productId`; só será problema quando houver
  necessidade de responder "quantos carrinhos contêm este produto".

---

## 5. Questões em aberto

1. **Limite de quantidade por item.** Hoje o stepper não tem teto. Limitar
   pelo `stock` atual dá falsa sensação de reserva; não limitar deixa alguém
   colocar 9.999 unidades. Provável saída: teto pelo estoque **na leitura**,
   com o `409` do commit continuando sendo a autoridade.
2. **TTL do carrinho.** Item de um ano atrás ainda deve aparecer?
3. **Carrinho anônimo com merge** — quando a conversão passar a ser medida.

---

## 6. Referências

- [`template-features.md`](../../template-features.md) — Feature 2, entregas E2E 1 a 3
- [`docs/api-design.md §2.4`](../api-design.md) — contrato de `/v1/cart`
- [`docs/data-model.md`](../data-model.md) — `carts`, `cart_items`
- [`app_achou/lib/state/cart_controller.dart`](../../app_achou/lib/state/cart_controller.dart) — o que vira cache
- [ADR 0001](0001-checkout-no-app-com-confirmacao-externa.md) §6.1 — questão que esta decisão fecha
