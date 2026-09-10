import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, IsUUID, IsUrl, Min, MaxLength, MinLength } from 'class-validator';

export class CreateProductDto {
  @IsString() @MinLength(3) @MaxLength(200)
  title: string;

  @IsOptional() @IsString() @MaxLength(2000)
  description?: string;

  // Centavos, sempre inteiro. Float em dinheiro acumula erro de arredondamento.
  @Type(() => Number) @IsInt({ message: 'priceCents deve ser inteiro (centavos)' }) @Min(1)
  priceCents: number;

  @Type(() => Number) @IsInt() @Min(0)
  stock: number;

  @IsOptional() @IsUUID()
  categoryId?: string;

  @IsOptional() @IsUrl({}, { message: 'imageUrl deve ser uma URL valida' })
  imageUrl?: string;
}
