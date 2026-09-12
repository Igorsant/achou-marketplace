# ADR 0001 — Checkout no app com confirmação de pagamento fora dele

| | |
|---|---|
| **Status** | Aceito |
| **Data** | 2026-09-11 |
| **Contexto de origem** | [`template-features.md`](../../template-features.md) — Feature 1, `Checkout pelo aplicativo` |
| **Decisores** | Equipe 4 |
| **Substitui** | — |

---

## 1. Contexto

A Feature 1 é o fim do caminho de compra: o comprador já tem produtos no
carrinho (Feature 2) e está autenticado (Feature 3). Falta transformar o
carrinho em **pedido** e o pedido em **dinheiro**.

Hoje o repositório está assim:

| Camada | Situação |
|---|---|
| App Flutter | [`checkout_page.dart`](../../app_achou/lib/features/checkout/checkout_page.dart) existe, com resumo, forma de pagamento e `Idempotency-Key` gerada no cliente |
| App Flutter | [`checkout_repository.dart`](../../app_achou/lib/data/repositories/checkout_repository.dart) só tem `MockCheckoutRepository` — aprova ou recusa sorteando, sem rede |
| Backend | `POST /v1/orders` está especificado em [`docs/api-design.md`](../api-design.md#25-pedidos-e-pagamento--v1orders) e **não existe** em `backend/src/` |
| Banco | `orders`, `order_items` e `payments` já estão migrados, com `payments.provider` default `"mock"` |
| Pagamento | Nenhum gateway contratado, nenhuma conta de PSP, nenhum CNPJ da operação |

O prazo do MVP é de ~3 dias ponta a ponta. Integrar um PSP de verdade
(Mercado Pago, Stripe, Pagar.me) não é problema de código: é onboarding,
documento, conta bancária de recebimento e homologação de webhook — semanas
de calendário que não dependem da equipe. Ao mesmo tempo, um checkout que
termina em `MockCheckoutRepository` não é comercializável: nenhum lojista
recebe nada.

A pergunta que este ADR responde: **o que exatamente acontece quando o
comprador toca em "Confirmar pedido", enquanto não há gateway?**

---

## 2. Forças em jogo

- **Conversão.** O comprador precisa sair do app achando que comprou, não que
  preencheu um formulário.
- **Viabilidade em 3 dias.** Sem dependência de terceiro no caminho crítico.
- **Integridade do pedido.** Estoque, preço e duplo-toque são problemas de
  concorrência que existem mesmo sem dinheiro envolvido — e já têm solução
  desenhada em [`api-design.md §3.2–3.5`](../api-design.md#32-concorrência-no-estoque).
- **Custo de troca.** Quando o gateway chegar, o que for escrito agora não
  pode precisar ser jogado fora.
- **Honestidade com o usuário.** O app não pode sugerir que cobrou algo que
  não cobrou.

---

## 3. Decisão

**O pedido é criado e persistido pelo backend do Achou!; a cobrança é
entregue a um canal externo (WhatsApp do lojista), e o pedido fica em
`PENDING_PAYMENT` até que o lojista confirme o recebimento.**

Concretamente:

1. `POST /v1/orders` é implementado **de verdade**, com a transação completa
   já especificada: valida carrinho → decremento condicional de estoque →
   `INSERT order + order_items` com snapshot de preço → `INSERT outbox` →
   limpa carrinho. Nada disso é adiado por não haver gateway.
2. O checkout passa a coletar **dados de entrega** e grava-os no pedido.
3. Ao commitar, o app abre o WhatsApp do lojista (`https://wa.me/...`) com o
   resumo do pedido — número, itens, total, entrega e forma de pagamento
   escolhida — pré-preenchido.
4. `payments.provider` recebe `"whatsapp"` e o `Payment` nasce `PENDING`.
   `providerRef` fica nulo até haver comprovante.
5. O lojista confirma o pagamento **no painel do app**, e só então o pedido
   vai para `PAID`. A transição continua sendo do backend, não do WhatsApp.
6. O app mostra o pedido como *aguardando confirmação do vendedor*, com o
   histórico acessível — o comprador nunca fica sem saber em que pé está.

### Máquina de estados resultante

```
                    ┌──────────────────┐
  POST /v1/orders   │ PENDING_PAYMENT  │  ← handoff pro WhatsApp acontece aqui
  (transação)   ──► │ payment: PENDING │
                    └────────┬─────────┘
                             │
        lojista confirma ────┤──── comprador/lojista cancela
        no painel            │            ou expira (TTL)
                             │
              ┌──────────────▼───┐        ┌───────────┐
              │ PAID             │        │ CANCELLED │
              │ payment:AUTHORIZED│       │ +devolve  │
              └──────────┬───────┘        │  estoque  │
                         │                └───────────┘
                    FULFILLED
```

O grafo é **o mesmo** já documentado em `api-design.md`. A decisão não
inventa estado novo: ela define *quem* dispara a transição enquanto não há
webhook. Hoje é um humano no painel do lojista; amanhã é o callback do PSP.

### O que fica explicitamente de fora

- Cálculo de frete real (valor é simulado, campo existe).
- Cupons e descontos.
- Split de pagamento entre lojistas do mesmo pedido.
- Captura de dados de cartão no app — **nunca**, nem depois: isso é
  responsabilidade do SDK do PSP, e coletar PAN traz escopo PCI-DSS junto.

---

## 4. Alternativas consideradas

### A. Integrar um PSP de verdade agora

| | |
|---|---|
| **Prós** | Fluxo definitivo, confirmação automática, sem trabalho manual do lojista |
| **Contras** | Onboarding do PSP não cabe em 3 dias; exige CNPJ e conta de recebimento que o projeto não tem; webhook precisa de endpoint público e assinatura verificada |
| **Por que não** | Bloqueia a entrega ponta a ponta por uma dependência externa que a equipe não controla. O MVP ficaria *pronto porém não demonstrável*. |

### B. Manter só o mock (estado atual)

| | |
|---|---|
| **Prós** | Zero trabalho; a tela já funciona e demonstra bem |
| **Contras** | Nenhum lojista recebe pedido, nenhum dado é persistido, o estoque nunca baixa. O carrinho e o login perdem o sentido — não existe ponta final |
| **Por que não** | Não é um MVP comercializável, que é o critério declarado da Feature 1. |

### C. Pix estático (chave copia-e-cola exibida no app)

| | |
|---|---|
| **Prós** | Sem PSP, sem contato externo, comprador paga na hora |
| **Contras** | Uma chave por lojista precisa ser cadastrada e verificada; sem API bancária não há como saber que o pagamento caiu — a conciliação continua manual; comprovante vira print no WhatsApp de qualquer jeito |
| **Por que não** | Tem o mesmo custo de confirmação manual da opção escolhida, mas sem o canal de conversa onde o lojista já resolve dúvida, combina entrega e negocia. É uma alternativa **complementar**, não concorrente — ver §7. |

### D. Checkout inteiramente no WhatsApp (app só monta a mensagem)

| | |
|---|---|
| **Prós** | Implementação trivial: um `launchUrl` e acabou |
| **Contras** | Sem `orders`, sem baixa de estoque, sem histórico, sem idempotência. O marketplace vira um gerador de link |
| **Por que não** | Joga fora justamente a parte que não precisa de gateway nenhum para funcionar. O pedido é o ativo do negócio; ele tem que nascer no nosso banco. |

---

## 5. Consequências

### Positivas

- O caminho crítico fica **inteiramente sob controle da equipe** — nenhuma
  entrega depende de aprovação de terceiro.
- Toda a engenharia difícil do checkout (transação, estoque concorrente,
  idempotência, snapshot de preço, outbox) é escrita **agora** e sobrevive
  à troca do meio de pagamento.
- A troca por um PSP é localizada: novo adapter de `Payment`, um webhook que
  faz a mesma transição `PENDING_PAYMENT → PAID` que o painel faz hoje.
  `MockCheckoutRepository` sai e entra `HttpCheckoutRepository` no app, sem
  mexer nas telas — o abstrato já está no lugar.
- O lojista entra no fluxo desde o dia 1, e é dele que vem o feedback que
  define o gateway certo depois.

### Negativas e riscos assumidos

| Risco | Mitigação |
|---|---|
| **Confirmação depende de ação humana** — lojista esquece, pedido trava em `PENDING_PAYMENT` | TTL de cancelamento automático com devolução de estoque; notificação ao lojista pelo worker de notificações já existente |
| **Estoque fica preso** entre o pedido e a confirmação | O decremento é imediato no commit; o cancelamento por TTL devolve. Trade-off deliberado: overselling é pior que reserva temporária |
| **Lojista pode marcar como pago sem ter recebido** | Aceito no MVP: o prejuízo é do próprio lojista. Com PSP, a confirmação deixa de ser dele |
| **Sai do app** e pode não voltar | O pedido já está criado antes do redirecionamento — a conversão acontece no commit, não no retorno |
| **Número de WhatsApp do lojista** vira dado obrigatório e sensível | Campo novo em `sellers`, validado no cadastro; exibido só ao comprador que tem pedido com aquele lojista |
| **Pedido com mais de um lojista** não tem um WhatsApp único | Ver §6 |

### Dívida técnica registrada

- `payments.provider` passa a ter dois valores possíveis (`"mock"`,
  `"whatsapp"`) sem ser enum — mantido como texto de propósito, porque
  o terceiro valor será o nome do PSP.
- A confirmação manual precisa de trilha de auditoria (quem confirmou,
  quando) antes de qualquer operação real com dinheiro de terceiro.

---

## 6. Questões em aberto

1. ~~**Pedido multi-lojista.**~~ **Resolvido pelo
   [ADR 0002](0002-carrinho-no-servidor-sem-reserva-de-estoque.md) §2.3:** o
   carrinho aceita vários lojistas e o checkout quebra em um pedido por
   lojista, na mesma transação, com `Idempotency-Key` derivada
   (`{key}:{sellerId}`). Cada pedido tem seu próprio handoff de WhatsApp.
2. **Onde moram os dados de entrega.** `orders` não tem endereço. Colunas
   novas em `orders` (simples, suficiente) ou tabela `addresses`
   reaproveitável? O MVP não reaproveita nada ainda.
3. **Valor do TTL** de cancelamento automático — 24h é o palpite inicial.

---

## 7. Caminho de evolução

```
hoje            ADR 0001              próximo               definitivo
────────────────────────────────────────────────────────────────────────
mock local  →   pedido real no       pedido real +      pedido real +
no Flutter      backend +            Pix estático       PSP com webhook
                handoff WhatsApp     no app             (confirmação
                (confirmação         (§4-C como          automática)
                 manual)             complemento)
```

Cada passo mantém `POST /v1/orders` e a máquina de estados intactos. O que
muda é apenas **quem** informa que o dinheiro chegou.

---

## 8. Referências

- [`template-features.md`](../../template-features.md) — Feature 1, entregas E2E 1 a 3
- [`docs/api-design.md §2.5, §3.2–3.5`](../api-design.md) — contrato, concorrência de estoque, idempotência, transação
- [`docs/data-model.md`](../data-model.md) — `orders`, `order_items`, `payments`
- [`backend/prisma/schema.prisma`](../../backend/prisma/schema.prisma) — enums `OrderStatus` e `PaymentStatus`
- [`app_achou/lib/data/repositories/checkout_repository.dart`](../../app_achou/lib/data/repositories/checkout_repository.dart) — abstração que absorve a troca
