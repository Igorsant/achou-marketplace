import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'node:crypto';
import Redis from 'ioredis';

@Injectable()
export class CacheService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(CacheService.name);
  private client: Redis;
  private disponivel = false;

  constructor(private readonly config: ConfigService) {}

  onModuleInit() {
    this.client = new Redis({
      host: this.config.get<string>('REDIS_HOST', 'localhost'),
      port: Number(this.config.get<string>('REDIS_PORT', '6379')),
      // Sem retry infinito: se o Redis nao volta, a API segue no Postgres.
      maxRetriesPerRequest: 2,
      lazyConnect: false,
      retryStrategy: (tentativas) => Math.min(tentativas * 200, 3000),
    });

    this.client.on('ready', () => {
      this.disponivel = true;
      this.logger.log('Redis conectado');
    });

    this.client.on('error', (err) => {
      if (this.disponivel) this.logger.warn(`Redis indisponivel: ${err.message}`);
      this.disponivel = false;
    });
  }

  async onModuleDestroy() {
    await this.client?.quit().catch(() => undefined);
  }

  /**
   * Chave estavel para uma listagem. As chaves do objeto sao ordenadas antes
   * do hash, senao ?q=a&sort=b e ?sort=b&q=a gerariam entradas diferentes
   * para a mesma consulta.
   */
  chaveDeLista(prefixo: string, params: Record<string, unknown>): string {
    const normalizado = Object.keys(params)
      .filter((k) => params[k] !== undefined && params[k] !== null)
      .sort()
      .map((k) => `${k}=${String(params[k])}`)
      .join('&');
    const hash = createHash('sha1').update(normalizado).digest('hex').slice(0, 16);
    return `${prefixo}:${hash}`;
  }

  /**
   * Le do cache; em qualquer falha devolve null e o chamador vai ao banco.
   * O cache e otimizacao, nunca dependencia: Redis fora do ar degrada
   * latencia, nao disponibilidade.
   */
  async get<T>(chave: string): Promise<T | null> {
    if (!this.disponivel) return null;
    try {
      const bruto = await this.client.get(chave);
      return bruto ? (JSON.parse(bruto) as T) : null;
    } catch (err) {
      this.logger.warn(`Falha ao ler ${chave}: ${(err as Error).message}`);
      return null;
    }
  }

  async set(chave: string, valor: unknown, ttlSegundos: number): Promise<void> {
    if (!this.disponivel) return;
    try {
      await this.client.set(chave, JSON.stringify(valor), 'EX', ttlSegundos);
    } catch (err) {
      this.logger.warn(`Falha ao gravar ${chave}: ${(err as Error).message}`);
    }
  }

  async del(...chaves: string[]): Promise<void> {
    if (!this.disponivel || chaves.length === 0) return;
    try {
      await this.client.del(...chaves);
    } catch (err) {
      this.logger.warn(`Falha ao invalidar: ${(err as Error).message}`);
    }
  }

  /**
   * Invalidacao por padrao. Usa SCAN, nunca KEYS: KEYS bloqueia o Redis
   * inteiro enquanto varre, e sob pico isso derruba o cache do catalogo.
   */
  async delPorPadrao(padrao: string): Promise<number> {
    if (!this.disponivel) return 0;
    let removidas = 0;
    try {
      let cursor = '0';
      do {
        const [proximo, chaves] = await this.client.scan(cursor, 'MATCH', padrao, 'COUNT', 200);
        cursor = proximo;
        if (chaves.length > 0) {
          await this.client.del(...chaves);
          removidas += chaves.length;
        }
      } while (cursor !== '0');
    } catch (err) {
      this.logger.warn(`Falha ao invalidar padrao ${padrao}: ${(err as Error).message}`);
    }
    return removidas;
  }
}
