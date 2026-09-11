import { Logger } from '@nestjs/common';

/**
 * Log de erro repetitivo (dependencia fora do ar, reconexao em loop) com no
 * maximo uma linha a cada 30s: o bastante para ver que a queda continua, sem
 * afogar o resto do log.
 */
export function avisoLimitado(logger: Logger, intervaloMs = 30_000) {
  let ultimo = 0;
  return (mensagem: string) => {
    const agora = Date.now();
    if (agora - ultimo < intervaloMs) return;
    ultimo = agora;
    logger.warn(`${mensagem} (repeticoes suprimidas por ${intervaloMs / 1000}s)`);
  };
}
