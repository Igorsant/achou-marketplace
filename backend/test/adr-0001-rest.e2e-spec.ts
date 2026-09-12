import request from 'supertest';
import { criarApp, tokenDe, AppDeTeste } from './apoio/app';
import { limpar, prisma, criarComprador, criarLojista, criarProduto } from './apoio/banco';

/**
 * ADR 0001 — interface HTTP: REST sobre recursos, versionada no path.
 *
 * Esta decisao e anterior a qualquer feature e esta inteiramente implementada,
 * entao a suite roda de verdade — nao ha nada diferido aqui.
 *
 * O que se verifica nao e "a rota funciona", e sim que ela funciona **do jeito
 * que o estilo exige**: resultado no status e nao no corpo, envelope de erro
 * unico com `code` estavel, prefixo de versao, e separacao de audiencia por
 * caminho. Sao exatamente as propriedades que um gateway ou uma CDN usam sem
 * abrir o corpo da mensagem (§2.1).
 */
describe('ADR 0001 — REST sobre recursos, versionada no path', () => {
  let ctx: AppDeTeste;

  beforeAll(async () => {
    ctx = await criarApp();
  });

  afterAll(async () => {
    await ctx.encerrar();
    await prisma.$disconnect();
  });

  beforeEach(limpar);

  const comAuth = (token: string) => ({ Authorization: `Bearer ${token}` });
  const uuidInexistente = '00000000-0000-0000-0000-000000000000';

  // --------------------------------------------------- §2.2 versao no path

  describe('§2.2 — versão no path', () => {
    it('o contrato do cliente vive sob /v1', async () => {
      await request(ctx.servidor).get('/v1/products').expect(200);
    });

    it('a mesma rota sem o prefixo de versão não existe', async () => {
      await request(ctx.servidor).get('/products').expect(404);
    });

    /**
     * `/health` fica fora de `/v1` de proposito: e sonda de infraestrutura, nao
     * parte do contrato versionado. O teste fixa isso para que ninguem
     * "corrija" movendo a rota para dentro da versao — os manifestos do
     * Kubernetes apontam para ela.
     */
    it('/health fica fora da versão, por ser sonda de infraestrutura', async () => {
      const res = await request(ctx.servidor).get('/health').expect(200);
      expect(res.body.status).toBe('ok');
      await request(ctx.servidor).get('/v1/health').expect(404);
    });
  });

  // ------------------------------------- §2.3 status como canal de resultado

  describe('§2.3 — o resultado vai no status, não no corpo', () => {
    /**
     * A afirmacao central do §2.3: nenhuma resposta de sucesso carrega um campo
     * dizendo que falhou. Se um dia alguem devolver `200 { success: false }`, e
     * aqui que quebra — e o motivo esta no ADR: retry, alerta e cache negativo
     * passam a depender de interpretar o corpo.
     */
    it('resposta de sucesso não carrega campo de sucesso/erro', async () => {
      const res = await request(ctx.servidor).get('/v1/products').expect(200);

      expect(res.body).not.toHaveProperty('success');
      expect(res.body).not.toHaveProperty('ok');
      expect(res.body).not.toHaveProperty('error');
    });

    it('criar recurso responde 201; ler responde 200', async () => {
      const lojista = await criarLojista();
      const token = await tokenDe(ctx, lojista.email);

      await request(ctx.servidor)
        .post('/v1/seller/products')
        .set(comAuth(token))
        .send({ title: 'Produto REST', priceCents: 1000, stock: 5 })
        .expect(201);

      await request(ctx.servidor).get('/v1/seller/products').set(comAuth(token)).expect(200);
    });

    /**
     * Cada classe de erro no seu status. O 401/403 vem do ADR 0003, mas a
     * *distincao* entre eles e decisao deste ADR: "nao sei quem voce e" e "sei
     * quem voce e e voce nao pode" sao respostas diferentes porque o cliente
     * reage diferente — uma renova o token, a outra nao.
     */
    it('cada classe de erro tem seu status', async () => {
      const comprador = await criarComprador();
      const token = await tokenDe(ctx, comprador.email);

      // 400 — payload malformado
      await request(ctx.servidor)
        .post('/v1/auth/register')
        .send({ email: 'nao-e-email', password: 'x', name: 'A', role: 'COMPRADOR' })
        .expect(400);

      // 401 — sem credencial
      await request(ctx.servidor).get('/v1/seller/products').expect(401);

      // 403 — credencial válida, papel errado
      await request(ctx.servidor)
        .get('/v1/seller/products')
        .set(comAuth(token))
        .expect(403);

      // 404 — recurso inexistente
      await request(ctx.servidor).get(`/v1/products/${uuidInexistente}`).expect(404);
    });

    it('id com formato inválido é 400, não 404 nem 500', async () => {
      await request(ctx.servidor).get('/v1/products/nao-e-uuid').expect(400);
    });

    /**
     * §2.1: `GET` e seguro e repetivel por definicao do metodo. Repetir uma
     * leitura nao pode mudar nada — e o que autoriza o retry automatico do app
     * e o cache da borda.
     */
    it('GET é seguro: repetir a leitura não muda o recurso', async () => {
      const lojista = await criarLojista();
      const produto = await criarProduto(lojista.seller!.id, { stock: 7 });

      await request(ctx.servidor).get(`/v1/products/${produto.id}`).expect(200);
      await request(ctx.servidor).get(`/v1/products/${produto.id}`).expect(200);

      const depois = await prisma.product.findUniqueOrThrow({ where: { id: produto.id } });
      expect(depois.stock).toBe(7);
    });
  });

  // ------------------------------------------------ §2.4 envelope de erro

  describe('§2.4 — envelope de erro único com code estável', () => {
    /**
     * Todo erro, de qualquer origem — guard, pipe de validacao, service —
     * chega ao cliente na mesma forma. Sem o filtro global, o ValidationPipe
     * responderia no formato do Nest e o app precisaria de dois parsers.
     */
    it('erros de origens diferentes têm a mesma forma', async () => {
      const comprador = await criarComprador();
      const token = await tokenDe(ctx, comprador.email);

      const respostas = await Promise.all([
        // do ValidationPipe
        request(ctx.servidor).post('/v1/auth/login').send({ email: 'x', password: '' }),
        // do guard
        request(ctx.servidor).get('/v1/seller/products').set(comAuth(token)),
        // do service
        request(ctx.servidor).get(`/v1/products/${uuidInexistente}`),
      ]);

      for (const res of respostas) {
        expect(res.body).toHaveProperty('error.code');
        expect(res.body).toHaveProperty('error.message');
        expect(typeof res.body.error.code).toBe('string');
        expect(typeof res.body.error.message).toBe('string');
      }
    });

    /**
     * O app decide comportamento pelo `code`, nunca pelo `message`. Para isso o
     * `code` precisa ser um identificador, nao uma frase: SCREAMING_SNAKE_CASE,
     * sem espaco nem acento.
     */
    it('code é identificador estável, não frase de tela', async () => {
      const respostas = await Promise.all([
        request(ctx.servidor).post('/v1/auth/login').send({ email: 'x', password: '' }),
        request(ctx.servidor).get('/v1/seller/products'),
        request(ctx.servidor).get(`/v1/products/${uuidInexistente}`),
      ]);

      for (const res of respostas) {
        expect(res.body.error.code).toMatch(/^[A-Z][A-Z0-9_]*$/);
      }
    });

    it('erro de validação diz quais campos falharam em details', async () => {
      const res = await request(ctx.servidor)
        .post('/v1/auth/register')
        .send({ email: 'nao-e-email', password: 'curta', name: 'A', role: 'COMPRADOR' })
        .expect(400);

      expect(res.body.error.code).toBe('VALIDACAO_FALHOU');
      expect(Array.isArray(res.body.error.details)).toBe(true);
      expect(res.body.error.details.length).toBeGreaterThan(0);
    });

    it('campo não previsto é recusado, não ignorado em silêncio', async () => {
      const res = await request(ctx.servidor)
        .post('/v1/auth/register')
        .send({
          email: 'a@teste.com',
          password: 'senha123',
          name: 'Alguem',
          role: 'COMPRADOR',
          campoQueNaoExiste: 'valor',
        })
        .expect(400);

      expect(res.body.error.code).toBe('VALIDACAO_FALHOU');
    });
  });

  // ------------------------------------- §2.6 separação por audiência

  describe('§2.6 — público e privado separados por prefixo', () => {
    /**
     * A separacao esta no *caminho*, nao em um campo do corpo. E isso que
     * permite exprimir a regra de cache e a de autorizacao como prefixo de URL
     * — o vocabulario do gateway e da CDN.
     */
    it('/v1/products é público; /v1/seller/* exige LOJISTA', async () => {
      const lojista = await criarLojista();
      await criarProduto(lojista.seller!.id);

      await request(ctx.servidor).get('/v1/products').expect(200);
      await request(ctx.servidor).get('/v1/seller/products').expect(401);

      const token = await tokenDe(ctx, lojista.email);
      await request(ctx.servidor).get('/v1/seller/products').set(comAuth(token)).expect(200);
    });

    it('a rota pública não vaza dado que só o painel do lojista devolve', async () => {
      const lojista = await criarLojista();
      await criarProduto(lojista.seller!.id, { stock: 3 });

      const publico = await request(ctx.servidor).get('/v1/products').expect(200);

      // `stock` exato é dado do painel; a vitrine pública responde
      // disponibilidade, não quantidade (api-design §2.2).
      const itens = publico.body.data ?? publico.body.items ?? publico.body;
      expect(JSON.stringify(itens)).not.toMatch(/"stock"\s*:\s*3/);
    });
  });

  // --------------------------------------- §2.1 recurso no path, ação no verbo

  describe('§2.1 — o recurso está no path, a ação no método', () => {
    /**
     * O mesmo caminho responde a metodos diferentes com significados
     * diferentes. E a propriedade que distingue REST de RPC sobre HTTP, onde
     * cada acao teria seu proprio caminho e tudo seria POST.
     */
    it('o mesmo caminho muda de significado conforme o método', async () => {
      const lojista = await criarLojista();
      const token = await tokenDe(ctx, lojista.email);

      const criado = await request(ctx.servidor)
        .post('/v1/seller/products')
        .set(comAuth(token))
        .send({ title: 'Produto', priceCents: 5000, stock: 2 })
        .expect(201);

      const caminho = `/v1/seller/products/${criado.body.id}`;

      await request(ctx.servidor)
        .patch(caminho)
        .set(comAuth(token))
        .send({ priceCents: 7000 })
        .expect(200);

      await request(ctx.servidor).delete(caminho).set(comAuth(token)).expect(200);
    });

    it('método não suportado no caminho responde 404, não 500', async () => {
      await request(ctx.servidor).delete('/v1/products').expect(404);
    });
  });
});
