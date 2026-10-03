# Feedbacks e melhorias — 03/10/2026

Este documento acompanha os relatos do build 39 e os pedidos de evolução tratados nesta rodada. Registra implementação e limites; não declara os feedbacks encerrados por QA nem atribui estas mudanças a um pacote entregue. Os identificadores individuais de feedback da Apple não estão reproduzidos aqui porque não foram disponibilizados ao autor deste registro. O build e a descrição são as referências usadas, sem inventar IDs.

## Alterações implementadas

| Pedido ou ponto de melhoria | Implementação observada | O que falta conferir |
| --- | --- | --- |
| Acesso mais direto às ações da Hoje | Atalhos antes de retomadas, próximo atendimento e ações da recepção; navegações independentes e acessos por perfil preservados. Retomadas compactas expansíveis e acesso à ficha pelo próximo atendimento continuam disponíveis | Navegação com dados fictícios, perfis clínico/recepção, fontes parciais, texto grande e VoiceOver no aparelho |
| Autorização da LARI precisava ser repetida | Preferência de texto geral versionada, por usuário e clínica neste aparelho; carregada ao abrir o chat e conferida novamente nos pontos de envio | Reabrir aplicativo, trocar usuário/clínica e validar em duas janelas reais |
| Revogar a autorização de IA | Configurações → Autorizações da LARI remove a autorização do escopo atual; instâncias abertas são atualizadas e os guards consultam o valor persistido atual | Revogar com aviso fechado e envio em andamento; uma mensagem já recebida pelo servidor pode continuar em processamento |
| Relatórios difíceis de ler | Distribuição da agenda em páginas de até oito intervalos, valores exatos expansíveis e acessíveis; gráfico sem rolagem vertical interna. Ausência ou inconsistência dos intervalos é indicada, sem estimar dados | Períodos curtos/longos, paginação, troca de contexto, valores zero, fonte parcial e leitura por VoiceOver |
| Identificação visual na comunidade | Avatares nas publicações, lista de pessoas, perfis e conversas diretas, usando mídia autenticada e miniatura. Falha ou ausência usa iniciais; publicação anônima usa símbolo neutro, sem buscar a foto do autor nem exibir suas iniciais | Autores anônimos/não anônimos, falha de mídia e mudança de clínica; não representa novo upload de foto |
| Apresentação, login e cadastro | Imagem oficial local; apresentação nativa com benefícios atuais, caminho para cadastro, layout adaptável ao iPad e preservação dos fluxos de autenticação. Oferta dinâmica obtida no catálogo público | Cadastro real em homologação, resultado incerto, retorno ao login, MFA, recuperação e apresentação em aparelho |
| Conhecer o Meu Prontuário | Página Techbem em Mais com App Store, site e compartilhamento explícito do link do aplicativo independente | Abertura e compartilhamento no aparelho; nenhum dado de paciente deve ir no conteúdo compartilhado |
| Iniciar exclusão da conta | Início nativo implementado em Mais → Configurações → Minha conta → Excluir minha conta | Operação do responsável por privacidade/DPO e QA pendentes; o início não comprova conta apagada nem protocolo de API |

## Escopo do consentimento

- Somente **texto geral da conversa da LARI** recebe persistência. A preferência não concede atos clínicos ou envio automático de documentos.
- O registro local contém escopo e versão da política, sem mensagens, conteúdo clínico ou autorizações de áudio.
- Anthropic (Claude) e Google (Gemini) permanecem identificados no aviso. Mudança relevante de provedores, dados ou finalidade exige atualização da versão, invalidando autorizações anteriores.
- Trocar conta ou clínica não herda a escolha do contexto anterior. A revogação reflete nos stores/janelas abertas do processo, e a autorização de envio consulta a preferência persistida atual.
- O organizador **SOAP continua com autorização pontual**, inclusive quando omite `pacienteId`: a ausência desse campo não transforma a anotação clínica em texto geral. Dados de pacientes e gravações também mantêm sua autorização própria.
- Revogar impede novos usos com aquela autorização; não apaga mensagens já recebidas pelo serviço nem comprova interrupção de processamento remoto em andamento.

## Catálogo e áreas profissionais

