import { FastifyInstance } from 'fastify';
import { Histogram } from 'prom-client';

// O _count do histograma ja e o contador de requisicoes: nao precisa de um
// Counter a parte para taxa de requisicao e de erro.
const duracao = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duracao das requisicoes HTTP da API',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

/**
 * Hook no Fastify em vez de interceptor do Nest: interceptor roda depois dos
 * guards, entao 401, 403 e 429 nunca passariam por ele -- e sao justamente as
 * respostas que mostram ataque e rate limit em acao.
 *
 * Precisa ser chamado antes do listen(), para o hook valer em todas as rotas.
 */
export function instrumentarHttp(fastify: FastifyInstance) {
  fastify.addHook('onResponse', async (request, reply) => {
    // Template da rota (/v1/products/:id), nunca a URL crua: cada id viraria
    // uma serie nova no Prometheus. Rota inexistente cai num rotulo unico,
    // senao um scanner varrendo URLs aleatorias faz o mesmo estrago.
    const route = request.routeOptions.url ?? 'nao_mapeada';
    duracao.observe(
      { method: request.method, route, status_code: String(reply.statusCode) },
      reply.elapsedTime / 1000,
    );
  });
}
