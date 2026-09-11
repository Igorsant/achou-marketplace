import { Injectable, Logger, OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Counter, Histogram } from 'prom-client';
import { PrismaService } from '../prisma/prisma.service';
import { Fila, Entrega, MAX_TENTATIVAS } from '../fila/fila';
import { EventoPublicado, Eventos } from '../outbox/eventos';
import { Email, EmailMockService } from './email-mock.service';
import { montarEmail } from './templates';

// Nome gravado em processed_events. Outro consumidor do mesmo evento
// (analytics) usa outro nome e registra o proprio consumo.
const HANDLER = 'notificacao-email';

// resultado: enviada | duplicada | sem_template | falha (por tentativa) | esgotada
const notificacoes = new Counter({
  name: 'achou_notificacoes_total',
  help: 'Notificacoes processadas pelo worker, por resultado',
  labelNames: ['tipo', 'resultado'],
});
const envio = new Histogram({
  name: 'achou_notificacao_envio_segundos',
  help: 'Latencia do provedor de e-mail',
  labelNames: ['resultado'],
  buckets: [0.1, 0.25, 0.5, 1, 2.5, 5],
});
// Do INSERT no outbox ate o e-mail sair: soma o intervalo do relay, a espera
// na fila e os retries. E o atraso que o usuario de fato percebe.
const latencia = new Histogram({
  name: 'achou_notificacao_latencia_segundos',
  help: 'Tempo entre o evento ocorrer e a notificacao ser enviada',
  labelNames: ['tipo'],
  buckets: [1, 2.5, 5, 10, 30, 60, 120, 300, 900],
});

// Series nascem em zero. Sem isso, a primeira notificacao de cada resultado
// aparece no scrape ja valendo 1 e o rate() nao ve incremento nenhum -- o
// alerta de "esgotada" perderia justamente a primeira falha.
for (const tipo of Object.values(Eventos)) {
  for (const resultado of ['enviada', 'duplicada', 'sem_template', 'falha', 'esgotada']) {
    notificacoes.inc({ tipo, resultado }, 0);
  }
  latencia.zero({ tipo });
}
for (const resultado of ['ok', 'erro']) envio.zero({ resultado });

/** Consome a fila e envia a notificacao de cada evento. */
@Injectable()
export class NotificationsProcessor implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger(NotificationsProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly email: EmailMockService,
    private readonly fila: Fila,
  ) {}

  onApplicationBootstrap() {
    this.fila.consumir((evento, entrega) => this.processar(evento, entrega));
  }

  // No SIGTERM (deploy, scale-in) termina o lote em andamento antes de sair.
  async onModuleDestroy() {
    await this.fila.parar();
  }

  async processar(evento: EventoPublicado, entrega: Entrega) {
    try {
      await this.notificar(evento);
    } catch (err) {
      const msg = `evento ${evento.eventId} falhou (tentativa ${entrega.tentativa}/${MAX_TENTATIVAS}): ${(err as Error).message}`;
      notificacoes.inc({ tipo: evento.type, resultado: 'falha' });
      if (entrega.ultima) {
        notificacoes.inc({ tipo: evento.type, resultado: 'esgotada' });
        this.logger.error(`${msg} -- tentativas esgotadas, mensagem vai para a dead-letter`);
      } else {
        this.logger.warn(msg);
      }
      throw err; // a fila agenda o retry (ou move para a dead-letter)
    }
  }

  private async notificar(evento: EventoPublicado) {
    const { eventId, type } = evento;

    // A fila entrega at-least-once: o mesmo evento pode chegar duas vezes.
    const jaProcessado = await this.prisma.processedEvent.findUnique({
      where: { eventId_handler: { eventId, handler: HANDLER } },
    });
    if (jaProcessado) {
      notificacoes.inc({ tipo: type, resultado: 'duplicada' });
      this.logger.log(`evento ${eventId} ja notificado, ignorando duplicata`);
      return;
    }

    const mensagem = montarEmail(evento);
    if (mensagem) await this.enviar(mensagem);
    else this.logger.warn(`evento ${eventId} (${type}) sem template de notificacao`);

    // Registrado so depois do envio: se o worker cair no meio, o retry
    // reenvia. E-mail duplicado e preferivel a e-mail perdido.
    try {
      await this.prisma.processedEvent.create({ data: { eventId, handler: HANDLER } });
    } catch (err) {
      // P2002: outra replica processou o mesmo evento em paralelo.
      if (!(err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002')) throw err;
    }

    notificacoes.inc({ tipo: type, resultado: mensagem ? 'enviada' : 'sem_template' });
    if (mensagem) latencia.observe({ tipo: type }, (Date.now() - Date.parse(evento.occurredAt)) / 1000);
  }

  private async enviar(mensagem: Email) {
    const fim = envio.startTimer();
    try {
      await this.email.enviar(mensagem);
      fim({ resultado: 'ok' });
    } catch (err) {
      fim({ resultado: 'erro' });
      throw err;
    }
  }
}
