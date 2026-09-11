# Observabilidade — Achou! Marketplace

Métricas com **Prometheus** e visualização com **Grafana**, cobrindo a API, o
cache e o fluxo assíncrono (outbox → fila → notificação). É a caixa
"OBSERVABILIDADE" do diagrama do [README](../README.md): a CPU medida aqui é o
sinal que dispara o auto-scaling em 70%.

```
 api  :9464/metrics ─┐
                     ├──► Prometheus :9090 ──► Grafana :3002
 worker :9465/metrics┘      (scrape 5s,          (dashboard
                            regras de alerta)     provisionado)
```

| O quê | Onde |
|---|---|
| Dashboard | http://localhost:3002 — login `admin` / `achou_dev`, abre direto no dashboard |
| Prometheus | http://localhost:9090 — alvos em `/targets`, alertas em `/alerts` |
| Config | [`observability/`](../observability/) — tudo versionado, nada configurado à mão |

Sobe junto com o resto: `docker compose up -d --build`.

---

## 1. Catálogo de métricas

### API

| Métrica | Tipo | Rótulos | Para quê |
|---|---|---|---|
| `http_request_duration_seconds` | histograma | `method`, `route`, `status_code` | Vazão, latência (p95) e taxa de erro por rota. O `_count` é o contador de requisições |
| `achou_cache_consultas_total` | contador | `prefixo`, `resultado` | Hit rate do Redis. `resultado`: `hit` · `miss` · `indisponivel` · `erro` |

### Worker

| Métrica | Tipo | Rótulos | Para quê |
|---|---|---|---|
| `achou_outbox_pendentes` | gauge | — | Eventos ainda não publicados na fila |
| `achou_outbox_atraso_segundos` | gauge | — | Idade do pendente mais antigo (0 = nada pendente) |
| `achou_outbox_publicados_total` | contador | `tipo` | Eventos publicados, só contados após o commit |
| `achou_outbox_falhas_total` | contador | — | Ciclos do relay que falharam (eventos continuam pendentes) |
| `achou_fila_jobs` | gauge | `fila`, `estado` | Jobs em `waiting` · `active` · `delayed` · `failed` |
| `achou_notificacoes_total` | contador | `tipo`, `resultado` | `enviada` · `duplicada` · `sem_template` · `falha` (por tentativa) · `esgotada` |
| `achou_notificacao_envio_segundos` | histograma | `resultado` | Latência do provedor de e-mail (`ok` / `erro`) |
| `achou_notificacao_latencia_segundos` | histograma | `tipo` | Do evento ocorrer até o e-mail sair — o atraso que o usuário percebe |

### Ambos os processos

Métricas padrão do `prom-client`: `process_cpu_seconds_total`,
`nodejs_eventloop_lag_p99_seconds`, `nodejs_heap_size_used_bytes`, GC e outras.
O rótulo `job` (`api` / `worker`) vem da config do Prometheus.

---

## 2. Dashboard

Arquivo: [`observability/grafana/dashboards/achou-marketplace.json`](../observability/grafana/dashboards/achou-marketplace.json)

| Seção | Painéis |
|---|---|
| **Visão geral** | Requisições/s · p95 · % de 5xx · cache hit rate · CPU da API · outbox pendente · alertas disparados (+ tabela) |
| **API** | Req/s por rota · p95 por rota (linha em 500ms) · respostas por status · leituras de cache por resultado |
| **Processos Node** | CPU por processo (linha no gatilho de 70%) · event loop lag p99 · heap |
| **Assíncrono** | Outbox pendente e atraso (linha em 60s) · jobs por estado · notificações/min · latência até o e-mail · latência do provedor |

O dashboard é **provisionado e somente leitura** na interface: o JSON no git é a
fonte da verdade. Para alterar, edite pela interface num dashboard copiado
(*Save as*), exporte o JSON (*Share → Export*) e substitua o arquivo.

---

## 3. Alertas

Regras em [`observability/prometheus/alertas.yml`](../observability/prometheus/alertas.yml),
validadas com `promtool`. Não há Alertmanager no ambiente local: os alertas
aparecem em http://localhost:9090/alerts e no painel "Alertas disparados".

| Alerta | Condição | Por quê |
|---|---|---|
| `AlvoForaDoAr` | `up == 0` por 1 min | API ou worker não respondem ao scrape |
| `CpuNoGatilhoDeEscala` | CPU da API > 70% de um núcleo por 2 min | O gatilho de auto-scaling do README |
| `TaxaDeErro5xxAlta` | > 5% de 5xx por 5 min | |
| `LatenciaP95Alta` | p95 de alguma rota > 500ms por 5 min | |
| `CacheIndisponivel` | leituras com `indisponivel`/`erro` por 1 min | O cache degrada sem erro: sem este alerta, a queda do Redis passaria despercebida |
| `OutboxAtrasado` | evento pendente há mais de 60s | Relay ou fila parados |
| `NotificacoesEsgotadas` | alguma notificação esgotou as 5 tentativas em 15 min | Precisa de `scripts/fila.sh retry` |

