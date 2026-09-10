import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CacheService } from '../cache/cache.service';
import { SearchProductsDto, SortOption } from './dto/search-products.dto';
import { normalizarTermoBusca } from '../common/texto.util';

// Pesos do score de relevancia. Somados ao ts_rank_cd do texto.
const PESO_POPULARIDADE = 0.3;
const BONUS_EM_ESTOQUE = 0.5;

interface ProductRow {
  id: string;
  title: string;
  price_cents: number;
  image_url: string | null;
  stock: number;
  seller_id: string;
  store_name: string;
  total: bigint;
}

@Injectable()
export class ProductsService {
  private readonly ttlProduto: number;
  private readonly ttlLista: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly cache: CacheService,
    config: ConfigService,
  ) {
    this.ttlProduto = Number(config.get('CACHE_TTL_PRODUCT', '300'));
    this.ttlLista = Number(config.get('CACHE_TTL_LIST', '120'));
  }

  /**
   * Busca no catalogo. Usa $queryRaw porque o Prisma Client nao consulta
   * tsvector: o ranking depende de ts_rank_cd sobre a coluna gerada.
   */
  async search(dto: SearchProductsDto) {
    const { category, minPrice, maxPrice } = dto;
    // Normaliza antes de montar a chave E antes de consultar, para que o valor
    // cacheado corresponda exatamente ao termo que gerou a chave.
    const q = normalizarTermoBusca(dto.q);
    const sort = dto.sort ?? SortOption.RELEVANCE;
    const page = dto.page ?? 1;
    const limit = dto.limit ?? 20;
    const offset = (page - 1) * limit;

    const chave = this.cache.chaveDeLista('products:list', {
      q, category, minPrice, maxPrice, sort, page, limit,
    });

    const emCache = await this.cache.get<Awaited<ReturnType<typeof this.consultarBanco>>>(chave);
    if (emCache) return emCache;

    const resultado = await this.consultarBanco({ q, category, minPrice, maxPrice, sort, page, limit, offset });
    await this.cache.set(chave, resultado, this.ttlLista);
    return resultado;
  }

  private async consultarBanco(p: {
    q?: string; category?: string; minPrice?: number; maxPrice?: number;
    sort: SortOption; page: number; limit: number; offset: number;
  }) {
    const { q, category, minPrice, maxPrice, sort, page, limit, offset } = p;

    const where: Prisma.Sql[] = [Prisma.sql`p.status = 'ACTIVE'`];

    if (q) {
      // f_unaccent nos dois lados: o documento foi indexado sem acento
      // (coluna gerada), entao o termo tambem precisa ser normalizado --
      // senao "tenis" nunca acha "tenis".
      // websearch_to_tsquery aceita a sintaxe que o usuario ja conhece
      // ("aspas", -exclusao) e nunca lanca erro de parse, ao contrario
      // de to_tsquery. Input malformado vira busca vazia, nao 500.
      where.push(Prisma.sql`p.search_vector @@ websearch_to_tsquery('portuguese', f_unaccent(${q}))`);
    }
    if (category) {
      where.push(Prisma.sql`c.slug = ${category}`);
    }
    if (minPrice !== undefined) {
      where.push(Prisma.sql`p.price_cents >= ${minPrice}`);
    }
    if (maxPrice !== undefined) {
      where.push(Prisma.sql`p.price_cents <= ${maxPrice}`);
    }

    const relevancia = q
      ? Prisma.sql`
          ts_rank_cd(p.search_vector, websearch_to_tsquery('portuguese', f_unaccent(${q})))
          + log(1 + p.sales_count) * ${PESO_POPULARIDADE}
          + CASE WHEN p.stock > 0 THEN ${BONUS_EM_ESTOQUE} ELSE 0 END`
      : // Vitrine sem termo: popularidade e recencia.
        Prisma.sql`log(1 + p.sales_count) + CASE WHEN p.stock > 0 THEN ${BONUS_EM_ESTOQUE} ELSE 0 END`;

    const orderBy = {
      [SortOption.RELEVANCE]: Prisma.sql`relevancia DESC, p.created_at DESC`,
      [SortOption.PRICE_ASC]: Prisma.sql`p.price_cents ASC`,
      [SortOption.PRICE_DESC]: Prisma.sql`p.price_cents DESC`,
      [SortOption.NEWEST]: Prisma.sql`p.created_at DESC`,
    }[sort];

    // COUNT(*) OVER() traz o total na mesma ida ao banco, evitando a
    // segunda query so para paginar.
    const rows = await this.prisma.$queryRaw<ProductRow[]>`
      SELECT
        p.id, p.title, p.price_cents, p.image_url, p.stock,
        s.id AS seller_id, s.store_name,
        ${relevancia} AS relevancia,
        COUNT(*) OVER() AS total
      FROM products p
      JOIN sellers s ON s.id = p.seller_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE ${Prisma.join(where, ' AND ')}
      ORDER BY ${orderBy}
      LIMIT ${limit} OFFSET ${offset}
    `;

    const total = rows.length > 0 ? Number(rows[0].total) : 0;

    return {
      data: rows.map((r) => ({
        id: r.id,
        title: r.title,
        priceCents: r.price_cents,
        imageUrl: r.image_url,
        inStock: r.stock > 0,
        seller: { id: r.seller_id, storeName: r.store_name },
      })),
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    };
  }

  async findOne(id: string) {
    const chave = `product:${id}`;
    const emCache = await this.cache.get<Record<string, unknown>>(chave);
    if (emCache) return emCache;

    const product = await this.prisma.product.findFirst({
      where: { id, status: 'ACTIVE' },
      include: {
        seller: { select: { id: true, storeName: true, slug: true } },
        category: { select: { id: true, name: true, slug: true } },
      },
    });

    if (!product) {
      // 404 nao entra no cache: produto pode ser ativado a qualquer momento
      // pelo lojista, e cachear a ausencia atrasaria a publicacao.
      throw new NotFoundException({
        error: { code: 'PRODUTO_NAO_ENCONTRADO', message: `Produto ${id} nao existe ou nao esta ativo.` },
      });
    }

    await this.cache.set(chave, product, this.ttlProduto);
    return product;
  }

  /**
   * Chamado sempre que um produto muda (CRUD do lojista, baixa de estoque
   * no checkout). O detalhe do produto tem invalidacao pontual; as listagens
   * nao -- o hash da query gera chaves demais para rastrear individualmente,
   * entao o TTL curto e o trade-off aceito, ja registrado como risco no README.
   */
  async invalidar(productId: string): Promise<void> {
    await this.cache.del(`product:${productId}`);
    await this.cache.delPorPadrao('products:list:*');
  }
}
