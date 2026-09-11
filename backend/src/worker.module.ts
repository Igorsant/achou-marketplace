import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './prisma/prisma.module';
import { FilaModule } from './fila/fila.module';
import { OutboxModule } from './outbox/outbox.module';
import { NotificationsModule } from './notifications/notifications.module';
import { WorkerMetricsService } from './metrics/worker-metrics.service';

/**
 * Processo assincrono, separado da API: relay do outbox + consumidor da fila.
 * Fica fora do caminho da requisicao, e escala (ou cai) sem afetar a latencia
 * das rotas HTTP. A API so escreve no outbox; nem conhece a fila.
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(),
    PrismaModule,
    FilaModule,
    OutboxModule,
    NotificationsModule,
  ],
  providers: [WorkerMetricsService],
})
export class WorkerModule {}
