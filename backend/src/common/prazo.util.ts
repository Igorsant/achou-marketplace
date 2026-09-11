/**
 * Rejeita se a promessa nao resolver em `ms`. Existe por causa do ioredis:
 * com o Redis fora ele nao falha, segura o comando na fila offline ate
 * reconectar, e quem aguarda fica parado sem erro.
 *
 * A promessa original nao e cancelada -- continua pendente e pode completar
 * depois. Quem chama precisa tolerar isso.
 */
export async function comPrazo<T>(promessa: Promise<T>, ms: number, mensagem: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const prazo = new Promise<never>((_, rejeitar) => {
    timer = setTimeout(() => rejeitar(new Error(mensagem)), ms);
  });
  try {
    return await Promise.race([promessa, prazo]);
  } finally {
    clearTimeout(timer);
  }
}
