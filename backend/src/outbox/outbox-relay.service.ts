import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SchedulerRegistry } from '@nestjs/schedule';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { Counter } from 'prom-client';
import { PrismaService } from '../prisma/prisma.service';
import { comPrazo } from '../common/prazo.util';
import { FILA_NOTIFICACOES, ROTAS } from '../queue/filas';
import { avisoDeConexao } from '../queue/aviso-de-conexao';
import { EventoPublicado, TipoEvento } from './eventos';

// Com o Redis fora, o ioredis segura o comando na fila offline ate reconectar
// e o relay ficaria parado sem erro, com a transacao aberta. O prazo derruba o
// ciclo e desfaz a transacao; os eventos continuam pendentes no outbox.
const PRAZO_PUBLICACAO_MS = 5_000;

type Jobs = Parameters<Queue['addBulk']>[0];

// Incrementado so depois do commit, para nao contar publicacao desfeita.
const publicados = new Counter({
  name: 'achou_outbox_publicados_total',
  help: 'Eventos do outbox publicados nas filas',
  labelNames: ['tipo'],
});
// Nasce em zero para o rate() enxergar ja o primeiro evento de cada tipo.
for (const tipo of Object.keys(ROTAS)) publicados.inc({ tipo }, 0);

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
 * Drena outbox_events para as filas do BullMQ.
 *
 * Entrega at-least-once: se o processo cair entre publicar na fila e marcar
 * published_at, o evento sai de novo no proximo ciclo. Duas defesas contra
 * duplicata: o jobId e o id do evento (o BullMQ ignora job com id repetido
 * enquanto o original existir) e o consumidor checa processed_events.
 */
@Injectable()
export class OutboxRelayService implements OnModuleInit {
  private readonly logger = new Logger(OutboxRelayService.name);
  private readonly filas: Map<string, Queue>;
  private readonly intervaloMs: number;
  private readonly lote: number;
  private rodando = false;
  private publicacaoPresa: Promise<unknown> | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly scheduler: SchedulerRegistry,
    config: ConfigService,
    @InjectQueue(FILA_NOTIFICACOES) notificacoes: Queue,
  ) {
    this.filas = new Map([[FILA_NOTIFICACOES, notificacoes]]);
    for (const [nome, fila] of this.filas) {
      fila.on('error', avisoDeConexao(this.logger, `fila ${nome}`));
    }
    this.intervaloMs = Number(config.get('OUTBOX_POLL_INTERVAL_MS', '5000'));
    this.lote = Number(config.get('OUTBOX_BATCH_SIZE', '100'));
  }

  // Registro dinamico em vez de @Interval(): o decorator exige o valor em
  // tempo de compilacao, e o intervalo vem do .env.
  onModuleInit() {
    this.scheduler.addInterval('outbox-relay', setInterval(() => this.drenar(), this.intervaloMs));
    this.logger.log(`Relay ativo: a cada ${this.intervaloMs}ms, lotes de ${this.lote}`);
  }

  async drenar(): Promise<number> {
    // Lote grande pode passar do intervalo; sem a trava, dois ciclos do mesmo
    // processo disputariam as mesmas linhas. E enquanto uma publicacao estourou
    // o prazo e segue esperando o Redis, tentar de novo so empilharia comandos
    // repetidos na fila offline do ioredis.
    if (this.rodando || this.publicacaoPresa) return 0;
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

          for (const [nome, fila] of this.filas) {
            const jobs = eventos
              .filter((e) => ROTAS[e.type]?.includes(nome))
              .map((e) => ({
                name: e.type,
                data: {
                  eventId: e.id,
                  type: e.type,
                  payload: e.payload,
                  occurredAt: e.created_at.toISOString(),
                } satisfies EventoPublicado,
                opts: { jobId: e.id },
              }));
            if (jobs.length > 0) await this.publicar(nome, fila, jobs);
          }

          for (const e of eventos.filter((e) => !ROTAS[e.type])) {
            this.logger.warn(`Evento ${e.id} de tipo "${e.type}" sem rota: marcado como publicado`);
          }

          // Se a fila falhou acima, a excecao desfaz a transacao e os eventos
          // continuam pendentes: nada se perde com o Redis fora do ar.
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

  /**
   * addBulk com prazo. Se o prazo estoura, o comando continua na fila offline
   * e entra quando o Redis voltar; o ciclo seguinte republica os mesmos
   * eventos e o jobId repetido faz o BullMQ ignorar a copia.
   */
  private async publicar(nome: string, fila: Queue, jobs: Jobs) {
    const envio = fila.addBulk(jobs);
    this.publicacaoPresa = envio;
    const liberar = () => { this.publicacaoPresa = null; };
    envio.then(liberar, liberar);
    await comPrazo(envio, PRAZO_PUBLICACAO_MS, `fila ${nome} sem resposta em ${PRAZO_PUBLICACAO_MS}ms`);
  }
}
