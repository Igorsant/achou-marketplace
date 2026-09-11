import { ConfigService } from '@nestjs/config';

export type ConexaoRedis = { url: string } | { host: string; port: number };

/**
 * Conexao do Redis de cache (a fila nao usa Redis: ver src/fila).
 *
 * REDIS_CACHE_URL tem precedencia: e o formato que carrega senha e TLS
 * (rediss://). Sem ela, vale REDIS_HOST/REDIS_PORT do ambiente local.
 */
export function conexaoRedis(config: ConfigService): ConexaoRedis {
  const url = config.get<string>('REDIS_CACHE_URL');
  if (url) return { url };
  return {
    host: config.get<string>('REDIS_HOST', 'localhost'),
    port: Number(config.get<string>('REDIS_PORT', '6379')),
  };
}
