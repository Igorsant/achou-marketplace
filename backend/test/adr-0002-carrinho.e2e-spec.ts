import { existsSync } from 'node:fs';
import { join } from 'node:path';
import request from 'supertest';
import { criarApp, tokenDe, AppDeTeste } from './apoio/app';
import { limpar, prisma, criarComprador, criarLojista, criarProduto } from './apoio/banco';

/**
 * ADR 0002 — carrinho: estado no servidor, sem preco congelado, split por
 * lojista no commit.
 *
 * `/v1/cart` **nao existe de proposito**: o ADR 0002 §7 registra a Feature 2
 * como escopo diferido. A parte da decisao que mais custa reverter — as
 * constraints do §2.2 — ja esta no schema e e verificada pelo
 * `scripts/adr-check.sh`. O que falta e o servico, e o contrato dele e este
 * arquivo.
 *
 * Os casos ficam pendentes em vez de vermelhos enquanto o modulo nao existe:
 * pipeline permanentemente vermelho para de ser lido, e ai nao serve para nada.
 *
 * A guarda e a existencia do modulo, decidida em tempo de coleta do Jest: ele
 * precisa saber se registra ou pula *antes* de subir o app.
 */
const implementado = existsSync(join(__dirname, '..', 'src', 'cart'));
const descreve = implementado ? describe : describe.skip;

if (!implementado) {
  console.log(
    '\n  ADR 0002 §7: escopo diferido do MVP. src/cart/ nao existe ainda.\n' +
      '  O contrato do carrinho esta escrito aqui e roda sozinho quando o modulo nascer.\n',
  );
}

