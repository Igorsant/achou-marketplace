import { Logger } from '@nestjs/common';

/**
 * Listener de 'error' para Queue e Worker do BullMQ. Com o Redis fora, o
 * ioredis tenta reconectar em loop e cada tentativa emite 'error': sem
 * listener, o BullMQ joga uma stack inteira no console por tentativa. Aqui
 * sai no maximo uma linha a cada 30s, o bastante para ver que a queda continua.
 */
export function avisoDeConexao(logger: Logger, origem: string, intervaloMs = 30_000) {
  let ultimo = 0;
  return (err: Error) => {
    const agora = Date.now();
    if (agora - ultimo < intervaloMs) return;
    ultimo = agora;
    logger.warn(`${origem}: ${err.message} (repeticoes suprimidas por ${intervaloMs / 1000}s)`);
  };
}
