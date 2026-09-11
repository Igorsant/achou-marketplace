import { Logger } from '@nestjs/common';
import { createServer } from 'node:http';
import { collectDefaultMetrics, register } from 'prom-client';

/**
 * Expoe /metrics numa porta propria, separada da porta publica da API.
 * Metrica revela rotas, volume e taxa de erro: nao deve sair pelo gateway.
 * So o Prometheus, dentro da rede interna, alcanca esta porta.
 *
 * Tambem e o unico jeito de o worker ser raspado: ele nao tem servidor HTTP.
 */
export function iniciarServidorDeMetricas(porta: number) {
  // CPU, memoria, event loop lag e GC do processo. A CPU e o sinal do
  // auto-scaling; o event loop lag e o que denuncia um Node saturado antes
  // da CPU chegar no limite.
  collectDefaultMetrics();

  const servidor = createServer(async (req, res) => {
    // Liveness do worker, que nao tem outro servidor HTTP. Nao reaproveita
    // /metrics porque o scrape consulta Postgres e Redis.
    if (req.url === '/live') {
      res.writeHead(200).end('ok');
      return;
    }
    if (req.url !== '/metrics') {
      res.writeHead(404).end();
      return;
    }
    try {
      const corpo = await register.metrics();
      res.writeHead(200, { 'Content-Type': register.contentType }).end(corpo);
    } catch (err) {
      res.writeHead(500).end((err as Error).message);
    }
  });

  // unref: sozinho, o servidor de metricas nao segura o processo no shutdown.
  servidor.unref();
  servidor.listen(porta, '0.0.0.0', () => Logger.log(`Metricas em :${porta}/metrics`, 'Metricas'));
}
