import { Module } from '@nestjs/common';
import { SellerProductsController } from './seller-products.controller';
import { SellerProductsService } from './seller-products.service';
import { ProductsModule } from '../products/products.module';

@Module({
  imports: [ProductsModule],
  controllers: [SellerProductsController],
  providers: [SellerProductsService],
})
export class SellerModule {}
