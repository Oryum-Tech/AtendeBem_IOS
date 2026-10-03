# AtendeBem iOS — plano mestre e matriz de paridade

Este documento é o contrato de entrega do aplicativo. O multirepositório web e os serviços de produção são fontes somente leitura. Uma linha só muda para **Concluída** quando contrato, permissão, UX, erros e testes estiverem cobertos.

## Definição de pronto

- A rota e o payload foram confirmados no OpenAPI ou na implementação web.
- A tela respeita clínica ativa, papel, recurso contratado e autorização do servidor.
- Há estados de carregamento, vazio, erro, nova tentativa e concorrência.
- Dados clínicos e credenciais não são persistidos fora dos mecanismos aprovados.
- Dynamic Type, VoiceOver, contraste, modo escuro e alvos de toque foram verificados.
- Existem testes unitários e/ou de UI proporcionais ao risco.
- Build Debug e Release, archive e validação de distribuição passam sem erro.

## Estado atual

| Domínio | Contratos principais | Estado iOS | Próximo aceite |
|---|---|---|---|
| Identidade | `/auth/*`, `/me`, `/clinicas-do-usuario`, `/usuarios/*` | Parcial: login, MFA, sessão, troca de clínica e senha | Gestão de equipe, convites, MFA do perfil e testes de refresh concorrente |
| Início e navegação | Preferências pessoais e permissões | Parcial: abas, atalhos e blocos por usuário/clínica | Sincronizar preferências com servidor quando o contrato web for confirmado |
| Agenda | `/agendamentos`, fila, bloqueios, turmas, tipos e disponibilidade | Parcial: leitura, detalhe, confirmação, fila e seletores Dia/Semana/Mês/Lista | Grades completas, catálogo de cores do servidor, criar/editar/remarcar/check-in/iniciar, bloqueios e turmas |
| Pacientes | `/pacientes/*`, alergias, equipe, consentimentos, LGPD e unificação | Parcial: lista, busca e detalhe | CRUD, alergias, consentimentos, anexos, equipe, duplicidade, arquivamento e exportação LGPD |
| Prontuário | Evoluções, anexos, ficha, avaliações, antecedentes e fichas de especialidade | Parcial: histórico e nova evolução SOAP | Rascunho, assinatura, anexos, PDF, modelos, antecedentes e formulários por especialidade |
| Receituário | Receitas, atestados, PDFs, envio, posologias, preferências e renovações | Parcial: criação e assinatura inicial | Listas, PDF/compartilhamento, envio, certificados, favoritos, preferências e renovação |
| Exames | Solicitação, assinatura, PDF, envio e resultados | Parcial: solicitação e assinatura | Listas, PDF, envio, upload/visualização de resultados e exames externos |
| Teleconsulta | Salas, token, fila e eventos | Parcial: cria sala e abre fluxo web seguro | SDK nativo, câmera/microfone, sala de espera, reconexão, eventos e testes de dispositivo |
| LARI | Conversas SSE, SOAP, CID/TUSS, interações e resumos | Parcial: sugestão SOAP/CID | Chat completo com streaming, histórico, TUSS, interações e resumos com avisos clínicos |
| Financeiro | Lançamentos, resumo, fluxo, metas, tributos, fiscal, contratos, PIX e documentos | Parcial: resumo e lançamentos de leitura | CRUD, relatórios, caixa, cobranças, metas, fiscal, orçamentos, contratos, honorários e documentos |
| TISS | TUSS, operadoras, guias, lotes, glosas e laudos | Não iniciado | Jornada completa conforme papel e feature flag |
| Planos terapêuticos | Planos, sessões, pacotes, exercícios e treinos | Não iniciado | Fluxos por fisioterapia e demais especialidades |
| Estudos/Residência | Questões, simulados, revisão, casos, atlas, apostilas, logbook e desempenho | Não iniciado | Dashboard adaptado a residente/preceptor e jornadas de estudo |
| Comunidade | Feed, publicações, comentários, reações e moderação | Não iniciado | Confirmar contratos diretamente no serviço e implementar feed seguro |
| Comunicação/equipe | Inbox, conversas, instâncias, notificações e aparelhos | Não iniciado | Caixa da equipe, push, preferências e registro do aparelho |
| Gestão/Analytics | Indicadores, demanda, geografia, faltas, rankings e equipe | Não iniciado | Dashboard por papel, filtros e relatórios acessíveis |
| Hospital | Internações, leitos, cirurgia, prescrições, OPME, perioperatório e CCIH | Não iniciado | Dividir em jornadas hospitalares com controles de alto risco |
| Estoque e integrações | Estoque, importações, CEP/CNPJ/DDD/feriados | Não iniciado | Confirmar contratos e implementar somente para perfis autorizados |
| Billing e planos comerciais | Assinaturas, planos e cobrança da clínica | Não iniciado | Área do gestor, sem expor rotas internas/admin |

## Sequência de implementação

1. Fundação, testes e configuração Release.
2. Agenda completa e catálogo de tipos/cores.
3. Paciente, consulta e prontuário completos.
4. Receitas, documentos, exames e teleconsulta nativa.
5. Perfis e fichas de especialidade.
6. Comunicação, notificações e gestão da equipe.
7. Financeiro, TISS, faturamento, estoque e relatórios.
8. LARI, Estudos/Residência e Comunidade.
9. Hospital e jornadas de maior risco.
10. Auditorias finais, archive, App Store Connect e revisão humana.

## Bloqueios que impedem a declaração “100%” hoje

- O scheme do aplicativo não contém targets de unit tests ou UI tests; o pacote possui testes, mas não está ligado ao plano ativo.
- Teleconsulta ainda não possui mídia nativa nem permissões de câmera/microfone.
- Não há privacy manifest no target.
- Configurações de segurança e Release ainda precisam da etapa de aprovação prevista na auditoria.
- Funcionalidades dependentes de contas, certificados, PIX, push, câmera e ambientes reais exigem credenciais/dispositivos de homologação e validação humana.
