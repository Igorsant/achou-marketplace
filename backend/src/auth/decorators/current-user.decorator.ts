import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Role } from '@prisma/client';

export interface UsuarioLogado {
  id: string;
  email: string;
  role: Role;
  sellerId?: string;
}

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): UsuarioLogado =>
    ctx.switchToHttp().getRequest().user,
);
