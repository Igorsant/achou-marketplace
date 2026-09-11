import { Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { setTimeout as esperar } from 'node:timers/promises';
import { PrismaService } from '../prisma/prisma.service';
import { EventoPublicado } from '../outbox/eventos';
import { avisoLimitado } from '../common/aviso-limitado';
import {
  CONCORRENCIA, EstatisticasFila, Fila, MAX_TENTATIVAS, Processador, atrasoDeRetrySegundos,
} from './fila';

// Tempo em que a mensagem fica invisivel enquanto e processada. Se o worker
// morrer no meio, ela reaparece sozinha depois disso: o mesmo mecanismo de
// visibilidade da OCI Queue.
const VISIBILIDADE_S = 30;
const ESPERA_FILA_VAZIA_MS = 1_000;

interface Reservada {
  id: string;
  conteudo: EventoPublicado;
  tentativas: number;
}

/**
 * Fila do ambiente local (FILA_DRIVER=postgres), na tabela fila_mensagens.
 * Existe para desenvolver sem conta na OCI; em producao a fila e a OCI Queue.
 */
export class FilaPostgres extends Fila {
  readonly nome = 'notificacoes';
  private readonly logger = new Logger(FilaPostgres.name);
  private readonly avisar = avisoLimitado(this.logger);
  private ativo = false;
  private laco: Promise<void> | null = null;

  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async publicar(eventos: EventoPublicado[]) {
    if (eventos.length === 0) return;
    // id da mensagem = id do evento: o relay que republica depois de uma
    // falha nao cria duplicata.
    await this.prisma.filaMensagem.createMany({
      data: eventos.map((e) => ({
        id: e.eventId,
        tipo: e.type,
        conteudo: e as unknown as Prisma.InputJsonObject,
      })),
      skipDuplicates: true,
    });
  }

  consumir(processar: Processador) {
    this.ativo = true;
    this.laco = this.rodar(processar);
  }

  async parar() {
    this.ativo = false;
    await this.laco;
  }

  async estatisticas(): Promise<EstatisticasFila> {
    const [l] = await this.prisma.$queryRaw<{ a: bigint; p: bigint; m: bigint }[]>`
      SELECT count(*) FILTER (WHERE NOT morta AND visivel_em <= now()) AS a,
             count(*) FILTER (WHERE NOT morta AND visivel_em >  now()) AS p,
             count(*) FILTER (WHERE morta)                             AS m
        FROM fila_mensagens`;
    return { aguardando: Number(l.a), emProcessamento: Number(l.p), mortas: Number(l.m) };
  }

  private async rodar(processar: Processador) {
    while (this.ativo) {
      try {
        const lote = await this.reservar();
        if (lote.length === 0) {
          await esperar(ESPERA_FILA_VAZIA_MS);
          continue;
        }
        await Promise.all(lote.map((m) => this.entregar(m, processar)));
      } catch (err) {
        this.avisar(`fila ${this.nome}: ${(err as Error).message}`);
        await esperar(5_000);
      }
    }
  }

  /**
   * Reserva e esconde ate CONCORRENCIA mensagens numa instrucao so.
   * SKIP LOCKED: replicas do worker em paralelo nunca pegam a mesma mensagem.
   */
  private reservar() {
    return this.prisma.$queryRaw<Reservada[]>`
      UPDATE fila_mensagens f
         SET tentativas = f.tentativas + 1,
             visivel_em = now() + ${VISIBILIDADE_S} * interval '1 second'
       WHERE f.id IN (
             SELECT id FROM fila_mensagens
              WHERE NOT morta AND visivel_em <= now()
              ORDER BY visivel_em
              LIMIT ${CONCORRENCIA}
                FOR UPDATE SKIP LOCKED)
      RETURNING f.id, f.conteudo, f.tentativas`;
  }

  private async entregar(m: Reservada, processar: Processador) {
    const ultima = m.tentativas >= MAX_TENTATIVAS;
    try {
      await processar(m.conteudo, { tentativa: m.tentativas, ultima });
      await this.prisma.filaMensagem.delete({ where: { id: m.id } });
    } catch (err) {
      const ultimoErro = (err as Error).message;
      await this.prisma.filaMensagem.update({
        where: { id: m.id },
        data: ultima
          ? { morta: true, ultimoErro }
          : { ultimoErro, visivelEm: new Date(Date.now() + atrasoDeRetrySegundos(m.tentativas) * 1000) },
      });
    }
  }
}
