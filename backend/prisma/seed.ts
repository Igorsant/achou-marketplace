import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  const senha = await bcrypt.hash('senha123', 10);

  const categorias = await Promise.all(
    [
      { name: 'Calçados', slug: 'calcados' },
      { name: 'Vestuário', slug: 'vestuario' },
      { name: 'Acessórios', slug: 'acessorios' },
    ].map((c) => prisma.category.upsert({ where: { slug: c.slug }, update: {}, create: c })),
  );

  const lojista = await prisma.user.upsert({
    where: { email: 'lojista@achou.com' },
    update: {},
    create: {
      email: 'lojista@achou.com',
      passwordHash: senha,
      name: 'Corrida Já',
      role: 'LOJISTA',
      seller: { create: { storeName: 'Corrida Já', slug: 'corrida-ja' } },
    },
    include: { seller: true },
  });

  await prisma.user.upsert({
    where: { email: 'comprador@achou.com' },
    update: {},
    create: {
      email: 'comprador@achou.com',
      passwordHash: senha,
      name: 'Ana Compradora',
      role: 'COMPRADOR',
      cart: { create: {} },
    },
  });

  const sellerId = lojista.seller!.id;
  const produtos = [
    { title: 'Tênis Runner Pro 42', description: 'Tênis de corrida com solado em EVA e amortecimento', priceCents: 24990, stock: 15, salesCount: 120, categoryId: categorias[0].id },
    { title: 'Tênis Trail X', description: 'Tênis para trilha, solado agressivo', priceCents: 31990, stock: 8, salesCount: 45, categoryId: categorias[0].id },
    { title: 'Meia esportiva cano médio', description: 'Meia para corrida com compressão leve', priceCents: 2990, stock: 50, salesCount: 300, categoryId: categorias[1].id },
    { title: 'Camiseta Dry Fit', description: 'Camiseta leve para treino e corrida', priceCents: 7990, stock: 0, salesCount: 80, categoryId: categorias[1].id },
    { title: 'Garrafa térmica 500ml', description: 'Garrafa para hidratação durante o treino', priceCents: 4990, stock: 30, salesCount: 15, categoryId: categorias[2].id },
  ];

  for (const p of produtos) {
    const existe = await prisma.product.findFirst({ where: { title: p.title, sellerId } });
    if (!existe) await prisma.product.create({ data: { ...p, sellerId } });
  }

  const total = await prisma.product.count();
  console.log(`seed concluido: ${total} produtos, 2 usuarios, ${categorias.length} categorias`);
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
