import { Controller, Get } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { PrismaService } from '../prisma/prisma.service';

// Probes do Kubernetes chegam a cada poucos segundos, do IP do node: sem isto
// consumiriam a cota de rate limit e poderiam levar 429.
@SkipThrottle()
@Controller('health')
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Probe de liveness, readiness e startup. Nao consulta nenhuma dependencia
   * de proposito:
   * - liveness checando o Postgres faria o Kubernetes reiniciar todos os pods
   *   em loop durante uma queda do banco, sem consertar nada;
   * - readiness checando o Postgres tiraria todos os pods do Service ao mesmo
   *   tempo, e o catalogo, que sai do cache, deixaria de ser servido.
   * Como o Nest so escuta depois de inicializar, responder ja prova que o pod
   * esta pronto.
   */
  @Get('live')
  live() {
    return { status: 'ok' };
  }

  /** Checagem das dependencias, para diagnostico. Nunca usar como probe. */
  @Get()
  async check() {
    await this.prisma.$queryRaw`SELECT 1`;
    return { status: 'ok', timestamp: new Date().toISOString() };
  }
}
