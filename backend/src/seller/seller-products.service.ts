import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, ProductStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';

@Injectable()
export class SellerProductsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly products: ProductsService,
  ) {}

  /** Lista os produtos da propria loja, incluindo inativos e arquivados. */
  async listar(sellerId: string) {
    return this.prisma.product.findMany({
      where: { sellerId },
      orderBy: { createdAt: 'desc' },
      include: { category: { select: { id: true, name: true, slug: true } } },
    });
  }

  async criar(sellerId: string, dto: CreateProductDto) {
    if (dto.categoryId) await this.exigirCategoria(dto.categoryId);

    const produto = await this.prisma.product.create({
      data: { ...dto, sellerId },
    });

    // Produto novo muda a vitrine: as listagens em cache ficam desatualizadas.
    await this.products.invalidar(produto.id);
    return produto;
  }

  async atualizar(sellerId: string, id: string, dto: UpdateProductDto) {
    await this.exigirPosse(sellerId, id);
    if (dto.categoryId) await this.exigirCategoria(dto.categoryId);

    const produto = await this.prisma.product.update({ where: { id }, data: dto });
    await this.products.invalidar(id);
    return produto;
  }

  async ajustarEstoque(sellerId: string, id: string, stock: number) {
    await this.exigirPosse(sellerId, id);
    const produto = await this.prisma.product.update({ where: { id }, data: { stock } });
    await this.products.invalidar(id);
    return produto;
  }

  /**
   * Soft delete. Produto nunca e removido de verdade porque order_items
   * referencia o id: apagar quebraria o historico de pedidos.
   */
  async arquivar(sellerId: string, id: string) {
    await this.exigirPosse(sellerId, id);
    const produto = await this.prisma.product.update({
      where: { id },
      data: { status: ProductStatus.ARCHIVED },
    });
    await this.products.invalidar(id);
    return produto;
  }

  async pedidosRecebidos(sellerId: string) {
    const itens = await this.prisma.orderItem.findMany({
      where: { sellerId },
      orderBy: { order: { createdAt: 'desc' } },
      include: {
        order: {
          select: {
            id: true, status: true, createdAt: true,
            buyer: { select: { id: true, name: true } },
          },
        },
      },
    });

    // Agrupa por pedido: a loja ve o pedido inteiro, mas so os itens dela.
    const porPedido = new Map<string, any>();
    for (const item of itens) {
      const atual = porPedido.get(item.orderId) ?? {
        orderId: item.orderId,
        status: item.order.status,
        createdAt: item.order.createdAt,
        buyer: item.order.buyer,
        items: [],
        subtotalCents: 0,
      };
      atual.items.push({
        productId: item.productId,
        title: item.titleSnapshot,
        quantity: item.quantity,
        unitPriceCents: item.unitPriceCents,
      });
      atual.subtotalCents += item.unitPriceCents * item.quantity;
      porPedido.set(item.orderId, atual);
    }
    return [...porPedido.values()];
  }

  /**
   * Posse antes de qualquer escrita. Sem isso, um lojista autenticado
   * poderia alterar produto de outra loja so trocando o id na URL.
   * Responde 404 (nao 403) para nao revelar que o produto existe.
   */
  private async exigirPosse(sellerId: string, productId: string) {
    const produto = await this.prisma.product.findUnique({
      where: { id: productId },
      select: { sellerId: true },
    });
    if (!produto || produto.sellerId !== sellerId) {
      throw new NotFoundException({
        error: { code: 'PRODUTO_NAO_ENCONTRADO', message: `Produto ${productId} nao pertence a esta loja.` },
      });
    }
  }

  private async exigirCategoria(categoryId: string) {
    const existe = await this.prisma.category.findUnique({ where: { id: categoryId } });
    if (!existe) {
      throw new NotFoundException({
        error: { code: 'CATEGORIA_NAO_ENCONTRADA', message: `Categoria ${categoryId} nao existe.` },
      });
    }
  }
}
