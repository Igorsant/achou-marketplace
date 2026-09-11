# Deploy — Oracle Cloud (Always Free)

O Achou! roda num cluster Kubernetes gerenciado (OKE) da Oracle Cloud, dentro
dos limites do **Always Free**: custo zero, desde que nada saia das travas
descritas abaixo. Serve à apresentação do trabalho — a ideia é subir antes,
apresentar e destruir depois.

```
                internet
                   │ HTTP :80
        ┌──────────▼───────────┐
        │ Network Load Balancer│  (Always Free; preserva o IP do cliente)
        └──────────┬───────────┘
   ┌───────────────┼──────────────────────────────────────────┐
   │ OKE Basic     │ NodePort 30080         2 nodes Ampere A1 │
   │        ┌──────▼──────┐                 (1 OCPU, 6 GB cada)│
   │        │   Traefik   │ Gateway "publico"                  │
   │        └──────┬──────┘                                    │
   │        ┌──────▼──────┐   ┌────────┐   ┌──────────────┐    │
   │        │ api (2..3)  │   │ worker │   │  Prometheus  │    │
   │        └──┬───────┬──┘   └─┬────┬─┘   │  + Grafana   │    │
   │   ┌───────▼──┐ ┌──▼────────▼┐   │     └──────────────┘    │
   │   │ Postgres │ │   Redis    │◄──┘      KEDA escala api     │
   │   │ (50 GB)  │ │ cache+fila │          (CPU) e worker (fila)│
   │   └──────────┘ └────────────┘                              │
   └────────────────────────────────────────────────────────────┘
```

---

## 1. Custo: o que cabe no Always Free

| Recurso | Usado | Limite Always Free |
|---|---|---|
| Control plane do OKE | Basic | Basic é gratuito (Enhanced custa US$ 0,10/h) |
| Ampere A1 | 2 OCPUs, 12 GB | 1.500 OCPU-h + 9.000 GB-h/mês = 2 OCPUs e 12 GB contínuos |
| Block volume | 2 × 50 GB (boot) + 50 GB (Postgres) = 150 GB | 200 GB |
| Load balancer | 1 Network Load Balancer | 1 NLB |
| Registro (OCIR) | ~250 MB de imagens | 20 GB de Object Storage |
| Rede | 1 VCN, Internet Gateway | 2 VCNs |

> **Atenção a tutoriais antigos:** muitos citam 4 OCPUs e 24 GB de A1. A
> documentação atual da Oracle diz 1.500 OCPU-hora e 9.000 GB-hora por mês —
> **2 OCPUs e 12 GB**. Acima disso, conta PAYG é cobrada.

**Travas contra custo acidental:**

- `infra/oci/1-cluster/variables.tf` recusa no `plan` qualquer combinação que
  passe de 2 OCPUs, 12 GB ou 200 GB de disco.
- Com `email_alerta_custo` preenchido, um orçamento de US$ 1 manda e-mail no
  **primeiro centavo** gasto no compartimento.
- Tudo fica num compartimento próprio (`achou`), apagado no `destruir`.

---

## 2. Pré-requisitos (uma vez só)

1. **Conta OCI** e sua **home region** (Perfil → Tenancy). Recursos Always Free
   só existem nela.
2. **Chave de API:** Perfil → Chaves de API → Adicionar chave → Gerar par de
   chaves → baixar a privada → Adicionar. O console mostra um trecho de
   configuração: salve em `~/.oci/config` e ajuste `key_file` para o caminho da
   chave baixada (`chmod 600` nela).
3. **Ferramentas:**
   ```bash
   brew install oci-cli terraform kubectl   # docker: Docker Desktop
   oci iam region list --output table       # testa a chave de API
   ```
   A CLI da OCI é obrigatória: o OKE autentica o `kubectl` com um token gerado
   por ela a cada comando.

---

## 3. Passo a passo

```bash
# 1. variaveis (OCIDs estao no ~/.oci/config)
cp infra/oci/1-cluster/terraform.tfvars.example infra/oci/1-cluster/terraform.tfvars
#    edite: tenancy_ocid, usuario_ocid, regiao; recomendado: ips_admin e email_alerta_custo

# 2. infraestrutura: rede, cluster, registro e plataforma (~15 min)
scripts/oci.sh subir

# 3. aplicacao: build ARM, push para o OCIR, migration e rollout (~5 min)
scripts/oci.sh publicar v1

# 4. usar
curl "$(scripts/oci.sh url)/health/live"
curl "$(scripts/oci.sh url)/v1/products"
scripts/oci.sh grafana          # http://localhost:3003
scripts/oci.sh status

# 5. depois da apresentacao
scripts/oci.sh destruir
```

Cada `terraform apply`/`destroy` mostra o plano e **pede confirmação**.

O `kubectl` usa `infra/oci/kubeconfig` (gerado pelo `subir`, fora do git). Para
comandos manuais: `export KUBECONFIG=infra/oci/kubeconfig`.

---

## 4. Estrutura

