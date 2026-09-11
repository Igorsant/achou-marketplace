import { Prisma, Role } from '@prisma/client';

/**
 * Catalogo de eventos de dominio. O nome do tipo e contrato com os
 * consumidores: evento ja publicado nunca muda de nome nem perde campo.
 */
export const Eventos = {
  USUARIO_CADASTRADO: 'usuario.cadastrado',
} as const;

export type TipoEvento = (typeof Eventos)[keyof typeof Eventos];

export interface PayloadPorEvento {
  'usuario.cadastrado': { userId: string; email: string; name: string; role: Role };
}

/** Formato do job na fila: o evento do outbox mais o id que garante idempotencia. */
export interface EventoPublicado<T extends TipoEvento = TipoEvento> {
  eventId: string;
  type: T;
  payload: PayloadPorEvento[T];
  occurredAt: string;
}

/**
 * Grava o evento no outbox. Recebe o client da transacao de proposito: o
 * evento so pode existir se a escrita de negocio que o originou tambem
 * existir. Gravar fora da transacao reabre a janela de "salvou o usuario
 * mas perdeu a notificacao" que o outbox existe para fechar.
 */
export function registrarEvento<T extends TipoEvento>(
  tx: Prisma.TransactionClient,
  type: T,
  payload: PayloadPorEvento[T],
) {
  return tx.outboxEvent.create({
    data: { type, payload: payload as unknown as Prisma.InputJsonObject },
  });
}
