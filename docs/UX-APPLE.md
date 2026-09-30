# AtendeBem iOS — estratégia de experiência

Decisões de 29/09/2026. Público inicial: profissionais de saúde, recepção e gestão de clínicas. O objetivo final é cobrir as funções existentes no AtendeBem com interface nativa. Esta especificação é uma referência de implementação; a conformidade ainda precisa de auditoria em dispositivos reais.

## Princípio de produto

O trabalho de quem cuida vem primeiro. A interface deve reduzir decisões desnecessárias e deixar clara a próxima ação, mantendo todas as capacidades necessárias ao trabalho. O minimalismo solicitado pelo usuário é aplicado à hierarquia, à linguagem e à quantidade de informação simultânea; não é justificativa para remover funções, esconder alertas clínicos ou exigir gestos secretos. Não atribuímos estas decisões a citações de Steve Jobs.

## Quatro destinos estáveis

| Aba | Pergunta humana | Conteúdo e progressão |
| --- | --- | --- |
| Hoje | O que precisa de mim agora? | Próximos atendimentos, fila, pendências acionáveis; sem uma parede de indicadores. Cada item abre o trabalho relacionado. |
| Agenda | Quem vou atender e quando? | Dia, profissional, disponibilidade, agendamento, confirmação, chegada e acompanhamento. Ações de criar pertencem à toolbar, não à tab bar. |
| Pacientes | De quem estou cuidando? | Busca → ficha → atendimento, histórico, prescrições, exames, documentos e especialidade. O paciente selecionado permanece no contexto. |
| Mais | Como organizo meu trabalho e minha clínica? | Áreas agrupadas por tarefa e permissão: comunicação, operação e gestão, conhecimento, conta e ajuda. Busca de funções prevista, sem acrescentar uma quinta aba. |

O limite de quatro abas é uma decisão do produto solicitada pelo usuário; a HIG orienta o comportamento da navegação, sem ser apresentada como origem desse número. Cada aba preserva sua pilha de navegação. Trocar de clínica ou sair da conta apaga as pilhas e os dados em memória. A ordem das abas permanece estável; permissões refinam destinos e ações, sem reorganizar continuamente o aplicativo.

Em iPad, evoluir para tab bar adaptável/sidebar e apresentação lista–detalhe, preservando os mesmos quatro destinos conceituais. A implementação atual possui TabView e NavigationStack; a apresentação avançada de iPad permanece pendente de validação com SDK e simulador.

## Jornadas que definem a estrutura

1. **Começar o dia:** entrar → confirmar clínica ativa → Hoje → abrir próximo atendimento. MFA só aparece quando o servidor exige. Falha temporária de rede não elimina credenciais válidas.
2. **Encontrar a pessoa certa:** Pacientes → buscar nome/CPF → reconhecer por dados cadastrais mínimos → abrir ficha. Nomes semelhantes nunca provocam união automática de cadastros.
3. **Receber o paciente:** Agenda/Hoje → agendamento → registrar confirmação ou chegada conforme o fato observado. Confirmar presença futura e registrar chegada são ações distintas.
4. **Atender:** abrir paciente → conferir identidade e alertas → registrar evolução → prescrever/solicitar exames → revisar e concluir. Esta jornada completa ainda precisa ser implementada.
5. **Gerir a clínica:** Mais → área de gestão → tarefa. Uma gestora sem papel clínico não recebe prontuário completo porque abriu o mesmo aplicativo.
6. **Trocar de clínica:** Mais → Suas clínicas → escolher → recarregar permissões e dados. Nunca manter nome, lista ou resposta assíncrona da clínica anterior.

## Sistema visual e interação

