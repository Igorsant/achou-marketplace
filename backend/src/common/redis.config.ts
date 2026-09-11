import { ConfigService } from '@nestjs/config';

export type ConexaoRedis = { url: string } | { host: string; port: number };

/**
 * Conexao de um dos dois papeis do Redis. Em producao sao instancias
 * separadas: o cache quer descartar chave antiga quando a memoria enche
 * (allkeys-lru), a fila nao pode perder job e o BullMQ exige noeviction.
 * Na mesma instancia, uma das duas politicas fica errada.
 *
 * REDIS_<PAPEL>_URL tem precedencia: e o formato do Redis gerenciado, que
 * carrega senha e TLS (rediss://). Sem ela, vale REDIS_HOST/REDIS_PORT --
 * o ambiente local, onde uma instancia so atende os dois papeis.
 */
export function conexaoRedis(config: ConfigService, papel: 'CACHE' | 'FILA'): ConexaoRedis {
  const url = config.get<string>(`REDIS_${papel}_URL`);
  if (url) return { url };
  return {
    host: config.get<string>('REDIS_HOST', 'localhost'),
    port: Number(config.get<string>('REDIS_PORT', '6379')),
  };
}