```
infra/oci/
├── 1-cluster/        provider oci: compartimento, VCN, security lists, OKE,
│                     node pool A1, OCIR, token do registro, orcamento
└── 2-plataforma/     providers helm/kubernetes: metrics-server, KEDA,
    ├── values/       Traefik (Gateway API + NLB), Prometheus/Grafana,
    └── ...           namespaces, segredos e pull secret do OCIR
deploy/k8s/overlays/oci/   ajustes da aplicacao para 2 OCPUs + Postgres/Redis
scripts/oci.sh             ciclo de vida completo
```

**Por que duas etapas:** os providers `helm` e `kubernetes` precisam de um
cluster existente na hora do `plan`. Numa etapa só, o primeiro `apply` não teria
o que consultar. A etapa 2 lê os outputs da 1 pelo state local.

---

## 5. Contrato com o Terraform

O que os manifests de `deploy/k8s/` esperam encontrar no cluster:

| Item | Quem cria | Onde |
|---|---|---|
| Secret `achou-secrets` (`DATABASE_URL`, `REDIS_CACHE_URL`, `REDIS_FILA_URL`, `JWT_SECRET`) | Terraform | `2-plataforma/aplicacao.tf` |
| Secret `credenciais` (senhas do Postgres e do Redis) | Terraform | idem |
| Pull secret `ocir` na ServiceAccount default | Terraform | idem |
| Gateway `publico` no namespace `gateway`, aceitando rotas de `achou` | Traefik via Terraform | `2-plataforma/values/traefik.yaml` |
| Prometheus em `kube-prometheus-stack-prometheus.monitoring.svc` | Terraform | `2-plataforma/plataforma.tf` |
| Descoberta de ServiceMonitor/PrometheusRule em qualquer namespace | Terraform | `values/monitoramento.yaml` |
| KEDA e metrics-server | Terraform | `plataforma.tf` |

Senhas são aleatórias (`random_password`) e ficam só no state do Terraform e
nos Secrets — nunca no git.

---

## 6. Decisões e concessões

| Decisão | Motivo | Concessão |
|---|---|---|
| **OKE Basic** | Control plane gratuito | Sem SLA nem add-ons gerenciados |
| **Workers em subnet pública** | NAT/Service Gateway em conta free tier é incerto; IGW funciona sempre | Nodes têm IP público (security list libera só o necessário) |
| **Network Load Balancer** | Gratuito e sem o teto de 10 Mbps do LB "flexible" gratuito | Um só por conta: Grafana fica por port-forward |
| **Preservar IP do cliente** | Rate limit por usuário real | NodePort 30080 aberto à internet nos workers |
| **Postgres e Redis no cluster** | Serviços gerenciados não são Always Free | Sem backup nem failover; um node caindo derruba o banco |
| **Um Redis para cache e fila** | Memória | Política `noeviction` (a da fila); cache cheio falha e cai no Postgres |
| **Só HTTP** | HTTPS exige domínio e certificado | Tráfego sem criptografia na demo |
| **Prometheus enxuto** | A stack completa não coube nem no cluster local | Sem dashboards/alertas padrão do chart, só os do projeto |

---

## 7. Riscos para o dia da apresentação

- **"Out of host capacity" no A1:** falta de ARM na região é comum. Tente outro
  `indice_ad`; se persistir, fazer upgrade da conta para PAYG costuma resolver e
  continua gratuito dentro do Always Free (deixe o `email_alerta_custo` ligado).
- **Suba na véspera**, não na hora: o primeiro `subir` + `publicar` leva uns 20
  minutos e depende de capacidade da Oracle.
- **Recuperação de instâncias ociosas:** a Oracle pode reclamar A1 com CPU, rede
  e memória abaixo de 20% por 7 dias. Para alguns dias de uso, não é problema.
- **Limite de 2 tokens de autenticação por usuário:** o Terraform cria um. Se
  você já tiver dois, apague um no console antes do `subir`.
- **Pods `Pending` por CPU:** use `nodes = 1`, `ocpus_por_node = 2`,
  `memoria_por_node_gb = 12` — um node só gasta menos com pods de sistema.

---

## 8. O que foi verificado

| Verificação | Resultado |
|---|---|
| `terraform validate` nas duas etapas (schemas reais: oci 9.1, helm 3.3, kubernetes 3.2) | ✅ |
| `helm template` do Traefik, KEDA e kube-prometheus-stack com os values do projeto | ✅ Gateway, Service NLB e NodePort conferidos no YAML gerado |
| Render do overlay `oci` com kustomize | ✅ |
| Manifests da aplicação num cluster kind (migration, rollout sem erro, rate limit, KEDA) | ✅ antes, no overlay `local` |
| **`terraform apply` na OCI** | ⬜ **não executado** — exige credenciais da conta |
| Escala da API por CPU sob carga | ⬜ não validado |

Limites do Always Free, regras de rede do OKE e anotações do NLB foram
conferidos na documentação da Oracle em setembro de 2026.
