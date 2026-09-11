import { Logger } from '@nestjs/common';
import { setTimeout as esperar } from 'node:timers/promises';
import * as common from 'oci-common';
import { QueueClient, models } from 'oci-queue';
import { EventoPublicado } from '../outbox/eventos';
import { avisoLimitado } from '../common/aviso-limitado';
import {
  CONCORRENCIA, EstatisticasFila, Fila, MAX_TENTATIVAS, Processador, atrasoDeRetrySegundos,
} from './fila';

// Long polling: o GetMessages segura a conexao ate chegar mensagem ou passar
// este tempo. Fila vazia custa ~3 requisicoes por minuto por replica, bem
// dentro do 1 milhao gratuito por mes.
const ESPERA_LONG_POLL_S = 20;
const VISIBILIDADE_S = 30;
// Limite da API: 20 mensagens por PutMessages.
const LOTE_PUBLICACAO = 20;

export interface ConfigFilaOci {
  queueId: string;
  endpoint: string;
  /** instance_principal no cluster; config_file para testar da maquina local. */
  autenticacao: 'instance_principal' | 'config_file';
  perfil?: string;
}

/**
 * OCI Queue (FILA_DRIVER=oci): fila gerenciada, fora do cluster. A
 * dead-letter e da propria OCI: depois de dead_letter_queue_delivery_count
 * entregas sem confirmacao, a mensagem sai da fila principal sozinha.
 */
export class FilaOci extends Fila {
  readonly nome = 'notificacoes';
  private readonly logger = new Logger(FilaOci.name);
  private readonly avisar = avisoLimitado(this.logger);
  private ativo = false;
  private laco: Promise<void> | null = null;

  // O cliente pode ser injetado (teste); sem ele, e criado na primeira chamada.
  constructor(
    private readonly config: ConfigFilaOci,
    private cliente?: QueueClient,
  ) {
    super();
  }

  async publicar(eventos: EventoPublicado[]) {
    const cliente = await this.obterCliente();
    for (let i = 0; i < eventos.length; i += LOTE_PUBLICACAO) {
      // Sem deduplicacao na OCI Queue: evento republicado vira mensagem
      // repetida, e quem segura e o processed_events do consumidor.
      await cliente.putMessages({
        queueId: this.config.queueId,
        putMessagesDetails: {
          messages: eventos.slice(i, i + LOTE_PUBLICACAO).map((e) => ({ content: JSON.stringify(e) })),
        },
      });
    }
  }

  consumir(processar: Processador) {
    this.ativo = true;
    this.laco = this.rodar(processar);
  }

  async parar() {
    this.ativo = false;
    await this.laco;
  }

  async estatisticas(): Promise<EstatisticasFila> {
    const cliente = await this.obterCliente();
    const { queueStats } = await cliente.getStats({ queueId: this.config.queueId });
    return {
      aguardando: queueStats.queue.visibleMessages,
      emProcessamento: queueStats.queue.inFlightMessages,
      mortas: queueStats.dlq.visibleMessages,
    };
  }

  private async obterCliente(): Promise<QueueClient> {
    if (this.cliente) return this.cliente;
    // Instance principal: o pod age com a identidade do node (dynamic group e
    // policy do Terraform). O OKE Basic nao tem Workload Identity; a
    // alternativa seria guardar uma chave de API num Secret.
    const auth = this.config.autenticacao === 'config_file'
      ? new common.ConfigFileAuthenticationDetailsProvider(undefined, this.config.perfil)
      : await new common.InstancePrincipalsAuthenticationDetailsProviderBuilder().build();
    const cliente = new QueueClient({ authenticationDetailsProvider: auth });
    cliente.endpoint = this.config.endpoint;
    this.cliente = cliente;
    return cliente;
  }

  private async rodar(processar: Processador) {
    while (this.ativo) {
      try {
        const cliente = await this.obterCliente();
        const { getMessages } = await cliente.getMessages({
          queueId: this.config.queueId,
          limit: CONCORRENCIA,
          visibilityInSeconds: VISIBILIDADE_S,
          timeoutInSeconds: ESPERA_LONG_POLL_S,
        });
        await Promise.all(getMessages.messages.map((m) => this.entregar(cliente, m, processar)));
      } catch (err) {
        this.avisar(`fila ${this.nome}: ${(err as Error).message}`);
        await esperar(5_000);
      }
    }
  }

  private async entregar(cliente: QueueClient, m: models.GetMessage, processar: Processador) {
    // deliveryCount comeca em 1 e e contado pela propria OCI.
    const ultima = m.deliveryCount >= MAX_TENTATIVAS;
    try {
      const evento = JSON.parse(m.content) as EventoPublicado;
      await processar(evento, { tentativa: m.deliveryCount, ultima });
      await cliente.deleteMessage({ queueId: this.config.queueId, messageReceipt: m.receipt });
    } catch {
      // Backoff: esconde a mensagem por mais tempo em vez de devolve-la ja.
      // Na ultima tentativa, prazo curto: ela segue logo para a dead-letter.
      // Se ate isto falhar, a visibilidade de 30s expira e ela volta igual.
      await cliente.updateMessage({
        queueId: this.config.queueId,
        messageReceipt: m.receipt,
        updateMessageDetails: { visibilityInSeconds: ultima ? 1 : atrasoDeRetrySegundos(m.deliveryCount) },
      }).catch(() => undefined);
    }
  }
}
