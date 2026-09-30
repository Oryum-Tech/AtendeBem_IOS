# Matriz de paridade web → iOS

Inventário do checkout em 29/09/2026. As rotas são referências de alcance funcional; um item parcial não é paridade completa. A autenticação nativa é tratada separadamente. Nenhuma rota web foi alterada.

| Rota existente | Destino nativo | Estado |
| --- | --- | --- |
| `/agenda/nova` | Agenda | Planejado; sem interface nativa funcional nesta versão |
| `/agenda` | Agenda | Parcial: consulta por dia e confirmação; criação, remarcação, turmas e preferências pendentes |
| `/agenda/procedimento` | Agenda | Planejado; sem interface nativa funcional nesta versão |
| `/ajuda` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/artigos/arquivos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/artigos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/billing` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/centro-cirurgico` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/centro-cirurgico/tablet` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/comunicacao` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/comunidade/mensagens` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/comunidade` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/comunidade/perfil/[id]` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/configuracoes` | Mais | Parcial: conta e troca de clínica; demais configurações pendentes |
| `/contratos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/convenios` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/estoque` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/exames` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/fila` | Hoje | Parcial: leitura; chegada e início de atendimento pendentes |
| `/financeiro` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/fisio` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/fono` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/gestao` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/hospital` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/indicacoes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/lari` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/medicamentos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/notas-fiscais` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/novidades` | Mais | Implementação inicial: novidades próprias do aplicativo |
| `/nutri` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/odonto` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/orcamentos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/overview` | Hoje | Parcial: agenda e fila; outros indicadores e pendências ainda pendentes |
| `/pacientes` | Pacientes | Parcial: busca paginada, ficha, alergias recebidas e resumo de consultas; cadastro e edição pendentes |
| `/pacientes/unificacoes` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/planos-tratamento` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/portal` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/avaliacoes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/banco` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/cronograma` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/matriz` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/residentes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/validacoes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/prontuario` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/protocolos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/psico` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/receituario` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/relatorios` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/renovacoes` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/apostilas` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/atlas` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/calculadoras` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/casos/[id]` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/casos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/desempenho` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/logbook` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/plantao` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/questoes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/revisao` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/residencia/simulados` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/satisfacao` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/suporte` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/teleconsulta` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/templates` | Mais | Planejado; sem interface nativa funcional nesta versão |

## Autenticação e base

| Fluxo | Estado |
| --- | --- |
| E-mail e senha, MFA TOTP, recuperação, troca obrigatória de senha | Implementado contra contratos existentes; E2E autenticado pendente |
| Sessão Keychain, refresh único concorrente, logout local, troca de clínica | Implementado; testes locais e validação no dispositivo têm alcances diferentes |
| Cadastro, convite de equipe, login social e vinculação de contas | Planejado |
| Push, documentos, câmera, biometria e links universais | Planejado |
| iPad com sidebar/lista-detalhe | Planejado; shell atual usa navegação nativa básica |

## Ordem de entrega

1. **Validar a base:** Xcode/SDK, compilação iOS, autenticação de homologação, comparação web↔iOS, acessibilidade e navegação.
2. **Fechar o ciclo da agenda:** criar, reagendar, cancelar com motivo, chegada, fila, turmas, disponibilidade e tipos de atendimento.
3. **Concluir o atendimento:** ficha completa, vínculos, histórico longitudinal, evolução, rascunho seguro, assinatura e encerramento.
4. **Documentos e cuidado:** prescrições, exames, atestados, anexos, renovações e especialidades com todos os estados e permissões.
5. **Gestão e comunicação:** financeiro, convênios, TISS, estoque, equipe, mensagens, fiscal, relatórios e suporte.
6. **Demais jornadas:** hospital, centro cirúrgico, teleconsulta, estudos, comunidade, residência, preceptoria, LARI e configurações avançadas.
7. **Distribuição:** ícone, App Privacy, permissões justificadas, assinatura Apple, TestFlight, testes com usuários e App Store.

Cada etapa exige funcionalidades reais e validação integrada. Links para a web, telas estáticas e listas de módulos não contam como uma função nativa concluída. A capacidade completa fica no roteiro sem sobrecarregar as quatro abas principais.