descreve('ADR 0002 — carrinho no servidor', () => {
  let ctx: AppDeTeste;

  beforeAll(async () => {
    ctx = await criarApp();
  });

  afterAll(async () => {
    await ctx.encerrar();
    await prisma.$disconnect();
  });

  beforeEach(limpar);

  async function cenario() {
    const comprador = await criarComprador();
    const lojista = await criarLojista();
    const produto = await criarProduto(lojista.seller!.id, { priceCents: 10_000, stock: 10 });
    return { comprador, lojista, produto, token: await tokenDe(ctx, comprador.email) };
  }

  const comAuth = (token: string) => ({ Authorization: `Bearer ${token}` });

  // ------------------------------------------------------- §2.2 exige login

  describe('§2.2 — carrinho exige comprador autenticado', () => {
    it('sem token, 401', async () => {
      await request(ctx.servidor).get('/v1/cart').expect(401);
    });

    it('lojista nao tem carrinho: 403', async () => {
      const lojista = await criarLojista();
      const token = await tokenDe(ctx, lojista.email);

      await request(ctx.servidor).get('/v1/cart').set(comAuth(token)).expect(403);
    });

    it('o carrinho de um comprador nao aparece para outro', async () => {
      const { produto, token } = await cenario();
      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 1 });

      const outro = await criarComprador();
      const res = await request(ctx.servidor)
        .get('/v1/cart')
        .set(comAuth(await tokenDe(ctx, outro.email)))
        .expect(200);

      expect(res.body.items).toHaveLength(0);
    });
  });

  // -------------------------------- §2.2 sem preco congelado, sem reserva

  describe('§2.2 — o carrinho nao congela preco nem reserva estoque', () => {
    /**
     * O teste comportamental da decisao de nao ter coluna de preco: mudar o
     * preco do produto tem de aparecer no carrinho ja existente. Se um dia
     * alguem "otimizar" guardando o preco na linha do carrinho, e aqui que
     * quebra — o schema sozinho nao pega uma copia feita no servico.
     */
    it('mudanca de preco aparece no carrinho ja montado', async () => {
      const { produto, token } = await cenario();
      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 2 })
        .expect(201);

      await prisma.product.update({
        where: { id: produto.id },
        data: { priceCents: 15_000 },
      });

      const res = await request(ctx.servidor).get('/v1/cart').set(comAuth(token)).expect(200);
      expect(res.body.items[0].unitPriceCents).toBe(15_000);
    });

    it('adicionar ao carrinho nao mexe no estoque do produto', async () => {
      const { produto, token } = await cenario();

      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 5 })
        .expect(201);

      const depois = await prisma.product.findUniqueOrThrow({ where: { id: produto.id } });
      expect(depois.stock).toBe(10);
    });

    it('nao existe linha de carrinho com preco: o cliente nao propoe valor', async () => {
      const { produto, token } = await cenario();

      // `forbidNonWhitelisted` no ValidationPipe: campo a mais e 400, nao
      // campo ignorado em silencio. E o que fecha o vetor do §2.1: o corpo da
      // requisicao nao carrega valor nenhum.
      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 1, priceCents: 1 })
        .expect(400);
    });

    it('mesmo produto duas vezes soma a quantidade em uma linha so', async () => {
      const { produto, token } = await cenario();
      const add = (quantity: number) =>
        request(ctx.servidor)
          .post('/v1/cart/items')
          .set(comAuth(token))
          .send({ productId: produto.id, quantity });

      await add(1);
      await add(2);

      const res = await request(ctx.servidor).get('/v1/cart').set(comAuth(token)).expect(200);
      expect(res.body.items).toHaveLength(1);
      expect(res.body.items[0].quantity).toBe(3);
    });

    /**
     * §4 (riscos): "GET /cart marca o item como indisponivel em vez de deletar
     * em silencio — sumico sem aviso e pior que erro visivel".
     */
    it('produto arquivado fica marcado como indisponivel, nao desaparece', async () => {
      const { produto, token } = await cenario();
      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 1 });

      await prisma.product.update({
        where: { id: produto.id },
        data: { status: 'ARCHIVED' },
      });

      const res = await request(ctx.servidor).get('/v1/cart').set(comAuth(token)).expect(200);
      expect(res.body.items).toHaveLength(1);
      expect(res.body.items[0].available).toBe(false);
    });
  });

  // --------------------------------------------- §2.1 servidor e a verdade

  describe('§2.1 — o estado mora no servidor', () => {
    it('o item persiste no banco, nao na memoria do app', async () => {
      const { comprador, produto, token } = await cenario();

      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 2 })
        .expect(201);

      const linhas = await prisma.cartItem.findMany({
        where: { cart: { userId: comprador.id } },
      });
      expect(linhas).toHaveLength(1);
      expect(linhas[0].quantity).toBe(2);
    });

    it('PATCH altera a quantidade e DELETE remove o item', async () => {
      const { produto, token } = await cenario();
      const criado = await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 1 });

      const itemId = criado.body.items?.[0]?.id ?? criado.body.id;

      await request(ctx.servidor)
        .patch(`/v1/cart/items/${itemId}`)
        .set(comAuth(token))
        .send({ quantity: 4 })
        .expect(200);

      let res = await request(ctx.servidor).get('/v1/cart').set(comAuth(token));
      expect(res.body.items[0].quantity).toBe(4);

      await request(ctx.servidor)
        .delete(`/v1/cart/items/${itemId}`)
        .set(comAuth(token))
        .expect(200);

      res = await request(ctx.servidor).get('/v1/cart').set(comAuth(token));
      expect(res.body.items).toHaveLength(0);
    });
  });

  // ------------------------------------------------------ §2.3 multi-lojista

  describe('§2.3 — um carrinho aceita varios lojistas', () => {
    it('produtos de duas lojas convivem na mesma sacola', async () => {
      const { produto, token } = await cenario();
      const outroLojista = await criarLojista();
      const outroProduto = await criarProduto(outroLojista.seller!.id);

      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: produto.id, quantity: 1 })
        .expect(201);
      await request(ctx.servidor)
        .post('/v1/cart/items')
        .set(comAuth(token))
        .send({ productId: outroProduto.id, quantity: 1 })
        .expect(201);

      const res = await request(ctx.servidor).get('/v1/cart').set(comAuth(token)).expect(200);
      expect(res.body.items).toHaveLength(2);
    });
  });
});
