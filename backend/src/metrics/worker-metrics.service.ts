import { Injectable } from '@nestjs/common';
import { Gauge } from 'prom-client';
import { PrismaService } from '../prisma/prisma.service';
import { Fila } from '../fila/fila';
import { comPrazo } from '../common/prazo.util';

// Abaixo do scrape_timeout do Prometheus: uma leitura lenta derruba so a
// propria metrica, nao o scrape inteiro do worker.
const PRAZO_COLETA_MS = 2_000;

/**
 * Metricas de estado, lidas no momento do scrape em vez de mantidas em
 * memoria: o outbox e a fila sao compartilhados entre replicas do worker, e
 * um contador local so enxergaria o que a propria replica fez.
 *
 * Se a leitura falha, a metrica fica sem valor (NaN ou serie ausente), nunca
 * zero: "0 pendentes" com o banco fora do ar seria mentira.
 */
@Injectable()
export class WorkerMetricsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly fila: Fila,
  ) {
    const servico = this;

    new Gauge({
      name: 'achou_outbox_pendentes',
      help: 'Eventos no outbox ainda nao publicados na fila',
      async collect() {
        try {
          const [{ n }] = await servico.consultar<{ n: bigint }>(
            `SELECT count(*) AS n FROM outbox_events WHERE published_at IS NULL`,
          );
          this.set(Number(n));
        } catch {
          this.set(NaN);
        }
      },
    });

    // Idade do evento pendente mais antigo. Melhor sinal de alerta que a
    // contagem: 50 pendentes ha 2s e normal, 1 pendente ha 5min nao e.
    new Gauge({
      name: 'achou_outbox_atraso_segundos',
      help: 'Idade do evento pendente mais antigo no outbox (0 = nada pendente)',
      async collect() {
        try {
          const [{ s }] = await servico.consultar<{ s: number | null }>(
            `SELECT extract(epoch FROM now() - min(created_at))::float8 AS s
               FROM outbox_events WHERE published_at IS NULL`,
          );
          this.set(s ?? 0);
        } catch {
          this.set(NaN);
        }
      },
    });

    // estado: aguardando | em_processamento | morta. O KEDA escala o worker
    // por "aguardando" (deploy/k8s/base/worker-escala.yaml).
    new Gauge({
      name: 'achou_fila_jobs',
      help: 'Mensagens na fila por estado',
      labelNames: ['fila', 'estado'],
      async collect() {
        try {
          const e = await comPrazo(servico.fila.estatisticas(), PRAZO_COLETA_MS, 'fila sem resposta');
          this.set({ fila: servico.fila.nome, estado: 'aguardando' }, e.aguardando);
          this.set({ fila: servico.fila.nome, estado: 'em_processamento' }, e.emProcessamento);
          this.set({ fila: servico.fila.nome, estado: 'morta' }, e.mortas);
        } catch {
          this.reset();
        }
      },
    });
  }

  private consultar<T>(sql: string) {
    return comPrazo(this.prisma.$queryRawUnsafe<T[]>(sql), PRAZO_COLETA_MS, 'postgres sem resposta');
  }
}
