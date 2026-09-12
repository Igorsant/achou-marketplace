import type { Config } from 'jest';

/**
 * Testes de integracao: sobem o AppModule de verdade contra um Postgres de
 * verdade. Nao ha mock de Prisma aqui de proposito — metade do que os ADRs
 * afirmam e sobre o banco (UNIQUE de idempotencia, decremento condicional de
 * estoque, transacao do checkout) e mock de banco nao prova nada disso.
 */
const config: Config = {
  rootDir: '..',
  testEnvironment: 'node',
  testRegex: '\\.e2e-spec\\.ts$',
  transform: { '^.+\\.ts$': ['ts-jest', { tsconfig: 'tsconfig.json' }] },
  // Um banco, um schema: suites em paralelo truncariam as tabelas umas das
  // outras. O ganho de paralelismo nao paga a instabilidade.
  maxWorkers: 1,
  // O boot do Nest + as migrations deixam o primeiro caso mais lento que o
  // padrao de 5s.
  testTimeout: 30_000,
  // O ioredis do CacheService mantem socket aberto por alguns ms depois do
  // close; sem isso o Jest reclama de handle vazando no fim da suite.
  forceExit: true,
};

export default config;
