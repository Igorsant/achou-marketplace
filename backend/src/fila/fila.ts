import { EventoPublicado } from '../outbox/eventos';

/**
 * Entregas de uma mensagem antes de ela ir para a dead-letter. Na OCI Queue
 * tem que bater com dead_letter_queue_delivery_count (infra/oci/1-cluster/fila.tf).
 */
export const MAX_TENTATIVAS = 5;

/** Mensagens processadas em paralelo por replica do worker. */
export const CONCORRENCIA = 5;

/** Espera antes da reentrega depois da falha n: 2s, 4s, 8s, 16s. */
export function atrasoDeRetrySegundos(tentativa: number): number {
  return 2 ** tentativa;
}

export interface Entrega {
  /** 1 na primeira entrega. */
  tentativa: number;
  /** Se falhar agora, a mensagem vai para a dead-letter. */
  ultima: boolean;
}

export type Processador = (evento: EventoPublicado, entrega: Entrega) => Promise<void>;

export interface EstatisticasFila {
  /** Prontas para entrega. */
  aguardando: number;
  /** Entregues e ainda sem confirmacao, ou esperando o proximo retry. */
  emProcessamento: number;
  /** Esgotaram as tentativas: estao na dead-letter. */
  mortas: number;
}

/**
 * Porta da fila de eventos, com duas implementacoes:
 * - FilaOci: OCI Queue, servico gerenciado fora do cluster (producao);
 * - FilaPostgres: tabela no proprio banco (ambiente local, sem conta na nuvem).
 *
 * Mesma semantica nas duas: entrega at-least-once com visibilidade (a
 * mensagem some enquanto e processada e reaparece se o consumidor morrer),
 * retry com backoff exponencial e dead-letter depois de MAX_TENTATIVAS.
 *
 * Classe abstrata, e nao interface, porque serve de token de injecao do Nest.
 */
export abstract class Fila {
  abstract readonly nome: string;
  abstract publicar(eventos: EventoPublicado[]): Promise<void>;
  /** Inicia o consumo em segundo plano; falha do processador = retry. */
  abstract consumir(processar: Processador): void;
  /** Para de buscar mensagens e espera o lote em andamento terminar. */
  abstract parar(): Promise<void>;
  abstract estatisticas(): Promise<EstatisticasFila>;
}
