-- Busca insensivel a acento.
--
-- Problema: 'tenis' gera o lexema 'ten' e 'tênis' gera 'tên'. Eles nao casam,
-- entao quem digita sem acento (a maioria) nao encontra o produto.
--
-- Solucao: normalizar acentos ANTES do to_tsvector, nos dois lados -- no
-- documento indexado e no termo de busca.

CREATE EXTENSION IF NOT EXISTS unaccent;

-- unaccent() e STABLE, nao IMMUTABLE, porque depende do dicionario carregado.
-- Coluna gerada exige IMMUTABLE, entao envelopamos fixando o dicionario
-- explicitamente, o que torna o resultado deterministico.
CREATE OR REPLACE FUNCTION f_unaccent(text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE STRICT
AS $$
  SELECT public.unaccent('public.unaccent', $1)
$$;

-- Nao da para ALTER numa expressao de coluna gerada: precisa dropar e recriar.
-- O indice GIN cai junto com a coluna, entao e recriado logo abaixo.
ALTER TABLE "products" DROP COLUMN "search_vector";

ALTER TABLE "products" ADD COLUMN "search_vector" tsvector
GENERATED ALWAYS AS (
    setweight(to_tsvector('portuguese', f_unaccent(coalesce("title", ''))), 'A') ||
    setweight(to_tsvector('portuguese', f_unaccent(coalesce("description", ''))), 'B')
) STORED;

CREATE INDEX "idx_products_search" ON "products" USING GIN ("search_vector");
