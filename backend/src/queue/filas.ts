import { TipoEvento } from '../outbox/eventos';

export const FILA_NOTIFICACOES = 'notificacoes';

/**
 * Para quais filas cada evento vai. Uma fila por consumidor: o BullMQ entrega
 * cada job a um unico worker, entao fan-out (notificacao + analytics sobre o
 * mesmo evento) exige publicar o evento em mais de uma fila.
 */
export const ROTAS: Record<TipoEvento, string[]> = {
  'usuario.cadastrado': [FILA_NOTIFICACOES],
};
