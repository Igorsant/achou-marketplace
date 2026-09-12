# Architecture Decision Records

Decisões **técnicas** que mudam a forma do sistema e cujo *porquê* não fica
óbvio lendo o código depois: onde mora o estado, qual constraint garante o quê,
qual mecanismo de concorrência, qual dado é copiado e qual é derivado.

O que **não** entra: decisão de produto. Se o checkout entrega a cobrança a um
canal externo ou a um PSP, se o carrinho aceita visitante, qual canal o lojista
usa para confirmar — isso muda por razão de negócio, não de engenharia, e o ADR
que o registra envelhece a cada conversa de roadmap. O que o ADR registra é a
consequência técnica: que a transição de estado seja um ponto de extensão, que
`carts.user_id` seja `NOT NULL`, que `payments.provider` seja texto.

Um ADR também não é documentação de implementação — para isso existem
[`api-design.md`](../api-design.md) e [`data-model.md`](../data-model.md).

ADR não se edita para mudar de ideia: cria-se um novo com status `Substitui`
apontando para o antigo, e o antigo vira `Substituído por`. Editar para
corrigir enquadramento ou registrar estado de implementação é outra coisa, e é
permitido — a decisão continua a mesma.

| # | Decisão técnica | Status | Implementação | Data |
|---|---|---|---|---|
| [0001](0001-checkout-no-app-com-confirmacao-externa.md) | Commit do pedido: idempotência no banco, decremento condicional e outbox | Aceito | Schema ✅ · serviço ⏳¹ | 2026-09-11 |
| [0002](0002-carrinho-no-servidor-sem-reserva-de-estoque.md) | Carrinho: estado no servidor, sem preço congelado, split por lojista | Aceito | Schema ✅ · serviço ⏳¹ | 2026-09-11 |
| [0003](0003-sessao-jwt-stateless-com-refresh.md) | Sessão por JWT stateless, com par access/refresh e papel no token | Aceito² | Backend ✅ · app ⚠️ | 2026-09-11 |

¹ Escopo **diferido de propósito** no MVP, não entrega atrasada. A parte que
mais custa reverter — as constraints — já está migrada; o serviço tem o
contrato escrito na suíte de integração correspondente.

² Aceito com pendências bloqueantes em §5: a Feature 3 foi declarada pronta e
tem duas lacunas no app. É uma situação diferente das duas acima, e o
relatório de pendências as separa (`BLOQUEIA` × `DIFERIDA`).

## Verificação automática

Um ADR aceito é uma afirmação sobre o sistema. Sem verificação, ele envelhece em
silêncio: alguém tira o `@unique` de `orders.idempotency_key`, alguém apaga a
checagem de `type: 'refresh'` na `JwtStrategy`, e o documento continua dizendo
que a decisão vale.

A verificação tem **dois níveis**, e a diferença importa:

| | Pergunta que responde | Onde |
|---|---|---|
| **estrutural** | a decisão está escrita no código? | [`scripts/adr-check.sh`](../../scripts/adr-check.sh) |
| **comportamental** | a decisão funciona? | [`backend/test/*.e2e-spec.ts`](../../backend/test) |

O nível estrutural é grep sobre fonte, schema e manifestos: barato, roda em
segundos, e pega remoção — apagar o `@unique` de `orders.idempotency_key` ou a
checagem de `type: 'refresh'`. Não pega **reescrita**: um `if` que existe e não
funciona passa pelo grep.

O nível comportamental sobe o `AppModule` contra um Postgres real e exerce as
rotas. É onde "o refresh token não autentica requisição" deixa de ser uma linha
de código e passa a ser um `401 TOKEN_INVALIDO` observado.

```bash
scripts/adr-check.sh            # estrutural: tudo
scripts/adr-check.sh 0003       # estrutural: só um ADR
scripts/adr-check.sh docs       # numeração, metadados, índice e links
scripts/adr-check.sh banco      # constraints no Postgres (exige DATABASE_URL)
scripts/adr-check.sh pendencias # o que os ADRs registram como não feito

scripts/test-e2e.sh             # comportamental: tudo
scripts/test-e2e.sh adr-0003    # comportamental: uma suíte
```

`scripts/test-e2e.sh` cria e migra um banco próprio (sufixo `_test` obrigatório
— as suítes truncam tabelas) e nunca toca o banco de desenvolvimento.

### Suítes que esperam a implementação

As decisões dos ADRs 0001 e 0002 dependem de `POST /v1/orders` e `/v1/cart`, que
ainda não existem. As suítes dos dois estão **escritas por completo** e se ativam
sozinhas quando `src/orders/` e `src/cart/` aparecerem; até lá ficam pendentes em
vez de vermelhas.

Isso as torna a definição de pronto das duas features: idempotência que devolve
o mesmo pedido, `409` com rollback total quando falta estoque em uma das lojas,
snapshot de preço que sobrevive a reajuste, um pedido por lojista com
`Idempotency-Key` derivada, carrinho que reflete preço novo porque não congela
valor. Implementar a feature é fazer essas suítes passarem.

Duas categorias, deliberadamente separadas:

| | O que é | No CI |
|---|---|---|
| **invariante** | decisão já materializada no código ou no banco | derruba o build |
| **pendência** | o que o próprio ADR registra como bloqueante, dívida ou questão em aberto | relatório |

A separação existe porque um ADR honesto documenta o que falta. Se o que falta
derrubasse o build, o pipeline nasceria vermelho e perderia a função de sinal.

Toda pendência carrega um teste de resolução. Quando ele passa, o script cobra a
atualização do ADR — é o que impede a documentação de ficar atrasada em relação
ao código sem ninguém notar.
