import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { Role } from '@prisma/client';
import { SellerProductsService } from './seller-products.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { UpdateStockDto } from './dto/update-stock.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser, UsuarioLogado } from '../auth/decorators/current-user.decorator';

@Controller('v1/seller')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.LOJISTA)
export class SellerProductsController {
  constructor(private readonly seller: SellerProductsService) {}

  @Get('products')
  listar(@CurrentUser() user: UsuarioLogado) {
    return this.seller.listar(user.sellerId!);
  }

  @Post('products')
  criar(@CurrentUser() user: UsuarioLogado, @Body() dto: CreateProductDto) {
    return this.seller.criar(user.sellerId!, dto);
  }

  @Patch('products/:id')
  atualizar(
    @CurrentUser() user: UsuarioLogado,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateProductDto,
  ) {
    return this.seller.atualizar(user.sellerId!, id, dto);
  }

  @Patch('products/:id/stock')
  ajustarEstoque(
    @CurrentUser() user: UsuarioLogado,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateStockDto,
  ) {
    return this.seller.ajustarEstoque(user.sellerId!, id, dto.stock);
  }

  @Delete('products/:id')
  arquivar(@CurrentUser() user: UsuarioLogado, @Param('id', ParseUUIDPipe) id: string) {
    return this.seller.arquivar(user.sellerId!, id);
  }

  @Get('orders')
  pedidos(@CurrentUser() user: UsuarioLogado) {
    return this.seller.pedidosRecebidos(user.sellerId!);
  }
}