---

## 4. Decisões

**Porta de métricas separada.** `/metrics` não existe na porta pública (3001):
API em `9464`, worker em `9465`, nenhuma publicada no host. Métrica revela rotas,
volume e taxa de erro — não deve passar pelo gateway. Também é o único jeito de o
worker, que não tem servidor HTTP, ser raspado.

**Hook do Fastify, não interceptor do Nest.** Interceptores rodam depois dos
guards, então 401, 403 e 429 nunca seriam medidos — justamente as respostas que
mostram ataque e rate limit em ação. Verificado: 401 sem token, 429 do
throttler e 404 aparecem no painel "Respostas por status".

**Template da rota, nunca a URL.** `route="/v1/products/:id"`, não o UUID — cada
id viraria uma série nova e a cardinalidade explode. Rotas inexistentes caem num
rótulo único, `nao_mapeada`: 15 URLs aleatórias viraram 1 série no teste.

**CPU como fração de um núcleo.** `rate(process_cpu_seconds_total[1m])` mede
segundos de CPU por segundo. O Node executa JavaScript numa thread só, então 70%
de *um* núcleo é o limite real do processo, independente do tamanho da máquina.
O event loop lag fica ao lado porque denuncia um processo saturado antes de a
CPU chegar ao limite.

**Estado lido no scrape, não mantido em memória.** Outbox e fila são
compartilhados entre réplicas do worker; um contador local só enxergaria o que
a própria réplica fez. Os gauges consultam Postgres e Redis a cada scrape.

**Coleta com prazo, e falha nunca vira zero.** Cada leitura do scrape tem prazo
de 2s. Com o Redis fora, `achou_fila_jobs` some da resposta e os gauges do
outbox viram `NaN` se o Postgres falhar — "0 pendentes" com o banco fora seria
mentira. O scrape em si continua respondendo: verificado com o Redis parado, o
worker seguiu `up` com scrape em 5ms.

**Séries de baixo volume nascem em zero.** Uma série que aparece no primeiro
scrape já valendo 1 não mostra incremento para o `rate()`. Descoberto no teste:
uma rajada de requisições coube entre dois scrapes e todo `rate()` deu `NaN`.
Para o tráfego HTTP isso só perde o primeiro scrape; para notificações, o
alerta `NotificacoesEsgotadas` perderia justamente a primeira falha. Por isso
as combinações conhecidas de `tipo × resultado` são inicializadas com 0.

---

## 5. Como testar

```bash
# alvos devem estar "up"
curl -s localhost:9090/api/v1/targets | python3 -c \
  "import sys,json; [print(t['labels']['job'], t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"

# metricas cruas, de dentro do container. 127.0.0.1 e nao localhost: no Alpine,
# localhost resolve primeiro para ::1 e o servidor escuta so em IPv4
docker exec achou_api wget -qO- 127.0.0.1:9464/metrics | grep achou_
docker exec achou_worker wget -qO- 127.0.0.1:9465/metrics | grep achou_

# gerar trafego (o rate limit e 100 req/min por IP)
for i in $(seq 1 60); do curl -s -o /dev/null 'localhost:3001/v1/products?q=tenis'; sleep 0.7; done
```

**Ver um alerta disparar:** `docker compose stop redis`, faça algumas buscas por
~2 minutos e `CacheIndisponivel` passa de `pending` para `firing`. A API continua
respondendo `200`. `docker compose start redis` para voltar.

**Recarregar regras sem reiniciar** depois de editar `alertas.yml`:

```bash
curl -X POST localhost:9090/-/reload
```

> O Grafana 12.1 loga `plugin table is already registered` ao subir. É da própria
> imagem (aparece também num container limpo, sem nenhuma config) e não afeta os
> painéis.

---

## 6. Próximos passos

- **Exporters de infraestrutura:** `redis_exporter` e `postgres_exporter` para
  memória do Redis, conexões e queries lentas do Postgres.
- **Alertmanager** para rotear alertas (Slack, e-mail) em vez de só exibi-los.
- **Service discovery:** com réplicas no Kubernetes, trocar `static_configs` por
  `kubernetes_sd_configs`; cada pod vira um alvo com seu `instance`.
- **Throttler no Redis:** o rate limit guarda contadores em memória, então com N
  réplicas o limite efetivo vira N × 100 req/min (já anotado no `app.module.ts`).
