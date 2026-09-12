# ADR 0003 — Sessão por JWT stateless, com par access/refresh e papel no token

| | |
|---|---|
| **Status** | Aceito — com pendências bloqueantes em §5 |
| **Data** | 2026-09-11 |
| **Contexto de origem** | [`template-features.md`](../../template-features.md) — Feature 3, `Autenticação de dados via login` |
| **Decisores** | Equipe 4 |
| **Relacionado** | Desbloqueia o [ADR 0002](0002-carrinho-no-servidor-sem-reserva-de-estoque.md) §4 |

---

## 1. Contexto

Diferente das Features 1 e 2, esta **já está implementada no backend**. O ADR
existe para registrar por que ficou assim e, principalmente, para nomear o que
foi deixado para trás — porque a Feature 3 promete uma coisa que o código
hoje não faz.

O que existe:

| Camada | Situação |
|---|---|
| Backend | [`auth.service.ts`](../../backend/src/auth/auth.service.ts) — register, login, refresh, me. `bcrypt` com cost 10 |
| Backend | [`jwt.strategy.ts`](../../backend/src/auth/jwt.strategy.ts) — Passport JWT, `Bearer`, sem tolerância de expiração |
| Backend | [`roles.guard.ts`](../../backend/src/auth/guards/roles.guard.ts) — autorização por `Role` lida do próprio token |
| Banco | `users.role` é enum `COMPRADOR \| LOJISTA`; `sellers` é 1:1 opcional com `users` |
| App | [`session_controller.dart`](../../app_achou/lib/state/session_controller.dart) — sessão **em memória**, com renovação silenciosa no 401 |

A arquitetura do README já exigia duas coisas do formato de sessão: o API
Gateway **valida o JWT na borda**, antes de chegar na aplicação, e o app
Flutter é um binário único que *"alterna navegação por perfil, role embutida
no JWT"*.

Isso restringe o espaço de escolha antes mesmo de discutir: uma sessão que
exige consulta a banco para ser validada não pode ser validada na borda.

---

## 2. Decisão

### 2.1 Token stateless, assinado, validado sem ida ao banco.

JWT HS256 com segredo compartilhado. Nenhuma tabela de sessão. O gateway
valida assinatura e expiração; a aplicação confia no que chegou.

### 2.2 Dois tokens, com tipo declarado dentro do payload.

| Token | Duração | Serve para |
|---|---|---|
| `access` | 15 min (`JWT_ACCESS_EXPIRES`) | Autenticar qualquer requisição |
| `refresh` | 7 dias (`JWT_REFRESH_EXPIRES`) | Só `/auth/refresh` |

Os dois saem da mesma chave e se distinguem pelo campo `type`. A
`JwtStrategy` **rejeita explicitamente** um refresh usado como access:

```ts
// Refresh token nao autentica requisicao: so serve em /auth/refresh.
// Sem esta checagem, um refresh token valeria como access token.
if (payload.type === 'refresh') { throw new UnauthorizedException(...); }
```

Sem essa linha, o par de durações seria decorativo: bastaria mandar o token
de 7 dias no `Authorization` para anular a janela de 15 minutos.

### 2.3 `role` e `sellerId` viajam no token.

O `RolesGuard` autoriza lendo o próprio payload, sem `SELECT`. É o que torna
`/v1/seller/*` barato e o que permite ao app desenhar a navegação certa sem
uma chamada extra.

### 2.4 Erro de login é deliberadamente vago.

E-mail inexistente e senha errada devolvem `CREDENCIAIS_INVALIDAS`, a mesma
mensagem — já implementado, com a razão no código: mensagens distintas deixam
enumerar quais e-mails têm conta.

---

## 3. Alternativas consideradas

### A. Sessão em servidor (cookie + tabela `sessions` ou Redis)

| | |
|---|---|
| **Prós** | Revogação imediata — logout mata a sessão de verdade; dá para listar e derrubar dispositivos |
| **Contras** | Toda requisição consulta o store. Quebra a validação na borda desenhada no README e coloca o Redis no caminho crítico de 100% do tráfego autenticado, não só do catálogo |
| **Por que não** | O custo é pago em toda requisição para comprar um benefício (revogação) cuja ausência dura no máximo 15 minutos no access token. |

### B. Token único de vida longa

| | |
|---|---|
| **Prós** | Mais simples: sem refresh, sem `type`, sem renovação silenciosa |
| **Contras** | Token vazado vale até expirar. Curto força relogin constante; longo é um risco permanente |
| **Por que não** | O par access/refresh é justamente o mecanismo que separa "exposição" de "conveniência". |

### C. Provedor externo (Auth0, Firebase Auth, Supabase)

| | |
|---|---|
| **Prós** | Recuperação de senha, verificação de e-mail, MFA e social login de graça — tudo que a Feature 3 chama de "elefante" |
| **Contras** | Dependência externa no login, vendor lock-in no modelo de usuário, e `sellers` continuaria sendo nosso de qualquer jeito |
| **Por que não** | Não pelo mérito — é uma opção legítima e talvez a certa mais adiante. Aqui a Feature 3 é também exercício de aprendizado sobre hash, sessão e guard; terceirizar isso esvazia a feature. Reavaliar quando o "elefante" entrar na fila de verdade. |

