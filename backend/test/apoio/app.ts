import { ValidationPipe } from '@nestjs/common';
import { ThrottlerStorage } from '@nestjs/throttler';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Test } from '@nestjs/testing';
import { AppModule } from '../../src/app.module';
import { AuthService } from '../../src/auth/auth.service';
import { HttpExceptionFilter } from '../../src/common/filters/http-exception.filter';
import { PrismaService } from '../../src/prisma/prisma.service';
import { SENHA } from './banco';

export interface AppDeTeste {
  app: NestFastifyApplication;
  /** O que o supertest recebe. */
  servidor: ReturnType<NestFastifyApplication['getHttpServer']>;
  encerrar: () => Promise<void>;
}

/**
 * Sobe o AppModule de verdade — mesmo ValidationPipe e mesmo
 * HttpExceptionFilter de `main.ts`.
 *
 * Replicar os globais nao e detalhe: metade do que os ADRs afirmam e sobre
 * *formato de erro* (`CREDENCIAIS_INVALIDAS`, `SEM_PERMISSAO`,
 * `ESTOQUE_INSUFICIENTE`). Sem o filtro, o Nest devolveria
 * `{"statusCode":401,"message":"..."}` e o teste passaria a medir outro app.
 *
 * @param comThrottle mantem o ThrottlerGuard ativo. O padrao e desligar: o
 *   limite global e 100 req/min por IP e uma suite estoura isso com facilidade,
 *   transformando falha de teste em 429. O limite tem um teste proprio, que e o
 *   unico lugar onde ligar faz sentido.
 */
export async function criarApp({ comThrottle = false } = {}): Promise<AppDeTeste> {
  const builder = Test.createTestingModule({ imports: [AppModule] });

  if (!comThrottle) {
    // Substituir o *storage*, e nao o guard. O AppModule registra o
    // ThrottlerGuard com `{ provide: APP_GUARD, useClass: ThrottlerGuard }`:
    // `overrideGuard(ThrottlerGuard)` nao pega (o useClass instancia a classe
    // em vez de resolver o token) e `overrideProvider(APP_GUARD)` tambem nao
    // (o Nest coleta os enhancers por fora do injetor comum). Com o storage
    // respondendo "primeiro acesso" sempre, o guard continua no caminho — so
    // nunca estoura, e a suite deixa de tomar 429 no sexto login.
    builder.overrideProvider(ThrottlerStorage).useValue({
      increment: async () => ({
        totalHits: 1,
        timeToExpire: 60,
        isBlocked: false,
        timeToBlockExpire: 0,
      }),
    });
  }

  const moduleRef = await builder.compile();
  const app = moduleRef.createNestApplication<NestFastifyApplication>(
    new FastifyAdapter({ logger: false }),
  );

  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalPipes(
    new ValidationPipe({ transform: true, whitelist: true, forbidNonWhitelisted: true }),
  );

  await app.init();
  await app.getHttpAdapter().getInstance().ready();

  // Segunda trava, agora do lado do app: `banco.ts` garante que o *teste* fala
  // com um banco _test, isto garante que a *aplicacao* tambem — se o
  // ConfigModule tivesse lido DATABASE_URL do `.env` de desenvolvimento, os
  // dois estariam em bancos diferentes e o teste apagaria o banco errado.
  const prisma = app.get(PrismaService);
  const [{ current_database: banco }] =
    await prisma.$queryRaw<{ current_database: string }[]>`SELECT current_database()`;
  if (!banco.endsWith('_test')) {
    await app.close();
    throw new Error(`A aplicacao subiu apontada para "${banco}", que nao e banco de teste.`);
  }

  return {
    app,
    servidor: app.getHttpServer(),
    encerrar: () => app.close(),
  };
}

/**
 * Access token de um usuario ja criado, pelo AuthService em vez de por HTTP.
 *
 * Autenticar e *preparo* na maioria das suites, nao o assunto. Passar pelo
 * `POST /auth/login` a cada caso gastaria o limite de 5/min do §6.2 e faria um
 * teste de carrinho falhar com 429 — erro que nao diz nada sobre carrinho. O
 * token sai do mesmo `montarResposta`, entao e o token de verdade.
 */
export async function tokenDe(ctx: AppDeTeste, email: string): Promise<string> {
  const { accessToken } = await ctx.app.get(AuthService).login({ email, password: SENHA });
  return accessToken;
}
