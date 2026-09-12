# ADR 0001 — Interface HTTP: REST sobre recursos, versionada no path

| | |
|---|---|
| **Status** | Aceito |
| **Data** | 2026-09-11 |
| **Implementação** | Completa — ver §8 |
| **Contexto de origem** | Arquitetura do [`README.md`](../../README.md); contrato em [`api-design.md`](../api-design.md) |
| **Decisores** | Equipe 4 |
| **Verificação** | [`scripts/adr-check.sh 0001`](../../scripts/adr-check.sh) · [`backend/test/adr-0001-rest.e2e-spec.ts`](../../backend/test/adr-0001-rest.e2e-spec.ts) |
| **Substitui** | — |

---

## 1. Contexto

O sistema tem um cliente — um app Flutter — e um backend NestJS. Entre os dois
existe uma escolha de estilo de interface que precede qualquer rota: **como o
cliente pede coisas ao servidor**.

A decisão é cara de reverter. Ela determina o formato de cada handler, o
tratamento de erro, a estratégia de cache, a forma do cliente HTTP no app e o
que um gateway consegue fazer na borda sem entender o corpo da mensagem. Trocar
depois não é reescrever rotas: é reescrever as duas pontas.

Restrições dadas pela arquitetura já registrada no README:

| Restrição | Consequência |
|---|---|
| Um API Gateway valida o JWT **na borda** | O gateway precisa decidir autenticação sem interpretar o corpo — o que exige que a identidade do recurso esteja na URL e no método |
| Catálogo é **cacheável**; painel do lojista não | Precisa existir uma unidade de cache que CDN e Redis reconheçam sem lógica de aplicação |
| Cliente único, Flutter, `package:http` | Sem runtime de schema, sem code-gen no caminho crítico |
| Equipe de 4, prazo de ~3 dias | O custo de aprendizado da interface entra no orçamento |

---

## 2. Decisão

**A API é REST sobre HTTP, orientada a recursos, versionada no path.**

### 2.1 Recurso no path, ação no método HTTP

Rotas nomeiam **coisas**, no plural; o verbo HTTP diz o que fazer com elas.

```
GET    /v1/products            POST   /v1/seller/products
GET    /v1/products/:id        PATCH  /v1/seller/products/:id
DELETE /v1/seller/products/:id PATCH  /v1/seller/products/:id/stock
```

Não existe verbo no path (`/criarProduto`, `/getProducts`, `/v1/products/list`).
A consequência prática não é estética: é que método + URL passam a ser um par
suficiente para decidir cache, retry e autorização **sem abrir o corpo**. Um
`GET` é seguro e repetível por definição do protocolo; um `POST` não é. Quem
está na borda — gateway, proxy, CDN, o interceptor de retry do app — usa isso.

### 2.2 Versão no path (`/v1`), não em header

Toda rota vive sob `/v1`. Quando houver `/v2`, as duas coexistem no mesmo
processo e a migração do app é rota a rota.

Versionar por header (`Accept: application/vnd.achou.v2+json`) é mais
"correto" na leitura estrita de REST e pior na prática aqui: some da URL, some
do log, some do Postman, e o cache passa a depender de `Vary`, que CDN trata de
forma desigual. A versão no path é legível em qualquer ferramenta que fale
HTTP, e o custo é um prefixo.

`/health` fica fora de `/v1` de propósito: é sonda de infraestrutura, não parte
do contrato do cliente, e não deve ser versionada junto com ele.

### 2.3 Status HTTP é o canal de resultado

O resultado da operação vai no **código de status**, nunca em um campo do corpo:

| Status | Uso |
|---|---|
| `200` / `201` | Sucesso; `201` quando um recurso nasce |
| `400` | Payload malformado |
| `401` | Token ausente ou inválido |
| `403` | Autenticado, sem permissão |
| `404` | Recurso inexistente |
| `409` | Conflito de estado |
| `422` | Validação de negócio falhou |
| `429` | Rate limit estourado |

`200 {"success": false}` é proibido. Um envelope de sucesso que carrega falha
obriga todo cliente, proxy e monitor a interpretar o corpo para saber se deu
certo — e desliga de graça tudo que o protocolo já oferece: retry por classe de
erro, circuit breaker, alerta por taxa de 5xx, cache negativo.

### 2.4 Envelope de erro único, com `code` estável

```json
{ "error": { "code": "ESTOQUE_INSUFICIENTE", "message": "...", "details": {} } }
```

