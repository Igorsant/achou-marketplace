import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { UsuarioLogado } from './decorators/current-user.decorator';

export interface JwtPayload {
  sub: string;
  email: string;
  role: UsuarioLogado['role'];
  sellerId?: string;
  type?: 'access' | 'refresh';
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_SECRET') ?? 'dev_secret',
    });
  }

  validate(payload: JwtPayload): UsuarioLogado {
    // Refresh token nao autentica requisicao: so serve em /auth/refresh.
    // Sem esta checagem, um refresh token valeria como access token.
    if (payload.type === 'refresh') {
      throw new UnauthorizedException({
        error: { code: 'TOKEN_INVALIDO', message: 'Use o access token para autenticar.' },
      });
    }
    return { id: payload.sub, email: payload.email, role: payload.role, sellerId: payload.sellerId };
  }
}
