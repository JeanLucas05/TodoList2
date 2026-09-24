# Prompt para o Agente de Codificação

Cole este prompt (junto com o arquivo de especificação anexado, ex: `SPEC.md`) na primeira mensagem para o seu agente (Claude Code, Cursor, etc.).

---

Você é um agente de codificação autônomo responsável por implementar, do zero, um aplicativo mobile de lista de tarefas ("to-do app") em **Flutter**, seguindo rigorosamente a especificação técnica anexada neste repositório em `SPEC.md`.

## Regras gerais de trabalho

1. Leia `SPEC.md` por completo antes de escrever qualquer código. Trate-o como a fonte de verdade para requisitos funcionais. Este prompt define apenas *como* você deve trabalhar, não *o que* construir — o que construir está em `SPEC.md`.
2. Trabalhe de forma incremental e demonstrável: cada etapa concluída deve deixar o projeto em um estado que builda e roda, sempre que possível.
3. Antes de considerar qualquer funcionalidade "pronta", **compile e execute o projeto** (ou rode os testes automatizados relevantes) para validar. Não assuma que o código gerado está correto só porque parece sintaticamente válido.
4. Sempre que encontrar um erro de build, exceção em runtime, ou comportamento inesperado, investigue a causa, registre o problema e a tentativa de correção no `BUILD_LOG.md` (ver seção abaixo), mesmo que a primeira tentativa de correção falhe.
5. Não reescreva o histórico do `BUILD_LOG.md` para "limpar" decisões erradas anteriores. Se uma decisão tomada antes se mostrar equivocada, mantenha a entrada original e adicione uma nova entrada corrigindo o rumo.
6. Se alguma parte da especificação for ambígua ou permitir mais de uma abordagem válida, escolha a abordagem mais simples e adequada a um projeto educacional pequeno, documente a escolha e siga em frente — não pare para pedir confirmação a menos que seja estritamente necessário.

## Stack técnica

- **Framework:** Flutter (Dart), voltado a mobile (Android como alvo mínimo; iOS se viável no ambiente).
- **Persistência:** SQLite local (ex.: pacotes `sqflite` ou `drift`/`sqflite_common_ffi` conforme sua avaliação). Justifique a escolha no `BUILD_LOG.md`.
- **Notificações locais:** um pacote de notificações locais agendadas (ex.: `flutter_local_notifications`), sem depender de servidor push remoto.
- Escolha livremente arquitetura (MVVM, repository pattern, feature-based, etc.) e gerenciamento de estado (Provider, Riverpod, Bloc, setState puro, etc.), desde que documentado e proporcional ao tamanho do projeto.

## Documentação obrigatória: `BUILD_LOG.md`

Crie `BUILD_LOG.md` **antes** de escrever qualquer código, e atualize-o continuamente — nunca apenas no final.

Para cada interação/decisão/implementação/bug relevante, adicione uma entrada nova contendo:

- **Prompt / Request** — o pedido do usuário que motivou a mudança (preserve a redação original sempre que possível).
- **Decision Summary** — o que foi decidido, bibliotecas/APIs escolhidas, decisões arquiteturais, suposições feitas, alternativas consideradas (resumo conciso, sem expor cadeia de raciocínio interna).
- **Actions Performed** — arquivos criados/modificados, dependências instaladas, mudanças de schema, navegação adicionada, etc.
- **Result** — sucesso, falha de build, funcionalidade parcial, erro em runtime, etc.
- **Problems / Errors** — erros de compilação, erros em runtime, suposições incorretas, bugs.
- **Fixes Attempted** — tentativas de correção, incluindo as que falharam.
- **Current Status** — `Completed` / `Partially completed` / `Broken` / `Needs testing` / `Blocked`.

## Ordem sugerida de implementação

1. Inicializar o projeto Flutter.
2. Criar `BUILD_LOG.md`.
3. Criar navegação básica entre as 3 telas exigidas.
4. Definir os modelos de dados (Task, Category).
5. Configurar SQLite (schema, DAO/repositório).
6. Implementar CRUD de tarefas.
7. Implementar CRUD de categorias.
8. Conectar a UI aos dados persistentes.
9. Implementar filtragem (status e categoria).
10. Implementar datas/horas de vencimento.
11. Implementar notificações locais agendadas.
12. Tratar permissões de notificação.
13. Testar persistência (fechar/reabrir app).
14. Testar o comportamento das notificações.
15. Revisar e limpar o projeto.

Você pode alterar essa ordem se justificar a mudança no `BUILD_LOG.md`.

## Commits

Se for solicitado a criar commits Git, mantenha um histórico significativo: cada commit deve representar um passo de implementação, correção ou decisão relevante — evite commits genéricos como "update" ou "wip" sem contexto.

## Critérios de aceitação

Ao final, verifique item a item a lista de "Functional Acceptance Criteria" da especificação (`SPEC.md`, seção 20) e reporte no `BUILD_LOG.md` quais itens estão concluídos, parciais ou pendentes.

## Entrega final

Quando a implementação estiver completa (ou no limite do que for viável no tempo disponível):

1. Revise os critérios de aceitação.
2. Identifique funcionalidades incompletas ou parcialmente funcionais.
3. Teste os fluxos mais importantes do app.
4. Atualize o `BUILD_LOG.md` com uma entrada final.
5. Produza um resumo final conciso contendo: arquitetura usada, dependências importantes, estratégia de SQLite, estratégia de gerenciamento de estado, estratégia de navegação, estratégia de notificações, limitações conhecidas e bugs remanescentes.

Não remova nem reescreva entradas anteriores do `BUILD_LOG.md`.