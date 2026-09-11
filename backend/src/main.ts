import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { instrumentarHttp } from './metrics/http';
import { iniciarServidorDeMetricas } from './metrics/servidor';

async function bootstrap() {
  // Atras do gateway, request.ip seria o IP do proxy, e o rate limit de
  // 100 req/min "por IP" valeria para todos os usuarios somados.
  // TRUST_PROXY lista as redes dos proxies (ex.: "uniquelocal" ou o CIDR da
  // VPC). O Fastify percorre o X-Forwarded-For da direita para a esquerda e
  // para no primeiro IP fora dessas redes: o do cliente. Entradas forjadas
  // pelo cliente ficam a esquerda e nunca sao lidas.
  //
  // Nunca "true" (confia no cabecalho inteiro, o cliente escolhe o proprio IP)
  // nem numero de saltos: desde o Fastify 5.12, numero nao confia em nada.
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({ logger: false, trustProxy: process.env.TRUST_PROXY || false }),
  );

  // No SIGTERM do rolling update, o Fastify para de aceitar conexoes e espera
  // as requisicoes em andamento; sem isto o processo morre com elas no meio.
  app.enableShutdownHooks();

  instrumentarHttp(app.getHttpAdapter().getInstance());

  app.useGlobalFilters(new HttpExceptionFilter());

  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );

  const config = new DocumentBuilder()
    .setTitle('Achou! Marketplace API')
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  SwaggerModule.setup('docs', app, SwaggerModule.createDocument(app, config));

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port, '0.0.0.0');
  console.log(`API em http://localhost:${port} — docs em /docs`);

  iniciarServidorDeMetricas(Number(process.env.METRICS_PORT ?? 9464));
}

bootstrap();
