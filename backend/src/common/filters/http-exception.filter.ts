import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { FastifyReply } from 'fastify';

/**
 * Normaliza toda saida de erro no envelope { error: { code, message, details } }.
 * Sem isso o ValidationPipe devolve o formato padrao do Nest
 * ({"message":[...],"statusCode":400}) e o contrato da API fica inconsistente.
 */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<FastifyReply>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const corpo = exception.getResponse() as any;

      // Erros que ja vem no envelope (lancados pelos services) passam direto.
      if (corpo?.error?.code) {
        return res.status(status).send(corpo);
      }

      // ValidationPipe: message e um array de strings.
      if (Array.isArray(corpo?.message)) {
        return res.status(status).send({
          error: {
            code: 'VALIDACAO_FALHOU',
            message: 'Os dados enviados sao invalidos.',
            details: corpo.message,
          },
        });
      }

      return res.status(status).send({
        error: {
          code: this.codigoPadrao(status),
          message: corpo?.message ?? exception.message,
        },
      });
    }

    this.logger.error(exception instanceof Error ? exception.stack : String(exception));
    return res.status(HttpStatus.INTERNAL_SERVER_ERROR).send({
      error: { code: 'ERRO_INTERNO', message: 'Erro inesperado no servidor.' },
    });
  }

  private codigoPadrao(status: number): string {
    return {
      400: 'REQUISICAO_INVALIDA',
      401: 'NAO_AUTENTICADO',
      403: 'SEM_PERMISSAO',
      404: 'NAO_ENCONTRADO',
      409: 'CONFLITO',
      429: 'MUITAS_REQUISICOES',
    }[status] ?? 'ERRO';
  }
}