O status diz a **classe** do erro; `code` diz **qual** erro. O app decide
comportamento pelo `code` — nunca pelo `message`, que é texto de tela e muda
sem aviso. `details` carrega o que a tela precisa para agir (qual produto, qual
campo).

Um `HttpExceptionFilter` global normaliza tudo, inclusive a saída do
`ValidationPipe`, que sem ele responderia no formato do Nest
(`{"message":[...],"statusCode":400}`) e furaria o contrato em toda rota com
DTO.

### 2.5 Idempotência de escrita é convenção de header

`POST` não é idempotente por definição do método, e é justamente aí que o duplo
toque e o retry do app doem. A compensação é o header `Idempotency-Key`, gerado
pelo cliente, obrigatório nas escritas que criam recurso cobrável.

Isto é decisão de **interface**: o header, a obrigatoriedade e a semântica de
resposta (repetir a chave devolve o recurso existente com `200`, em vez de criar
outro com `201`). Como o servidor garante isso do lado de dentro não é assunto
deste ADR.

### 2.6 Separação por audiência no path

`/v1/products` é público e cacheável; `/v1/seller/*` exige `LOJISTA`. O prefixo,
não um campo do corpo nem um parâmetro, é o que separa os dois.

Isso torna a regra de cache e a regra de autorização expressáveis como prefixo
de URL — que é o vocabulário do gateway, do Ingress e da CDN. Uma API em que
público e privado compartilham a mesma URL não tem como ser cacheada na borda
sem risco de servir dado de um lojista para outro.

---

## 3. Alternativas consideradas

### A. GraphQL

| | |
|---|---|
| **Prós** | O app pede exatamente os campos de cada tela, sem over-fetching; um endpoint só; schema tipado gera cliente |
| **Contras** | Cache por URL deixa de existir — tudo é `POST /graphql` e a camada de cache precisa entender query, o que empurra Redis para dentro do resolver. Autorização passa a ser por campo, não por rota, e o gateway não consegue mais decidir na borda. N+1 vira problema estrutural, resolvido com dataloader |
| **Por que não** | O ganho é o over-fetching de um app com 6 telas e um cliente só. O custo é desmontar a validação na borda do README e a estratégia de cache do catálogo, que são duas restrições dadas. |

### B. gRPC

| | |
|---|---|
| **Prós** | Contrato forte em `.proto`, serialização binária, streaming, cliente gerado |
| **Contras** | Não roda nativamente em browser (exige grpc-web e proxy). O ecossistema de inspeção — Postman, `curl`, log de acesso, painel de CDN — fala HTTP/JSON, e nada disso funciona sem tradução. Nenhum CDN cacheia gRPC |
| **Por que não** | Faz sentido entre serviços internos com tráfego alto. Aqui a fronteira é cliente-servidor, com um cliente, e o que se ganha em bytes se perde em ferramenta. |

### C. RPC sobre HTTP (`POST /api/criarPedido`)

| | |
|---|---|
| **Prós** | Mapeamento direto de caso de uso para endpoint; nenhuma discussão sobre qual verbo usar |
| **Contras** | Tudo vira `POST`, então nada é cacheável nem seguro para retry. Status deixa de significar algo e o resultado migra para o corpo. Idempotência, autorização e cache viram convenção interna, redescoberta a cada endpoint novo |
| **Por que não** | Troca um vocabulário padronizado e compreendido por toda a infraestrutura por um vocabulário local. O ganho é evitar a pergunta "isto é PATCH ou POST?", que se responde uma vez. |

### D. REST estrito com HATEOAS

| | |
|---|---|
| **Prós** | Cliente descobre transições por links; servidor pode mudar URLs sem quebrar |
| **Contras** | Exige cliente que navegue por links em vez de montar URL, e nenhum cliente real faz isso — o app teria as rotas embutidas de qualquer jeito. Corpo cresce com metadados que ninguém lê |
| **Por que não** | Resolve acoplamento de URL entre times que não se falam. Aqui o cliente e o servidor são a mesma equipe e versionam juntos (§2.2). |

---

## 4. Consequências

### Positivas

- Método + URL bastam para decidir cache, retry e autorização. É o que permite
  a validação de JWT na borda e o cache do catálogo por prefixo.
- O erro tem uma forma só em toda a API, e o app tem um ponto só de tradução.
- Qualquer ferramenta que fale HTTP inspeciona o sistema: `curl`, Postman, log
  de acesso, métrica por status. A collection do Postman **é** a documentação
  executável do contrato.
