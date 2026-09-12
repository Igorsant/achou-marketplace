import { PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

/**
 * Banco dos testes de integracao.
 *
 * Os testes truncam tabelas entre casos. Rodar isso contra o banco de
 * desenvolvimento apagaria o seed — e o `psql` de quem estiver com o Postman
 * aberto ao lado nao avisaria nada. Por isso a guarda: o nome do banco tem de
 * terminar em `_test`. Sem isso, o modulo se recusa a carregar.
 */
function urlDoTeste(): string {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error(
      'DATABASE_URL nao definida. Use scripts/test-e2e.sh, que aponta para o banco de teste.',
    );
  }

  const nome = new URL(url).pathname.replace(/^\//, '');
  if (!nome.endsWith('_test')) {
    throw new Error(
      `Recusando rodar: o banco "${nome}" nao termina em _test.\n` +
        'Os testes truncam tabelas — aponte DATABASE_URL para um banco descartavel.',
    );
  }
  return url;
}

export const prisma = new PrismaClient({ datasources: { db: { url: urlDoTeste() } } });

/**
 * Limpa tudo entre casos. As tabelas vem do catalogo em vez de uma lista fixa:
 * tabela nova entra no TRUNCATE sem ninguem lembrar de atualizar este arquivo,
 * e o CASCADE resolve a ordem das FKs.
 */
export async function limpar(): Promise<void> {
  const tabelas = await prisma.$queryRaw<{ tablename: string }[]>`
    SELECT tablename FROM pg_tables
     WHERE schemaname = 'public' AND tablename <> '_prisma_migrations'
  `;
  if (tabelas.length === 0) return;
  const lista = tabelas.map((t) => `"public"."${t.tablename}"`).join(', ');
  await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${lista} RESTART IDENTITY CASCADE`);
}

// --------------------------------------------------------------- fabricas

let seq = 0;
const unico = (prefixo: string) => `${prefixo}-${Date.now()}-${++seq}`;

export const SENHA = 'senha123';

// Um hash por processo de teste em vez de um por usuario criado: o cost 10 do
// AuthService custa ~60ms e as fabricas rodam em todo caso de teste.
const HASH = bcrypt.hashSync(SENHA, 10);

/** Comprador com carrinho, como o AuthService.register faz. */
export async function criarComprador(email = `${unico('comprador')}@teste.com`) {
  return prisma.user.create({
    data: {
      email,
      name: 'Comprador de Teste',
      role: Role.COMPRADOR,
      passwordHash: HASH,
      cart: { create: {} },
    },
    include: { cart: true },
  });
}

export async function criarLojista(email = `${unico('lojista')}@teste.com`) {
  return prisma.user.create({
    data: {
      email,
      name: 'Lojista de Teste',
      role: Role.LOJISTA,
      passwordHash: HASH,
      seller: { create: { storeName: 'Loja de Teste', slug: unico('loja') } },
    },
    include: { seller: true },
  });
}

export async function criarProduto(
  sellerId: string,
  dados: { priceCents?: number; stock?: number; title?: string } = {},
) {
  return prisma.product.create({
    data: {
      sellerId,
      title: dados.title ?? 'Produto de Teste',
      priceCents: dados.priceCents ?? 10_000,
      stock: dados.stock ?? 10,
    },
  });
}
