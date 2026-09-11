import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SchedulerRegistry } from '@nestjs/schedule';
import { Counter } from 'prom-client';
import { PrismaService } from '../prisma/prisma.service';
import { comPrazo } from '../common/prazo.util';
import { Fila } from '../fila/fila';
import { Eventos, EventoPublicado, TipoEvento } from './eventos';

// A publicacao roda dentro da transacao que trava os eventos: sem prazo, uma
// fila lenta seguraria a transacao aberta ate o timeout do Prisma.
const PRAZO_PUBLICACAO_MS = 10_000;

// Incrementado so depois do commit, para nao contar publicacao desfeita.
const publicados = new Counter({
  name: 'achou_outbox_publicados_total',
  help: 'Eventos do outbox publicados na fila',
  labelNames: ['tipo'],
});

// Nasce em zero para o rate() enxergar ja o primeiro evento de cada tipo.
for (const tipo of Object.values(Eventos)) publicados.inc({ tipo }, 0);

const falhas = new Counter({
  name: 'achou_outbox_falhas_total',
  help: 'Ciclos do relay que falharam; os eventos continuam pendentes',
});

interface LinhaOutbox {
  id: string;
  type: TipoEvento;
  payload: any;
  created_at: Date;
}

/**
 * Drena outbox_events para a fila.
 *
 * Entrega at-least-once: se o processo cair entre publicar e marcar
 * published_at, o evento sai de novo no proximo ciclo. A fila local ignora o
 * id repetido; a OCI Queue nao deduplica, e quem segura e o processed_events
 * do consumidor.
 */
@Injectable()
export class OutboxRelayService implements OnModuleInit {
  private readonly logger = new Logger(OutboxRelayService.name);
  private readonly intervaloMs: number;
  private readonly lote: number;
  private rodando = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly scheduler: SchedulerRegistry,
    private readonly fila: Fila,
    config: ConfigService,
  ) {
    this.intervaloMs = Number(config.get('OUTBOX_POLL_INTERVAL_MS', '5000'));
    this.lote = Number(config.get('OUTBOX_BATCH_SIZE', '100'));
  }

  // Registro dinamico em vez de @Interval(): o decorator exige o valor em
  // tempo de compilacao, e o intervalo vem do .env.
  onModuleInit() {
    this.scheduler.addInterval('outbox-relay', setInterval(() => this.drenar(), this.intervaloMs));
    this.logger.log(`Relay ativo: a cada ${this.intervaloMs}ms, lotes de ${this.lote}, fila ${this.fila.nome}`);
  }

  async drenar(): Promise<number> {
    // Lote grande pode passar do intervalo; sem a trava, dois ciclos do mesmo
    // processo disputariam as mesmas linhas.
    if (this.rodando) return 0;
    this.rodando = true;
    try {
      const eventos = await this.prisma.$transaction(
        async (tx) => {
          // SKIP LOCKED: com varias replicas do worker, cada uma pega um lote
          // diferente em vez de esperar o lock da outra. Usa idx_outbox_pendentes.
          const eventos = await tx.$queryRaw<LinhaOutbox[]>`
            SELECT id, type, payload, created_at
              FROM outbox_events
             WHERE published_at IS NULL
             ORDER BY created_at
             LIMIT ${this.lote}
               FOR UPDATE SKIP LOCKED`;
          if (eventos.length === 0) return eventos;

          await comPrazo(
            this.fila.publicar(eventos.map((e) => ({
              eventId: e.id,
              type: e.type,
              payload: e.payload,
              occurredAt: e.created_at.toISOString(),
            } satisfies EventoPublicado))),
            PRAZO_PUBLICACAO_MS,
            `fila ${this.fila.nome} sem resposta em ${PRAZO_PUBLICACAO_MS}ms`,
          );

          // Se a fila falhou acima, a excecao desfaz a transacao e os eventos
          // continuam pendentes: nada se perde com a fila fora do ar.
          await tx.outboxEvent.updateMany({
            where: { id: { in: eventos.map((e) => e.id) } },
            data: { publishedAt: new Date() },
          });
          return eventos;
        },
        { timeout: 15_000 },
      );

      if (eventos.length > 0) {
        for (const e of eventos) publicados.inc({ tipo: e.type });
        this.logger.log(`${eventos.length} evento(s) publicados na fila`);
      }
      return eventos.length;
    } catch (err) {
      falhas.inc();
      this.logger.warn(`Falha ao drenar o outbox, nova tentativa no proximo ciclo: ${(err as Error).message}`);
      return 0;
    } finally {
      this.rodando = false;
    }
  }
}
