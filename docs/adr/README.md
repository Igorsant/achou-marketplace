# Architecture Decision Records

Decisões que mudam a forma do sistema e cujo *porquê* não fica óbvio lendo o
código depois. Um ADR não é documentação de implementação — para isso existem
[`api-design.md`](../api-design.md) e [`data-model.md`](../data-model.md).

ADR não se edita para mudar de ideia: cria-se um novo com status `Substitui`
apontando para o antigo, e o antigo vira `Substituído por`.

| # | Decisão | Status | Data |
|---|---|---|---|
| [0001](0001-checkout-no-app-com-confirmacao-externa.md) | Checkout no app com confirmação de pagamento fora dele | Aceito | 2026-09-11 |
| [0002](0002-carrinho-no-servidor-sem-reserva-de-estoque.md) | Carrinho no servidor, multi-lojista, sem reserva de estoque | Aceito | 2026-09-11 |
| [0003](0003-sessao-jwt-stateless-com-refresh.md) | Sessão por JWT stateless, com par access/refresh e papel no token | Aceito¹ | 2026-09-11 |

¹ Aceito com pendências bloqueantes registradas em §5 — ver o próprio ADR.
