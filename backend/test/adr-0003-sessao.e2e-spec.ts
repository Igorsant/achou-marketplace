import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { criarApp, AppDeTeste } from './apoio/app';
import { limpar, prisma, criarComprador, criarLojista, SENHA } from './apoio/banco';

/**
 * ADR 0003 — sessao por JWT stateless, par access/refresh, papel no token.
 *
 * Cada caso aqui corresponde a uma frase do ADR. A diferenca em relacao ao
 * `scripts/adr-check.sh`: lá o teste e "a linha existe no arquivo", aqui e "o
 * servidor se comporta assim". Apagar a checagem de `type` faz o grep falhar;
 * *reescrever* a checagem de um jeito que nao funciona so falha aqui.
 */
describe('ADR 0003 — sessao JWT stateless', () => {
  let ctx: AppDeTeste;
  let jwt: JwtService;

  const segredo = () => process.env.JWT_SECRET ?? 'dev_secret';

  beforeAll(async () => {
    ctx = await criarApp();
    jwt = ctx.app.get(JwtService);
  });

  afterAll(async () => {
    await ctx.encerrar();
    await prisma.$disconnect();
  });

  beforeEach(limpar);

  // ------------------------------------------------------------ §2.2 o par

  describe('§2.2 — dois tokens, distinguidos pelo campo type', () => {
    it('login devolve access e refresh, e os dois declaram seu type', async () => {
      const user = await criarComprador();

      const res = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA })
        .expect(200);

      expect(res.body.accessToken).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();
      expect(jwt.decode(res.body.accessToken)).toMatchObject({ type: 'access' });
      expect(jwt.decode(res.body.refreshToken)).toMatchObject({ type: 'refresh' });
    });

    /**
     * O caso central do ADR. Sem a checagem na JwtStrategy, o token de 7 dias
     * autenticaria requisicao e a janela de 15 minutos seria decorativa — o
     * proprio ADR diz isso em §2.2.
     */
    it('refresh token NAO autentica requisicao', async () => {
      const user = await criarComprador();
      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA });

      // Prova que o refresh e valido como token antes de exigir que seja
      // recusado: senao o 401 poderia vir de assinatura ruim, nao da regra.
      expect(() => jwt.verify(body.refreshToken, { secret: segredo() })).not.toThrow();

      const res = await request(ctx.servidor)
        .get('/v1/auth/me')
        .set('Authorization', `Bearer ${body.refreshToken}`)
        .expect(401);

      expect(res.body.error.code).toBe('TOKEN_INVALIDO');
    });

    it('access token NAO serve para renovar', async () => {
      const user = await criarComprador();
      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA });

      const res = await request(ctx.servidor)
        .post('/v1/auth/refresh')
        .send({ refreshToken: body.accessToken })
        .expect(401);

      expect(res.body.error.code).toBe('REFRESH_INVALIDO');
    });

    it('access dura 15 min e refresh dura 7 dias', async () => {
      const user = await criarComprador();
      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA });

      const vida = (token: string) => {
        const { iat, exp } = jwt.decode(token) as { iat: number; exp: number };
        return exp - iat;
      };

      expect(vida(body.accessToken)).toBe(15 * 60);
      expect(vida(body.refreshToken)).toBe(7 * 24 * 60 * 60);
    });

    it('refresh devolve um par novo e utilizavel', async () => {
      const user = await criarComprador();
      const login = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA });

      const res = await request(ctx.servidor)
        .post('/v1/auth/refresh')
        .send({ refreshToken: login.body.refreshToken })
        .expect(200);

      expect(res.body.accessToken).toBeDefined();
      await request(ctx.servidor)
        .get('/v1/auth/me')
        .set('Authorization', `Bearer ${res.body.accessToken}`)
        .expect(200);
    });
  });

  // -------------------------------------------------- §2.1 stateless, sem I/O

  describe('§2.1 — token assinado, validado sem ida ao banco', () => {
    it('token expirado e recusado (ignoreExpiration: false)', async () => {
      const user = await criarComprador();
      const expirado = jwt.sign(
        { sub: user.id, email: user.email, role: user.role, type: 'access' },
        { secret: segredo(), expiresIn: '-1s' },
      );

      await request(ctx.servidor)
        .get('/v1/auth/me')
        .set('Authorization', `Bearer ${expirado}`)
        .expect(401);
    });

    it('token assinado com outro segredo e recusado', async () => {
      const user = await criarComprador();
      const forjado = jwt.sign(
        { sub: user.id, email: user.email, role: user.role, type: 'access' },
        { secret: 'outro_segredo_qualquer', expiresIn: '15m' },
      );

      await request(ctx.servidor)
        .get('/v1/auth/me')
        .set('Authorization', `Bearer ${forjado}`)
        .expect(401);
    });

    it('sem Authorization, rota autenticada responde 401', async () => {
      await request(ctx.servidor).get('/v1/auth/me').expect(401);
    });

    /**
     * Risco declarado em §4: "role no token fica velha — promover comprador a
     * lojista nao vale até o token expirar". O teste trava o trade-off: se
     * alguem acrescentar um SELECT de conferencia no guard, este caso quebra e
     * o ADR precisa ser reescrito (ou o SELECT removido). Um ADR que aceita um
     * risco conscientemente merece um teste que mostre o risco existindo.
     */
    it('role do token vale mesmo depois de mudar no banco (risco aceito)', async () => {
      const user = await criarLojista();
      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA })
        .expect(200);

      // Rebaixado no banco, token antigo na mao.
      await prisma.user.update({ where: { id: user.id }, data: { role: 'COMPRADOR' } });

      await request(ctx.servidor)
        .get('/v1/seller/products')
        .set('Authorization', `Bearer ${body.accessToken}`)
        .expect(200);
    });
  });

  // ------------------------------------------- §2.3 role e sellerId no token

  describe('§2.3 — role e sellerId viajam no token', () => {
    it('lojista recebe sellerId no token e na resposta', async () => {
      const user = await criarLojista();

      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA })
        .expect(200);

      expect(body.user.sellerId).toBe(user.seller!.id);
      expect(jwt.decode(body.accessToken)).toMatchObject({
        role: 'LOJISTA',
        sellerId: user.seller!.id,
      });
    });

    it('comprador nao recebe sellerId', async () => {
      const user = await criarComprador();

      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA })
        .expect(200);

      expect(body.user.sellerId).toBeUndefined();
      expect(jwt.decode(body.accessToken)).toMatchObject({ role: 'COMPRADOR' });
      expect(jwt.decode(body.accessToken)).not.toHaveProperty('sellerId');
    });

    it('comprador em rota de lojista recebe 403 SEM_PERMISSAO', async () => {
      const user = await criarComprador();
      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA });

      const res = await request(ctx.servidor)
        .get('/v1/seller/products')
        .set('Authorization', `Bearer ${body.accessToken}`)
        .expect(403);

      expect(res.body.error.code).toBe('SEM_PERMISSAO');
    });

    it('lojista em rota de lojista passa', async () => {
      const user = await criarLojista();
      const { body } = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: SENHA });

      await request(ctx.servidor)
        .get('/v1/seller/products')
        .set('Authorization', `Bearer ${body.accessToken}`)
        .expect(200);
    });
  });

  // ------------------------------------------------ §2.4 erro de login vago

  describe('§2.4 — erro de login deliberadamente vago', () => {
    /**
     * A afirmacao do ADR e sobre *indistinguibilidade*, entao o teste compara
     * as duas respostas entre si em vez de conferir cada uma contra um literal.
     * E o unico jeito de o teste falhar quando alguem acrescentar um detalhe
     * bem-intencionado em so um dos caminhos.
     */
    it('e-mail inexistente e senha errada produzem a mesma resposta', async () => {
      const user = await criarComprador();

      const senhaErrada = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: 'errada_mas_valida' })
        .expect(401);

      const emailInexistente = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: 'ninguem@teste.com', password: SENHA })
        .expect(401);

      expect(senhaErrada.body).toEqual(emailInexistente.body);
      expect(senhaErrada.body.error.code).toBe('CREDENCIAIS_INVALIDAS');
      // A mensagem nao pode citar qual dos dois falhou.
      expect(senhaErrada.body.error.message).not.toMatch(/e-?mail n|nao existe|cadastrad/i);
    });

    it('a resposta de erro nao vaza hash nem dados do usuario', async () => {
      const user = await criarComprador();

      const res = await request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: 'errada' })
        .expect(401);

      expect(JSON.stringify(res.body)).not.toContain('$2b$');
      expect(JSON.stringify(res.body)).not.toContain(user.id);
    });
  });

  // ----------------------------------------------------- register e hash

  describe('§1 — register: bcrypt e o carrinho do comprador', () => {
    it('senha e gravada como hash bcrypt, nunca em claro', async () => {
      const email = 'novo-comprador@teste.com';

      await request(ctx.servidor)
        .post('/v1/auth/register')
        .send({ email, password: SENHA, name: 'Novo', role: 'COMPRADOR' })
        .expect(201);

      const salvo = await prisma.user.findUniqueOrThrow({ where: { email } });
      expect(salvo.passwordHash).not.toBe(SENHA);
      expect(salvo.passwordHash).toMatch(/^\$2[aby]\$10\$/);
    });

    /**
     * Ponte com o ADR 0002 §2.2: "sem usuario nao ha onde pendurar o item".
     * Se o register parar de criar o carrinho, toda rota de /v1/cart passa a
     * ter de tratar carrinho ausente — e e esse tratamento que o ADR 0002
     * decidiu nao escrever.
     */
    it('comprador nasce com carrinho; lojista nasce com loja', async () => {
      await request(ctx.servidor)
        .post('/v1/auth/register')
        .send({ email: 'c@teste.com', password: SENHA, name: 'Comprador', role: 'COMPRADOR' })
        .expect(201);
      await request(ctx.servidor)
        .post('/v1/auth/register')
        .send({
          email: 'l@teste.com',
          password: SENHA,
          name: 'Lojista',
          role: 'LOJISTA',
          storeName: 'Loja Nova',
        })
        .expect(201);

      const comprador = await prisma.user.findUniqueOrThrow({
        where: { email: 'c@teste.com' },
        include: { cart: true, seller: true },
      });
      const lojista = await prisma.user.findUniqueOrThrow({
        where: { email: 'l@teste.com' },
        include: { cart: true, seller: true },
      });

      expect(comprador.cart).not.toBeNull();
      expect(comprador.seller).toBeNull();
      expect(lojista.seller).not.toBeNull();
    });

    it('e-mail repetido responde 409 EMAIL_JA_CADASTRADO', async () => {
      const user = await criarComprador();

      const res = await request(ctx.servidor)
        .post('/v1/auth/register')
        .send({ email: user.email, password: SENHA, name: 'Outro', role: 'COMPRADOR' })
        .expect(409);

      expect(res.body.error.code).toBe('EMAIL_JA_CADASTRADO');
    });
  });
});

/**
 * §6.2 — rate limit no /auth/login.
 *
 * Suite separada porque e a unica que precisa do ThrottlerGuard ligado. O ADR
 * lista isso como questao em aberto ("a resposta generica do §2.4 protege
 * contra enumeracao e nao contra forca bruta"), mas o `@Throttle` do
 * AuthController ja resolveu — este teste e o que transforma "ja resolvida" em
 * garantia de que continua resolvida.
 */
describe('ADR 0003 §6.2 — forca bruta no login', () => {
  let ctx: AppDeTeste;

  beforeAll(async () => {
    ctx = await criarApp({ comThrottle: true });
  });

  afterAll(async () => {
    await ctx.encerrar();
    await prisma.$disconnect();
  });

  beforeEach(limpar);

  it('o sexto login errado no mesmo minuto responde 429', async () => {
    const user = await criarComprador();
    const tentar = () =>
      request(ctx.servidor)
        .post('/v1/auth/login')
        .send({ email: user.email, password: 'errada' });

    const status: number[] = [];
    for (let i = 0; i < 6; i++) {
      status.push((await tentar()).status);
    }

    expect(status.slice(0, 5)).toEqual([401, 401, 401, 401, 401]);
    expect(status[5]).toBe(429);
  });
});