- Preferir TabView, NavigationStack, List, Form, Section, DatePicker, sheets, alerts e confirmationDialog do sistema. Usar SF Symbols com rótulos textuais.
- Usar fontes semânticas San Francisco e Dynamic Type; títulos, subtítulos e texto de apoio estabelecem a hierarquia. Não comprimir texto para acomodar um layout fixo.
- Superfícies de conteúdo com fundo semântico do sistema. Liquid Glass é reservado à navegação e aos controles fornecidos pelo sistema em versões compatíveis; não cobrir fichas clínicas e listas com vidro.
- Cor de destaque única para ações. Vermelho tem significado de erro, risco ou destruição, sempre acompanhado de texto/símbolo. Situações nunca dependem só de cor.
- Uma ação principal clara por etapa. Ações secundárias no contexto. Pedir confirmação quando a consequência justificar; não interromper ações simples repetidamente.
- Alvos de interação de pelo menos 44 × 44 pt como meta deste produto. Evitar botões lado a lado quando o texto ampliado comprometer seu uso.
- Formulários roláveis, com labels persistentes e suporte a teclado/AutoFill. Nenhum modal pode esconder o botão que confirma ou encerra a tarefa.
- Preferir sheets para tarefas curtas; navegação para leitura e trabalho longo. Nunca empilhar modais para simular uma navegação.
- Preservar espaço para leitura e nomes longos. Adaptar linhas horizontais para verticais em tamanhos de acessibilidade.
- Feedback específico: carregando, sem resultados, acesso restrito, falha de conexão, resposta parcial e informação desatualizada são estados distintos.
- Não chamar uma alteração de salva antes da confirmação do servidor. Nunca usar números fictícios para preencher um painel vazio.

## Acessibilidade e confiança

Revisar VoiceOver, ordem de foco, Voice Control, Dynamic Type até os tamanhos máximos, contraste aumentado, redução de transparência e movimento, modo escuro, orientação e teclado. Preferir controles nativos, mas verificar o comportamento: sua presença não comprova conformidade automaticamente.

Proteger a visualização no seletor de aplicativos. Não guardar prontuário em UserDefaults nem em cache HTTP. Credenciais ficam no Keychain, restritas a este dispositivo. Notificações futuras devem ter conteúdo genérico na tela bloqueada e abrir o registro apenas depois da autenticação.

Ausência de um campo clínico significa informação não disponível; não significa resultado negativo. Exemplo: alergias ausentes não viram “sem alergias”. Histórico continua ligado ao ID correto do paciente.

## Critérios de aceitação da experiência completa

- Profissional encontra o próximo atendimento em Hoje sem navegar por um catálogo de módulos.
- Paciente reconhecível na ficha e nas etapas seguintes; identidade não se perde ao consultar documentos ou especialidades.
- Todas as funções da matriz de paridade têm um caminho nativo, condicionado às permissões reais.
- Nenhuma quinta aba principal; nenhum botão de criação usado como aba.
- Voltar preserva filtros e posição quando apropriado; trocar clínica elimina contexto anterior.
- Uma pessoa consegue completar formulários e confirmações usando VoiceOver e fonte ampliada.
- Estados de rede mostram o último dado confirmado e uma ação de recuperação, sem prometer operação offline inexistente.
- Testes com profissionais, recepção e gestores observam conclusão de tarefas, toques de retorno, erros e dúvidas. Metas de tempo dependem dessa medição, não de estimativas inventadas.

## Documentação Apple consultada

- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): destinos principais, orientação e estado da navegação.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): ações relacionadas ao conteúdo.
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons): hierarquia de ações e áreas de toque.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): auditoria e uso independente de características visuais.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): separação entre controles e conteúdo, uso de Liquid Glass.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass): adoção dos componentes do sistema e hierarquia da interface.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout): adaptação de espaço e safe areas.

Typography, VoiceOver, data entry, sheets, alerts, search, privacy, notifications e demais orientações específicas devem acompanhar cada módulo e a auditoria final. As páginas completas de Typography e Privacy exigiram JavaScript no acesso desta sessão; não foram tratadas como revisão concluída. Consultar a documentação pertinente e verificar a interface são passos contínuos; não declaramos ter auditado toda a documentação Apple.
