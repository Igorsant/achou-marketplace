import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { Fila } from './fila';
import { FilaOci } from './fila-oci';
import { FilaPostgres } from './fila-postgres';

/** FILA_DRIVER escolhe a implementacao: postgres (padrao, local) ou oci. */
function criarFila(config: ConfigService, prisma: PrismaService): Fila {
  const driver = config.get<string>('FILA_DRIVER', 'postgres');
  if (driver === 'postgres') return new FilaPostgres(prisma);
  if (driver === 'oci') {
    return new FilaOci({
      queueId: config.getOrThrow<string>('FILA_OCI_ID'),
      endpoint: config.getOrThrow<string>('FILA_OCI_ENDPOINT'),
      autenticacao: config.get('FILA_OCI_AUTH', 'instance_principal'),
      perfil: config.get<string>('OCI_CLI_PROFILE'),
    });
  }
  throw new Error(`FILA_DRIVER invalido: "${driver}" (use postgres ou oci)`);
}

@Module({
  providers: [{ provide: Fila, inject: [ConfigService, PrismaService], useFactory: criarFila }],
  exports: [Fila],
})
export class FilaModule {}