O cliente usa `GET /v1/planos` para a oferta e `POST /v1/onboarding` para criar o espaço solicitado. A [resposta pública preservada nesta rodada](../release/app-store/evidence/2026-10-03-lari-continuidade/public-plans.json) contém nove planos com 14 dias e sem cartão, além de Rede, sem essa oferta. Nenhum sucesso de cadastro foi inferido da leitura do catálogo.

Há sete opções profissionais no cadastro: Medicina, Fisioterapia, Odontologia, Psicologia, Fonoaudiologia, Nutrição e Residência. O cadastro identifica o responsável; não comprova implementação nativa de odontograma, avaliações de fisioterapia/fonoaudiologia, planos alimentares, sessões de psicologia ou demais módulos específicos. A [matriz de paridade](PARIDADE.md) mantém essas pendências.

## Meu Prontuário e limites de integração

O [site oficial](https://meuprontuarioapp.com) e a [App Store](https://apps.apple.com/br/app/meu-prontu%C3%A1rio-rem%C3%A9dios/id6777473301) sustentam os usos de organização de receitas, exames e lembretes apresentados na tela Techbem. Abrir ou compartilhar esses links não conecta contas, não envia prontuários e não estabelece sincronismo com o aplicativo independente.

O portal do AtendeBem também usa a denominação Meu Prontuário. Seu contrato de clínica não comprova a conexão com o aplicativo de App Store. Não foi criado botão de conectar nem implementado endpoint novo para essa finalidade.

## Evidências e validações pendentes

Fontes de implementação: `TodayView.swift`, `AIConsentPreferences.swift`, `AIProcessingNotice.swift`, `LARIChatView.swift`, `SettingsView.swift`, `ReportsView.swift`, `ProfileAvatarView.swift`, `CommunityView.swift`, `CommunityPeopleView.swift`, `LoginView.swift`, `WelcomeView.swift`, `RegistrationOfferLabel.swift`, `RegistrationView.swift`, `Registration.swift`, `TechbemView.swift` e `MoreView.swift` no pacote nativo. Imagem e origem documentadas em [Entrada e apresentação](LOGIN-WELCOME-2026-10-03.md) e `LOGIN-ASSETS-PROVENANCE-2026-10-03.json`.

Compilação, suíte de testes desta rodada, comportamento autenticado com homologação, UI/acessibilidade no aparelho, conta demonstrativa para a Apple, capturas/vídeo de loja e entrega/publicação dependem de registros próprios. Este documento não certifica nenhum desses passos como concluído. Não foram alterados arquivos da web, serviços, banco ou configuração de versão por esta tarefa de documentação. Nenhum baseline de sincronização foi aceito.

## Novos relatos após a entrega40

O navegador oficial foi recuperado e os anexos do TestFlight foram lidos em03/10,
após a entrega40. Os quatro relatos novos são deste build, em iPhone17ProMax,
iOS27.0.1:

| Horário BRT | Relato | Observação do anexo | Estado |
| --- | --- | --- | --- |
| 15:03 | Não está puxando os cids | Buscar CID-10 sem consulta preenchida; campo Código ou descrição no rodapé. A imagem não comprova resposta vazia da API | Melhorar descoberta da pesquisa e verificar busca preenchida |
| 15:02 | Erro ao gravar | Transcrever consulta com ambos os consentimentos ligados; botão Iniciar gravação e mensagem genérica Não foi possível concluir. Tente novamente | Diagnóstico da permissão, pré-verificação de acesso e AVAudioSession ainda pendente; sem causa inventada |
| 14:50 | Falta o logo do meu prontuário aqui | Tela Techbem usa símbolo genérico de prontuário no cartão | Aplicar recurso oficial da marca, preservando limites de integração |
| 14:50 | Dá para melhorar os alinhamentos e ux aqui | Tela inicial LARI com catálogo de tarefas, busca e compositor; textos pequenos e cartões comprimidos | Revisar hierarquia, alinhamento e Dynamic Type no iPhone e iPad |

Capturas dos anexos ficam somente em evidência local ignorada pelo Git. Esses
relatos foram triados; não foram encerrados nem incluídos retroativamente no40.

O código foi publicado em Oryum-Tech/AtendeBem_IOS. O Xcode Cloud agora tem o
repositório correto salvo e executou testes/Archive reais no commit76dc1dc; veja
[configuração e limites da execução](GITHUB-E-XCODE-CLOUD.md). O bloqueio de cobrança
do GitHub Actions continua independente desse serviço Apple.
