import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './prisma/prisma.module';
import { OutboxModule } from './outbox/outbox.module';
import { NotificationsModule } from './notifications/notifications.module';
import { QueueModule } from './queue/queue.module';
import { WorkerMetricsService } from './metrics/worker-metrics.service';

/**
 * Processo assincrono, separado da API: relay do outbox + consumidores da fila.
 * Fica fora do caminho da requisicao, e escala (ou cai) sem afetar a latencia
 * das rotas HTTP. A API so escreve no outbox; nem conecta no BullMQ.
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(),
    PrismaModule,
    QueueModule,
    OutboxModule,
    NotificationsModule,
  ],
  providers: [WorkerMetricsService],
})
export class WorkerModule {}