### D. RS256 (par de chaves) em vez de HS256

| | |
|---|---|
| **Prós** | O gateway valida com a chave **pública**; só o auth assina. Segredo de assinatura nunca sai do serviço que emite |
| **Contras** | Distribuição de chave, rotação, JWKS |
| **Por que não agora** | Com um backend único emitindo e validando, HS256 basta. **Vira obrigatório** quando o gateway da arquitetura do README existir de fato — registrado em §5.3. |

---

## 4. Consequências

### Positivas

- Validação sem I/O: o custo de autenticar é verificar uma assinatura.
- `RolesGuard` autoriza sem consultar banco; `/v1/seller/*` fica protegido
  por um decorator.
- Renovação silenciosa já implementada no app: o 401 vira `refresh` e a ação
  do usuário continua, em vez de jogá-lo no login no meio de um cadastro.
- A resposta de login já carrega `sellerId`, então o app sabe se desenha
  painel ou vitrine sem uma segunda chamada.

### Negativas e riscos assumidos

| Risco | Mitigação |
|---|---|
| **Logout não revoga nada.** O access token continua válido até expirar | Janela limitada a 15 min. Aceito conscientemente — revogação real exige a opção A |
| **Refresh de 7 dias não é rotacionado nem invalidado** | Um refresh vazado vale a semana inteira. Rotação na renovação + `jti` em denylist é a evolução natural |
| **`role` no token fica velha.** Promover comprador a lojista não vale até o token expirar | Aceito: a mudança de papel é rara e o atraso é de minutos |
| **Troca de senha não derruba sessões existentes** | Mesmo caminho da rotação de refresh |

### Dívida técnica registrada

Em `jwt.strategy.ts` e `auth.module.ts`:

```ts
secretOrKey: config.get<string>('JWT_SECRET') ?? 'dev_secret',
```

O fallback é conveniente em desenvolvimento e **perigoso em produção**: um
deploy sem `JWT_SECRET` sobe funcionando, assinando tokens com um segredo
que está no repositório público. Qualquer pessoa forjaria um token de
lojista. Deve virar falha de boot quando `NODE_ENV=production`.

---

## 5. Pendências bloqueantes

Três itens em que o código entregue **não cumpre** a Feature 3 ou bloqueia as
outras. Não são melhorias — são o resto da feature.

### 5.1 A sessão não sobrevive a fechar o app

A entrega E2E 3 da Feature 3 diz: *"ao reabrir o app, a sessão válida é
recuperada"*. O `SessionController` diz o contrário:

```dart
/// Sessão do lojista. Vive em memória: fechou o app, precisa entrar de novo.
/// Persistir o refresh token é assunto para quando houver onde guardá-lo com
/// segurança (Keychain / Keystore), não `SharedPreferences`.
```

A ressalva do comentário está correta — refresh token em `SharedPreferences`
é texto plano lido por qualquer backup. **Decisão:** persistir o refresh
token em `flutter_secure_storage` (Keychain no iOS, Keystore no Android) e
restaurar a sessão no boot chamando `/auth/refresh`. O access token continua
só em memória; ele dura 15 minutos e não vale o risco de ser guardado.

### 5.2 Comprador não consegue autenticar no app

O `SessionController` recusa qualquer conta que não seja lojista:

```dart
if (!sessao.isLojista) { _erro = 'Esta conta não é de lojista.'; }
```

Era correto quando a única tela autenticada era o painel. Deixa de ser no
momento em que o carrinho vai para o servidor (ADR 0002 §2.2) e o checkout
cria pedido em nome de um comprador (ADR 0001). **Decisão:** a sessão passa a
aceitar os dois papéis; a restrição de perfil migra para a navegação, que já
é o lugar onde o README a colocou.

O backend não muda: `RolesGuard` e `users.role` já tratam os dois papéis.

### 5.3 RS256 quando o gateway existir

Enquanto emissor e validador são o mesmo processo, HS256 basta. No momento em
que o API Gateway da arquitetura passar a validar JWT na borda, distribuir o
segredo de **assinatura** para ele significa que quem valida também pode
forjar. Migrar para RS256 antes desse passo, não depois.

---

## 6. Questões em aberto

1. **Recuperação de senha** não existe. Sem ela, conta com senha esquecida é
   conta perdida — e isso pesa mais no lojista, que tem produto cadastrado.
2. **Rate limiting no login.** `api-design.md §4` define limites de escrita,
   mas `/auth/login` precisa de um limite próprio, por e-mail e por IP, senão
   a resposta genérica do §2.4 protege contra enumeração e não contra força
   bruta.
3. **Cost 10 do bcrypt** foi o default, não uma medição. Vale calibrar pelo
   tempo real na máquina de produção.

---

## 7. Referências

- [`template-features.md`](../../template-features.md) — Feature 3, entregas E2E 1 a 3
- [`README.md`](../../README.md) — arquitetura: gateway valida JWT na borda, role embutida no token
- [`backend/src/auth/`](../../backend/src/auth/) — implementação atual
- [`app_achou/lib/state/session_controller.dart`](../../app_achou/lib/state/session_controller.dart) — §5.1 e §5.2
- [ADR 0002](0002-carrinho-no-servidor-sem-reserva-de-estoque.md) §4 — o bloqueio que §5.2 remove