- Swagger sai de graça dos decorators do Nest, sem passo de build.

### Negativas e riscos assumidos

| Risco | Mitigação |
|---|---|
| **Over-fetching**: a vitrine devolve campos que a tela não usa | Aceito. A alternativa é um endpoint por tela, que acopla a API ao layout |
| **Telas compostas custam N requisições** | Aceito no MVP. Se doer, a saída é um recurso agregado (`/v1/home`), não trocar o estilo |
| **Versionar é manter `/v1` vivo** depois que `/v2` nascer | Convivência no mesmo processo (§2.2); só a rota que muda ganha versão nova |
| **`code` de erro vira contrato público** — renomear quebra o app | Por isso ele é estável e o `message` não. Códigos novos são aditivos |
| **Discussão recorrente sobre qual verbo usar** em operação que não é CRUD | `PATCH /resource/:id/subrecurso` (ex.: `/stock`) como forma padrão para transição de estado |

### Dívida técnica registrada

- Nenhuma rota emite `ETag` nem `Cache-Control`. O cache do catálogo é
  server-side (Redis); o cache HTTP, que é o ganho natural deste estilo, ainda
  não foi explorado.
- `/health` não tem versão nem contrato declarado — aceitável enquanto for
  sonda de infraestrutura, problema no dia em que alguém depender dele.

---

## 5. Questões em aberto

1. **Paginação**: hoje `limit`/`offset` em query string. Cursor é melhor sob
   escrita concorrente, e a decisão não foi tomada explicitamente.
2. **Recurso agregado para a home**, se as N requisições da tela inicial
   virarem problema medido.
3. **`PUT` não é usado em lugar nenhum** — toda atualização é `PATCH` parcial.
   Vale registrar como regra ou deixar caso a caso?

---

## 6. Caminho de evolução

```
hoje                    próximo                 se doer
──────────────────────────────────────────────────────────────
REST /v1            →   ETag e Cache-Control    →   recurso agregado
JSON, status HTTP       na borda                    por tela composta
```

Nenhum desses passos troca o estilo: os dois primeiros são propriedades que
REST já oferece e o projeto ainda não usou.

---

## 7. Referências

- [`docs/api-design.md`](../api-design.md) — o contrato que materializa esta decisão
- [`README.md`](../../README.md) — gateway validando JWT na borda; cacheabilidade do catálogo
- [`docs/achou-marketplace.postman_collection.json`](../achou-marketplace.postman_collection.json) — contrato executável
- [`backend/src/common/filters/http-exception.filter.ts`](../../backend/src/common/filters/http-exception.filter.ts) — §2.4
- [ADR 0002](0002-carrinho-no-servidor-sem-reserva-de-estoque.md) — recurso `/v1/cart` sob este estilo
- [ADR 0003](0003-sessao-jwt-stateless-com-refresh.md) — autenticação por `Bearer`, validável na borda por causa do §2.1

---

## 8. Estado da implementação

Diferente dos ADRs 0002 e 0003, esta decisão está **inteiramente implementada**
— ela é anterior a qualquer feature, e toda rota existente já a obedece. É
também a mais barata de verificar: o estilo aparece na forma das rotas e das
respostas, que um teste de integração observa direto.

| Decisão | Estado | Onde é verificado |
|---|---|---|
| §2.1 recurso no path, sem verbo | ✅ | `adr-check.sh 0001` (proíbe verbo em `@Controller`/`@Get`/…) |
| §2.2 tudo sob `/v1`, exceto `/health` | ✅ | `adr-check.sh 0001` · `adr-0001-rest.e2e-spec.ts` |
| §2.3 status HTTP como canal de resultado | ✅ | `adr-0001-rest.e2e-spec.ts` (401/403/404/409/429 observados) |
| §2.3 nenhum `success: false` no corpo | ✅ | `adr-check.sh 0001` |
| §2.4 envelope de erro único com `code` | ✅ | `adr-check.sh 0001` (filtro global) · `adr-0001-rest.e2e-spec.ts` |
| §2.5 header `Idempotency-Key` no cliente | ✅ no app | `adr-check.sh 0001` |
| §2.6 separação por prefixo de audiência | ✅ | `adr-0001-rest.e2e-spec.ts` |
| §4 `ETag`/`Cache-Control` | ⏳ dívida | — |
