import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { setTimeout as esperar } from 'node:timers/promises';

export interface Email {
  para: string;
  assunto: string;
  corpo: string;
}

/**
 * Provedor de e-mail falso. Simula o que importa de um real para o fluxo
 * assincrono: latencia de rede e falha intermitente. A taxa de falha vem de
 * NOTIFICATION_MOCK_FAILURE_RATE (0 a 1) para exercitar o retry da fila.
 */
@Injectable()
export class EmailMockService {
  private readonly logger = new Logger('EmailMock');
  private readonly taxaFalha: number;

  constructor(config: ConfigService) {
    this.taxaFalha = Number(config.get('NOTIFICATION_MOCK_FAILURE_RATE', '0'));
  }

  async enviar(email: Email): Promise<{ messageId: string }> {
    await esperar(150 + Math.random() * 450);

    if (Math.random() < this.taxaFalha) {
      throw new Error('provedor de e-mail indisponivel (503 simulado)');
    }

    const messageId = `mock-${randomUUID()}`;
    this.logger.log(`enviado ${messageId} para=${email.para} assunto="${email.assunto}"`);
    return { messageId };
  }
}
