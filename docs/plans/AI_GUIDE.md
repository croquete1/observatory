# AI Contribution Guide — Observatório de Integridade

Este documento define as regras obrigatórias para qualquer contribuição assistida por IA (Codex, ChatGPT, etc.).

## 1. Princípios Arquiteturais Invioláveis

### Multi-país por defeito
- Todas as entidades e contratos são scoped por `country_code`.
- Unicidade:
  - Entity: (tax_identifier, country_code)
  - Contract: (external_id, country_code)

### Snapshot semantics
- Full ingestion é sempre snapshot completo (page=1).
- `last_success_page` apenas para recovery dentro do mesmo run_id.
- Nunca implementar ingestão incremental por offset.

### Idempotência obrigatória
- Persistência via bulk `upsert_all`.
- Índice único obrigatório em contracts(external_id, country_code).
- Reexecutar ingestão nunca pode duplicar dados.

### Circuit breaker
- Sempre por DataSource.
- TTL obrigatório.
- Reset no primeiro sucesso.

---

## 2. Regras por Tipo de Issue

### type: data
- Nada de N+1.
- Nada de loops com save!.
- Bulk operations obrigatórias.
- Sem HTTP real nos testes.

### type: flag
- Determinística.
- Explicável.
- Testes para disparo e não disparo.
- Nunca alterar contratos na execução da flag.

### type: ui
- Evitar N+1.
- Manter contraste acessível.
- SSR-first (Hotwire).

---

## 3. Requisitos de Testes

- 100% de cobertura de linha.
- Sem pedidos HTTP reais.
- Testes de fronteira obrigatórios.
- Teste de idempotência sempre que há ingestão.

---

## 4. Proibido

- Incremental ingest baseado em offset.
- Remover índices únicos.
- Quebrar compatibilidade com Solid Queue.
- Reduzir cobertura de testes.

---

## 5. Fluxo Padrão para Fechar Issues

1. Implementar código.
2. Garantir idempotência.
3. Garantir cobertura 100%.
4. Atualizar README se for alteração operacional.
5. PR com "Closes #<issue>".
6. Merge apenas com CI verde.
