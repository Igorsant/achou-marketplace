/**
 * Normaliza o termo de busca para uso como chave de cache.
 *
 * A busca no Postgres ja e insensivel a caixa (to_tsvector) e a acento
 * (f_unaccent), entao "tenis", "Tenis", "TENIS" e "tênis" devolvem exatamente
 * o mesmo resultado. Sem normalizar, cada variacao gerava uma chave de cache
 * distinta apontando para conteudo identico -- desperdicio de memoria, miss
 * desnecessario e invalidacao por SCAN mais cara.
 *
 * Devolve `undefined` para termo vazio ou so com espacos, o que faz a busca
 * cair na vitrine em vez de montar um tsquery vazio.
 */
export function normalizarTermoBusca(termo?: string): string | undefined {
  if (!termo) return undefined;

  const normalizado = termo
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // remove marcas de acentuacao
    .toLowerCase()
    .replace(/\s+/g, ' ')            // colapsa espacos repetidos
    .trim();

  return normalizado.length > 0 ? normalizado : undefined;
}
