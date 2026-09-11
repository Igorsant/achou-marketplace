import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { BullModule } from '@nestjs/bullmq';
import { FILA_NOTIFICACOES } from './filas';
import { conexaoRedis } from '../common/redis.config';

@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        connection: conexaoRedis(config, 'FILA'),
      }),
    }),
    BullModule.registerQueue({
      name: FILA_NOTIFICACOES,
      defaultJobOptions: {
        // 5 tentativas com espera de 2s, 4s, 8s, 16s: cobre instabilidade
        // curta do provedor de e-mail sem martelar o servico enquanto cai.
        attempts: 5,
        backoff: { type: 'exponential', delay: 2_000 },
        removeOnComplete: { age: 24 * 3600, count: 1_000 },
        // Falha definitiva fica guardada 7 dias para inspecao e reprocesso.
        removeOnFail: { age: 7 * 24 * 3600 },
      },
    }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
