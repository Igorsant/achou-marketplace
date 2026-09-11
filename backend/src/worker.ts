import { NestFactory } from '@nestjs/core';
import { Logger } from '@nestjs/common';
import { WorkerModule } from './worker.module';
import { iniciarServidorDeMetricas } from './metrics/servidor';

async function bootstrap() {
  // Sem servidor HTTP: so o contexto de injecao de dependencia.
  const app = await NestFactory.createApplicationContext(WorkerModule);

  // No SIGTERM (deploy, scale-in) o BullMQ termina os jobs em andamento
  // antes de sair, em vez de deixa-los travados ate o lock expirar.
  app.enableShutdownHooks();

  // Porta diferente da API: rodando os dois fora do Docker, na mesma maquina,
  // a mesma porta colidiria.
  iniciarServidorDeMetricas(Number(process.env.WORKER_METRICS_PORT ?? 9465));

  Logger.log('Worker no ar: relay do outbox + fila de notificacoes', 'Worker');
}
bootstrap();
