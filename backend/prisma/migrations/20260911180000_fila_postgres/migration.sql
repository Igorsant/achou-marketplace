-- Fila do ambiente local (FILA_DRIVER=postgres). Em producao a fila e a
-- OCI Queue e esta tabela fica vazia.
--
-- id = id do evento do outbox: republicar o mesmo evento nao duplica.
-- visivel_em faz o papel da visibilidade da OCI Queue: a mensagem entregue
-- fica invisivel ate ser apagada (sucesso) ou reaparece (worker morreu, ou
-- retry agendado com backoff).
CREATE TABLE "fila_mensagens" (
    "id" UUID NOT NULL,
    "tipo" TEXT NOT NULL,
    "conteudo" JSONB NOT NULL,
    "tentativas" INTEGER NOT NULL DEFAULT 0,
    "visivel_em" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "morta" BOOLEAN NOT NULL DEFAULT false,
    "ultimo_erro" TEXT,
    "criada_em" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "fila_mensagens_pkey" PRIMARY KEY ("id")
);

-- Indice PARCIAL: so as mensagens vivas entram. A consulta do consumidor
-- (NOT morta AND visivel_em <= now()) continua rapida mesmo com a
-- dead-letter acumulando. O Prisma nao introspecta indice parcial, entao ele
-- nao aparece no schema.prisma e nao gera drift.
CREATE INDEX "idx_fila_visiveis" ON "fila_mensagens" ("visivel_em")
    WHERE NOT "morta";
