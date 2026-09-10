import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService, JwtSignOptions } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { JwtPayload } from './jwt.strategy';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async register(dto: RegisterDto) {
    const existe = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existe) {
      throw new ConflictException({
        error: { code: 'EMAIL_JA_CADASTRADO', message: 'Ja existe uma conta com este e-mail.' },
      });
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    const user = await this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        name: dto.name,
        role: dto.role,
        // Lojista ganha loja; comprador ganha carrinho. Criar aqui evita
        // ter que tratar "carrinho ausente" em toda rota de carrinho.
        ...(dto.role === Role.LOJISTA
          ? { seller: { create: { storeName: dto.storeName!, slug: await this.gerarSlug(dto.storeName!) } } }
          : { cart: { create: {} } }),
      },
      include: { seller: true },
    });

    return this.montarResposta(user.id, user.email, user.role, user.name, user.seller?.id);
  }

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findUnique({
      where: { email: dto.email },
      include: { seller: true },
    });

    // Mesma mensagem para e-mail inexistente e senha errada: revelar qual
    // dos dois falhou permite enumerar contas cadastradas.
    const senhaOk = user && (await bcrypt.compare(dto.password, user.passwordHash));
    if (!senhaOk) {
      throw new UnauthorizedException({
        error: { code: 'CREDENCIAIS_INVALIDAS', message: 'E-mail ou senha incorretos.' },
      });
    }

    return this.montarResposta(user.id, user.email, user.role, user.name, user.seller?.id);
  }

  async refresh(refreshToken: string) {
    let payload: JwtPayload;
    try {
      payload = this.jwt.verify<JwtPayload>(refreshToken, {
        secret: this.config.get<string>('JWT_SECRET'),
      });
    } catch {
      throw new UnauthorizedException({
        error: { code: 'REFRESH_INVALIDO', message: 'Refresh token expirado ou invalido.' },
      });
    }

    if (payload.type !== 'refresh') {
      throw new UnauthorizedException({
        error: { code: 'REFRESH_INVALIDO', message: 'O token enviado nao e um refresh token.' },
      });
    }

    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      include: { seller: true },
    });
    if (!user) {
      throw new UnauthorizedException({
        error: { code: 'REFRESH_INVALIDO', message: 'Usuario nao existe mais.' },
      });
    }

    return this.montarResposta(user.id, user.email, user.role, user.name, user.seller?.id);
  }

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true, email: true, name: true, role: true, createdAt: true,
        seller: { select: { id: true, storeName: true, slug: true } },
      },
    });
    return user;
  }

  private montarResposta(id: string, email: string, role: Role, name: string, sellerId?: string) {
    const base = { sub: id, email, role, ...(sellerId ? { sellerId } : {}) };
    return {
      user: { id, email, name, role, ...(sellerId ? { sellerId } : {}) },
      accessToken: this.jwt.sign(
        { ...base, type: 'access' },
        this.expiraEm('JWT_ACCESS_EXPIRES', '15m'),
      ),
      refreshToken: this.jwt.sign(
        { ...base, type: 'refresh' },
        this.expiraEm('JWT_REFRESH_EXPIRES', '7d'),
      ),
    };
  }

  /**
   * O tipo de `expiresIn` no @nestjs/jwt e um literal do pacote `ms`
   * ("15m", "7d"...), incompativel com a `string` que o ConfigService devolve.
   * A conversao fica isolada aqui em vez de espalhada nas chamadas.
   */
  private expiraEm(chave: string, padrao: string): JwtSignOptions {
    return { expiresIn: this.config.get<string>(chave, padrao) } as JwtSignOptions;
  }

  /** Slug unico a partir do nome da loja: "Corrida Já!" -> "corrida-ja". */
  private async gerarSlug(storeName: string): Promise<string> {
    const base = storeName
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '') || 'loja';

    let slug = base;
    let n = 1;
    while (await this.prisma.seller.findUnique({ where: { slug } })) {
      slug = `${base}-${++n}`;
    }
    return slug;
  }
}
