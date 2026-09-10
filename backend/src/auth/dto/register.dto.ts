import { Role } from '@prisma/client';
import { IsEmail, IsEnum, IsOptional, IsString, MinLength, ValidateIf } from 'class-validator';

export class RegisterDto {
  @IsEmail({}, { message: 'email deve ser um endereco valido' })
  email: string;

  @IsString() @MinLength(8, { message: 'password precisa de ao menos 8 caracteres' })
  password: string;

  @IsString() @MinLength(2)
  name: string;

  @IsEnum(Role, { message: 'role deve ser COMPRADOR ou LOJISTA' })
  role: Role;

  // Obrigatorio so para lojista: e o nome que aparece na vitrine.
  @ValidateIf((o) => o.role === Role.LOJISTA)
  @IsString() @MinLength(2, { message: 'storeName e obrigatorio para LOJISTA' })
  storeName?: string;
}
