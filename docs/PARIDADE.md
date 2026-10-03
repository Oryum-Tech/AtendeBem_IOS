# Matriz de paridade web → iOS

Inventário do checkout em 29/09/2026. As rotas são referências de alcance funcional; um item parcial não é paridade completa. A autenticação nativa é tratada separadamente. Nenhuma rota web foi alterada. Estados nativos atualizados em 03/10/2026; itens parciais continuam sem aceite completo.

| Rota existente | Destino nativo | Estado |
| --- | --- | --- |
| `/agenda/nova` | Agenda | Parcial: criação nativa com paciente, profissional e catálogo; homologação pendente |
| `/agenda` | Agenda | Parcial: linha do tempo do dia, lista compacta e semana com sete dias, busca no período, resumo por dia, indicação de falhas parciais, criação, reagendamento e mudanças de estado; confirmação solicitada versus registrada, pedido explícito de confirmação com reconciliação por leitura; visão mensal agregada, turmas e preferências avançadas pendentes |
| `/agenda/procedimento` | Agenda | Planejado; sem interface nativa funcional nesta versão |
| `/ajuda` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/artigos/arquivos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/artigos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/billing` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/centro-cirurgico` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/centro-cirurgico/tablet` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/comunicacao` | Mais | Parcial: chat da equipe, envio, atualização e marcar todas como lidas; histórico acima de 50 mensagens depende do serviço |
| `/comunidade/mensagens` | Mais | Parcial: lista, abertura e envio de mensagens diretas; histórico longo e homologação pendentes |
| `/comunidade` | Mais | Parcial: feed, filtros, publicação, edição/exclusão próprias, curtir, salvar, compartilhar e imagens autenticadas; avatares com imagem autorizada ou iniciais, sem carregar a imagem nem mostrar iniciais do autor em publicação anônima; upload, vídeo, comentários, moderação, denúncia e bloqueio pendentes |
| `/comunidade/perfil/[id]` | Mais | Parcial: descoberta, perfis, avatares, edição do próprio perfil, seguir e iniciar conversa; homologação pendente |
| `/configuracoes` | Mais | Parcial: central com busca e sinônimos, aparência atual e alcance local explícitos, atalhos locais, conta/permissões, troca de clínica, consulta do cadastro e edição de nome/telefone para gestor/admin, padrão de letra de receita sincronizado; autorização de texto geral da LARI versionada por conta/clínica/aparelho, com revogação refletida nas janelas abertas; segurança, fiscal e administração avançada pendentes |
| `/contratos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/convenios` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/estoque` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/exames` | Pacientes | Parcial: pedidos com vários itens e modelos; revisão/assinatura/PDF somente para origem compatível; registro de exame externo por perfis autorizados, laudo/arquivo, leitura dos resultados e conferência de envio incerto. Prévia PDF/imagens e compartilhamento explícito; DICOM sem visualizador diagnóstico. Envio separado implementado após assinatura confirmada e revisão de contatos, sem equiparar enfileiramento a entrega. Homologação entre perfis/dispositivo e entrega real pendentes |
| `/fila` | Hoje / Agenda | Parcial: Aguardando e Em atendimento, ordem/posição do serviço, chegada, espera, atraso, auto-check-in e exceções registradas; abertura do agendamento exato e filtro de profissional segundo o recorte autorizado. Homologação entre perfis e interface no aparelho pendentes |
| `/financeiro` | Mais | Parcial: resumo e lançamentos em leitura; demais fluxos pendentes |
| `/fisio` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/fono` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/gestao` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/hospital` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/indicacoes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/lari` | Hoje / Mais | Parcial: conversa geral com fontes/aviso, recuperação de sessão sem repetição automática, contexto anterior incluído em rascunho revisável e organizador SOAP integrado à consulta com revisão e aplicação seletiva apenas ao rascunho local; preparação da consulta com resumo longitudinal, fatos, trechos e referências, geração explícita sem gravação clínica; consentimento com Anthropic/Google Gemini identificados, persistência apenas para texto geral no mesmo aparelho/conta/clínica e revogação entre janelas; SOAP, dados de pacientes e áudio mantêm autorização própria; catálogo contínuo de tarefas, agendamento, histórico factual, exames com envio explícito, transcrição revisada, indicadores municipais/sazonalidade e interações de base limitada; retenção de tarefas na sessão, busca de tarefas, abertura direta preservando o rascunho e progresso factual com filtro de continuidade; histórico remoto, auditoria contratual dos provedores e homologação pendentes |
| `/medicamentos` | Receita / LARI | Parcial: seleção manual, busca paginada por nome/princípio com termo revisável de pedidos explícitos, submit pelo teclado e retry da consulta exata, inclusão explícita de inativos, ficha de registro/empresa/situação e busca oficial no Bulário; acesso por perfil/contexto. Interações com princípios revisados e fonte/data da base limitada. Índice ANVISA local separado do serviço. Texto integral de bulas, indicações fundamentadas, corpus completo, reconciliação clínica e homologação pendentes |
| `/notas-fiscais` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/novidades` | Mais | Implementação inicial: novidades próprias do aplicativo |
| `/nutri` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/odonto` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/orcamentos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/overview` | Hoje | Parcial: contexto da clínica e ações frequentes antes das retomadas compactas expansíveis, próximo agendamento válido com acesso direto à ficha, recepção, LARI, gestão autorizada, prévia da agenda e fila; atalhos configuráveis, avisos de recorte parcial e mudança de dia/contexto; homologação e acessibilidade pendentes |
| `/pacientes` | Pacientes | Parcial: busca, filtros de idade e acompanhamento, condição/medicamento para perfis clínicos autorizados, indicação de resultados parciais e nascimentos ausentes, cadastro, edição, ficha, alergias, documentos e histórico; linha do tempo unificada paginada com avisos de fontes; problemas, sinais vitais, medicações, relatos do paciente, triagens com medidas vinculadas, dados cadastrais e metadados das evoluções; anexos, detalhes especializados, consentimentos e LGPD pendentes |
| `/pacientes/unificacoes` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/planos-tratamento` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/portal` | Mais | Planejado; sem interface nativa funcional nesta versão. A apresentação Techbem em Mais abre ou compartilha links públicos do aplicativo independente Meu Prontuário: Remédios; não implementa o portal da clínica nem sincronização de contas com esse aplicativo |
| `/preceptoria/avaliacoes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/banco` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/cronograma` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/matriz` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/residentes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/preceptoria/validacoes` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/prontuario` | Pacientes | Parcial: leitura de evoluções, retomada/salvamento de rascunhos, indicação de alterações não salvas, revisão e confirmação da evolução não assinada, comparação explícita de versões e reconciliação por leitura; pausa e retomada na mesma sessão do aplicativo pela Hoje, sem persistência local; sem CAS atômico no serviço. Assinatura, anexos, especialidades e homologação pendentes |
| `/protocolos` | Mais | Planejado; sem interface nativa funcional nesta versão |
| `/psico` | Pacientes | Planejado; sem interface nativa funcional nesta versão |
| `/receituario` | Pacientes | Parcial: receitas em rascunho, documentos com busca e filtros por tipo/disponíveis para assinar, acesso direto pela ficha, assinatura via serviço e PDF; consulta do certificado e compartilhamento de PDF; cadastro/renovação de certificados, envio pelo serviço e renovações de receitas pendentes |
| `/relatorios` | Mais | Parcial: agenda e receitas por período e perfil, períodos prontos/personalizado, distribuição real da agenda paginada em até oito intervalos, gráfico e valores exatos acessíveis, aviso de distribuição ausente ou inconsistente sem estimar valores, falhas por fonte; relatórios avançados e homologação pendentes |
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
| `/teleconsulta` | Mais | Parcial: sala pelo serviço com abertura externa; vídeo nativo e homologação pendentes |
| `/templates` | Mais / Receita / Exames | Parcial: biblioteca com busca/tipos/autoria, revisão e aplicação de modelos de receita/exames, salvar itens como modelo privado, criar cópia privada, editar campos estruturados e excluir os próprios modelos com confirmação; mudança de compartilhamento, importação e aplicação de protocolos mistos pendentes |

## Autenticação e base

| Fluxo | Estado |
| --- | --- |
| E-mail e senha, MFA TOTP, recuperação, troca obrigatória de senha | Implementado contra contratos existentes; E2E autenticado pendente |
| Sessão Keychain, refresh único concorrente, logout local, troca de clínica | Implementado; testes locais e validação no dispositivo têm alcances diferentes |
| Apresentação e cadastro de clínica/consultório | Parcial: entrada e apresentação nativas com imagem oficial; cadastro pelo contrato existente, seleção de plano elegível consultado em `GET /v1/planos`, sete perfis profissionais e tratamento de resultado incerto sem repetição automática. Cadastro real, retorno ao login e validação autenticada pendentes |
| Convite de equipe, login social e vinculação de contas | Planejado |
| Exclusão da conta | Parcial: início nativo implementado em Mais → Configurações → Minha conta → Excluir minha conta; operação DPO e QA pendentes. Não comprova conta apagada nem emissão de protocolo por API |
| Push, câmera, biometria e links universais | Planejado |
| iPad com sidebar/lista-detalhe | Parcial no layout: entrada, apresentação, cadastro e página Techbem adaptam colunas à largura e ao texto. Sidebar/lista-detalhe e homologação de multitarefa/acessibilidade continuam pendentes; shell conserva quatro abas |

O cadastro aceita Medicina, Fisioterapia, Odontologia, Psicologia, Fonoaudiologia, Nutrição e Residência. Essa classificação do responsável não comprova implementação das fichas, avaliações, planos terapêuticos ou jornadas específicas de cada profissão. Os módulos especializados acima continuam com seus estados próprios.

## Ordem de entrega

1. **Validar a base:** Xcode/SDK, compilação iOS, autenticação de homologação, comparação web↔iOS, acessibilidade e navegação.
2. **Fechar o ciclo da agenda:** criar, reagendar, cancelar com motivo, chegada, fila, turmas, disponibilidade e tipos de atendimento.
3. **Concluir o atendimento:** ficha completa, vínculos, histórico longitudinal, evolução, rascunho seguro, assinatura e encerramento.
4. **Documentos e cuidado:** prescrições, exames, atestados, anexos, renovações e especialidades com todos os estados e permissões.
5. **Gestão e comunicação:** financeiro, convênios, TISS, estoque, equipe, mensagens, fiscal, relatórios e suporte.
6. **Demais jornadas:** hospital, centro cirúrgico, teleconsulta, estudos, comunidade, residência, preceptoria, LARI e configurações avançadas.
7. **Distribuição:** ícone, App Privacy, permissões justificadas, assinatura Apple, TestFlight, testes com usuários e App Store.

Cada etapa exige funcionalidades reais e validação integrada. Links para a web, telas estáticas e listas de módulos não contam como uma função nativa concluída. A capacidade completa fica no roteiro sem sobrecarregar as quatro abas principais.

## Incremento de feedbacks — build 27

Antecedentes resumidos com Mais dados, busca CID, marca oficial no pacote e validação de PDF incorporados. Ver [checklist e limitações](FEEDBACKS-2026-10-02.md). Estas implementações não equivalem a aceite de sincronismo ou encerramento dos incidentes clínicos.

## Incremento de feedbacks — build 29

Perfis, mensagens diretas, gestão de publicações, imagens sob demanda, marcação de leitura explícita, certificado, compartilhamento de PDF, consentimento da LARI e histórico unificado implementados. O histórico mantém a ordem do servidor e deduplica páginas sem unir fichas. Não encerra o relato de consultas ausentes sem reproduzir o caso na homologação. Build 28 preservado como intermediário; não entregue.

## Incremento de feedbacks — build 30

Dois feedbacks do TestFlight 1.3.0 (27), consultados em 02/10 (o relato dos atalhos às 15:15), orientaram esta entrega: atalhos abrindo LARI e falta de diferença entre Dia/Lista. Atalhos agora usam ações individuais e um destino de navegação fora da lista; Dia usa linha do tempo por hora e Lista usa apresentação compacta. A barra mantém até quatro abas. Configurações e Mais têm busca, agrupamentos e descrições. Preferências de aparência/atalhos ficam locais por conta/clínica; letra das receitas e cadastro da clínica usam contratos existentes. Modelos clínicos e pedidos de vários exames ampliam as funções nativas, sem descarte de dose, frequência, duração, instruções ou justificativas ao aplicar modelos.

42 testes Swift e Archive iOS passaram. Testes de UI foram acrescentados para os dois feedbacks e ainda precisam ser executados no dispositivo/Simulator com sessão de homologação. O build 30 inclui o incremento 29, que foi arquivado/exportado, mas não entregue. A matriz continua parcial.

## Evolução após o build 30 — código observado em 02/10/2026

Este registro descreve o código consultado nesta rodada; não atribui as mudanças a um pacote distribuído, não confirma comportamento em aparelho e não avança o baseline de sincronização. A validação desta rodada é registrada separadamente em [VALIDACAO.md](VALIDACAO.md).

- **Agenda semanal:** consulta os sete dias de segunda a domingo em UTC−03:00, com até três consultas de dia simultâneas. Cada dia apresenta seus agendamentos ou um erro explícito; totais com dias indisponíveis são marcados como parciais. A duração somada não desconta sobreposições e não é apresentada como disponibilidade. A tela reutiliza o resultado em memória por até cinco minutos no mesmo contexto/semana, sem consulta periódica da semana; a atualização manual força nova leitura. O código impede a exibição de resultados de outro contexto de conta/clínica. Os rótulos dos tipos acompanham as cores do catálogo, sem depender apenas de cor.
- **Pacientes:** filtros de acompanhamento (todos, sem consulta há 90 dias, condições crônicas e gestantes), inclusão de arquivados e faixa etária inclusiva de 0 a 130 anos. Condição, medicamento e segmentos clínicos exigem perfil clínico; o papel administrativo isolado não libera essa busca. O segmento de 90 dias informa a inclusão de arquivados definida pelo serviço. A tela explica respostas truncadas e cadastros sem nascimento; filtros ativos não são repetidos automaticamente a cada 30 segundos. Estes filtros consultam dados, sem editar prontuários ou estabelecer diagnóstico.
- **Documentos:** acesso direto pela ficha do paciente, busca no conteúdo retornado, tipo de documento e filtro Para eu assinar. O resultado mostra a quantidade no recorte; o estado de assinatura continua vindo do serviço e a disponibilidade do PDF não certifica assinatura. Nenhum documento é assinado ou enviado automaticamente.
- **Modelos:** cópia privada de um modelo acessível e edição/exclusão dos próprios modelos. O editor preserva campos estruturados de medicamentos, exames, justificativas, orientações, condição e códigos; envia somente alterações. Há revisão de conteúdo, aviso do alcance de um modelo já compartilhado, confirmação de exclusão e consulta da versão antes de editar/excluir. Essa consulta prévia não equivale a controle atômico de concorrência no servidor. Ao aplicar, conteúdo que mudou deve ser revisado novamente. Importação, mudança de compartilhamento e aplicação de protocolo misto continuam pendentes.
- **Configurações:** busca ampliada por termos de uso (fonte, impressão, assinatura, ordenar, tema), valor atual da aparência e explicação do alcance local por conta/clínica/aparelho. Modelos e letra das receitas continuam vinculados aos serviços existentes. Preferência local de aparência não promete sincronização com a web.

As implementações preservam as quatro abas. A análise competitiva está em [CONCORRENTES-2026-10-02.md](CONCORRENTES-2026-10-02.md). Agenda mensal, importação/compartilhamento de modelos, QA real, acessibilidade no aparelho, comparação autenticada web↔iOS e as demais lacunas desta matriz continuam abertas. Nenhuma conclusão de superioridade sobre concorrentes decorre apenas da leitura do código.

## Perfis, clínicas, prontuário e LARI — incremento de 02/10/2026

- Capacidades clínicas conferidas por papéis literais dos controllers. Administração isolada não concede atos clínicos; perfis acumulados continuam somando os acessos previstos. Clínica ativa e perfis ficam visíveis na Hoje e Configurações; a recepção tem atalhos de agenda/cadastro/equipe. A troca usa somente filiações retornadas, invalida o contexto anterior e recarrega conta e papéis. Não há compartilhamento irrestrito entre clínicas nem alteração de permissões no servidor.
- Atualizar meus acessos relê a conta e as filiações. Não é atualização contínua de papéis. O vínculo paciente–profissional da agenda é criado pelo serviço e pode ter processamento assíncrono; homologação com recepção e médico continua necessária.
- Prontuário ampliado em leitura: problemas, sinais vitais, medicações da clínica e relatos do paciente consultados separadamente, com falhas próprias. Valida IDs antes de mostrar dados. Preserva procedência, unidades desconhecidas, registros tardios e seções históricas. Não confirma adesão, normalidade, conciliação medicamentosa ou ausência de doença por resultado vazio.
- LARI recupera sessão após 401 por leitura autenticada, sem repetir o envio. Mantém pergunta e conversa quando possível, distingue criação malsucedida de mensagem incerta e permite cancelar a espera. O usuário pode acrescentar o último par pergunta/resposta ao rascunho, sem envio automático e sem truncamento acima de 4.000 caracteres.
- O serviço LARI não recupera histórico no prompt e não fornece GET de conversas; também pode retornar resposta alternativa quando o provedor falha sem informar esse modo ao cliente. Essas limitações exigem evolução do serviço, fora da autorização de alteração deste projeto.

Novos testes de estado e contrato foram escritos; resultados executados ficam em VALIDACAO.md. Edição dos registros clínicos adicionais, anexos, assinatura final da evolução, reprodução do caso do doutor e QA autenticado permanecem pendentes.

## Fluxos integrados — desenvolvimento após o build 32

- LARI na consulta: texto explicitamente preparado e consentido, comparação com a anotação original, seleção dos trechos e acréscimo local. Preserva texto, seções personalizadas, queixa e CIDs; não salva nem confirma automaticamente. A resposta fica inválida se o rascunho/contexto mudar.
- Depois da confirmação da consulta, criação de receita, exame ou atestado conforme perfil, mantendo o paciente. O resultado da criação é validado por paciente/autor/ID e abre o documento específico.
- Documentos carregam por fonte, mostram conteúdo estruturado retornado e revalidam a projeção antes de solicitar assinatura. Falhas de autorização descartam o conteúdo. Resposta de assinatura perdida exige reconciliação por leitura, sem repetição automática. O serviço não fornece revisão atômica nem todos os campos do PDF na listagem; PDF de receita rascunho só fica disponível após assinatura.
- Relatórios: Hoje, Esta semana, Este mês, Mês anterior e período personalizado com Aplicar/Cancelar; gráfico mais tabela de valores. Período e contexto invalidam resultados antigos. Agenda usa UTC−03; receitas seguem o fuso aplicado pelo serviço à UF da clínica.

Resultados e limites de validação em [VALIDACAO.md](VALIDACAO.md). O novo código ainda não deve ser atribuído aos pacotes 31/32 já gerados. Não houve alteração da web nem avanço de baseline. [Decisões e roteiro de homologação](FLUXOS-INTEGRADOS-2026-10-02.md).

## LARI por comando — incremento de 03/10/2026

Pedidos reconhecidos de receita e relatório financeiro agora têm fluxos nativos com permissões por clínica. Prescrição exige identidade, medicamento, dados clínicos e assinatura profissional; financeiro usa duas fontes por período e explicita valores pendentes e indisponíveis. O contrato público de receita não devolve todos os campos de rascunhos externos. Tipos especiais fora do formulário, retomada persistente, comandos universais, integração real e recebimento de mensagens continuam pendentes. Ver [fluxos e limites](LARI-TAREFAS-2026-10-03.md). Não encerra a matriz de paridade.

## Continuidade e configurações — incremento após o build 36

Retomada de consultas somente em memória nesta sessão, com entrada na Hoje e preservação dos estados de gravação incerta; contexto/conta/clínica invalidam o conteúdo. Configurações de clínica e letra de receitas protegem edições, confirmam descarte e permitem consultar o servidor preservando campos editados. Validação e limites estão em [Continuidade e configurações](CONTINUIDADE-E-CONFIGURACOES-2026-10-03.md). Este incremento não pertence ao IPA 36 entregue, não recupera notas perdidas em sessões anteriores nem resolve as lacunas de assinatura final e consultas retroativas.


## Home e expansão da LARI — build38, 03/10/2026

Implementação com304testes locais aprovados, Archive assinado e IPA exportado; importado no Transporter, entrega ainda não confirmada. Sem paridade completa ou homologação: Hoje com retomadas/próximo agendamento/ações/recorte curto; tarefas nativas de agendamento, histórico, exames, transcrição, indicadores e interações. Escopo e limites em [Home e LARI](HOME-LARI-2026-10-03.md). Permanecem abertos comportamento autenticado, dados implantados, UI/acessibilidade no aparelho, maturidade clínica e mídia real da loja. A base de interações é limitada e os relatórios de sazonalidade usam o período disponível no serviço; não há agente irrestrito nem pesquisa arbitrária de todos os dados.

## Feedbacks do build 39 — implementação de 03/10/2026

Hoje prioriza os atalhos antes do próximo atendimento; a autorização de texto geral da LARI é persistida e revogável no escopo local, com atualização entre janelas. Relatórios apresentam apenas os intervalos recebidos, com paginação; a comunidade passa a mostrar avatares respeitando o anonimato. Entrada/apresentação e cadastro são nativos e adaptáveis ao iPad. Mais apresenta o aplicativo independente Meu Prontuário com links e compartilhamento explícito, sem conexão automática.

O catálogo público consultado nesta rodada retorna nove planos com 14 dias e sem cartão; Rede retorna zero dias e não é elegível à oferta. O cadastro lê as condições atuais e não usa os destaques de especialidades como prova de funcionalidades nativas concluídas. Escopo, fontes e roteiro de validação em [Feedbacks de 03/10](FEEDBACKS-2026-10-03.md) e [Entrada e apresentação](LOGIN-WELCOME-2026-10-03.md).

Este registro descreve código implementado. Não confirma compilação, QA no aparelho, conta demonstrativa, mídias de loja, entrega ou publicação desta rodada; os resultados devem ser registrados separadamente após verificação. Não houve aceite de paridade nem avanço do baseline por este registro.
