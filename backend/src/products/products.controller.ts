import { Controller, Get, Param, ParseUUIDPipe, Query } from '@nestjs/common';
import { ProductsService } from './products.service';
import { SearchProductsDto } from './dto/search-products.dto';

@Controller('v1/products')
export class ProductsController {
  constructor(private readonly products: ProductsService) {}

  @Get()
  search(@Query() query: SearchProductsDto) {
    return this.products.search(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.products.findOne(id);
  }
}
