import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Role } from '@prisma/client';
import { ROLES_KEY } from '../decorators/roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const exigidos = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (!exigidos || exigidos.length === 0) return true;

    const { user } = ctx.switchToHttp().getRequest();
    if (!user || !exigidos.includes(user.role)) {
      throw new ForbiddenException({
        error: {
          code: 'SEM_PERMISSAO',
          message: `Esta rota exige o perfil ${exigidos.join(' ou ')}.`,
        },
      });
    }
    return true;
  }
}
