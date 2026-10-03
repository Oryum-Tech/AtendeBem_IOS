# Política de privacidade — AtendeBem para iPhone e iPad

**Minuta para revisão. Não publicada.** Atualizada em 3 de outubro de 2026. A entrada em vigor depende da consolidação das práticas do serviço e da publicação da versão aprovada.

## 1. Sobre esta política

Este documento explica o tratamento de dados relacionado ao aplicativo AtendeBem para profissionais e clínicas. O aplicativo permite acessar informações dos serviços AtendeBem conforme as permissões de cada conta. Ele utiliza a infraestrutura compartilhada com a versão web.

A identificação publicada pelo serviço é TechBem LTDA, CNPJ 65.884.893/0001-20. O canal de privacidade é privacidade@atendebem.io e o canal de suporte é contato@atendebem.io. Esses dados constam no site do AtendeBem; sua atualização e a responsabilidade pelo aplicativo devem ser confirmadas antes da publicação deste documento.

## 2. Responsáveis pelos dados

A clínica ou o profissional que determina a finalidade do tratamento dos registros de seus pacientes é responsável por esse tratamento. A TechBem presta o serviço tecnológico conforme os contratos e instruções aplicáveis. Para administração de contas, segurança e relacionamento próprio com os usuários, as responsabilidades da TechBem devem refletir suas decisões efetivas sobre o tratamento.

Se você é paciente, procure a clínica responsável para assuntos sobre seu atendimento, correção de registros, acesso a documentos e guarda do prontuário. O canal de privacidade pode orientar o encaminhamento da solicitação, com proteção da identidade do solicitante.

## 3. Informações utilizadas pelo aplicativo

- Acesso à conta: e-mail, senha ou código de autenticação enviados para autenticar o usuário; identificador da conta, nome, e-mail, papéis e clínicas vinculadas retornados pelo serviço.
- Sessão: tokens de acesso e renovação para manter a sessão autorizada. A senha não é guardada pelo código do aplicativo para reutilização automática.
- Rotina da clínica: agenda, fila, identificadores de pacientes e profissionais, horários, tipos e situação de agendamentos. Criação, reagendamento e mudanças de situação enviam alterações ao serviço.
- Consulta de pacientes: termos digitados na busca, identificadores selecionados, nome, data de nascimento, documento mascarado, contatos, alergias e resumo de consultas quando fornecidos pelo serviço e autorizados para o perfil.
- Registros clínicos: cadastros e contatos, alergias, conteúdo de rascunhos, receitas, documentos e pedidos de exames enviados por ação do profissional ao serviço, que aplica permissões e persistência. PDFs e informações de assinatura são retornados para visualização.
- Resultados de exames: integrantes autorizados da equipe podem registrar exames externos, informar sua procedência e anexar texto de laudo ou um arquivo escolhido no seletor do sistema. O aplicativo envia esses dados ao serviço de exames da clínica ativa após a conferência do usuário. Arquivos existentes são obtidos por acesso autenticado; a visualização não interpreta o resultado nem gera diagnóstico. O seletor não dá ao aplicativo acesso automático a toda a biblioteca de arquivos ou fotos.
- LARI — conversa e sugestões com IA: texto informado enviado ao serviço de conversas ou sugestões. A conversa geral começa sem prontuário anexado; no organizador clínico pode ser enviado o identificador do paciente selecionado. Provedores confirmados pelo responsável em 02/10/2026: Anthropic (Claude) e Google (Gemini), conforme a configuração do serviço. O app solicita autorização antes de enviar o texto. Retenção, modalidade contratual, países e uso para treinamento precisam de verificação operacional antes da publicação.
- LARI — tarefas nativas: comandos reconhecidos de receita, agendamento, histórico, exames, financeiro, indicadores e interações abrem tarefas no aplicativo, sem enviar o comando ao chat geral. Cada tarefa consulta ou altera os serviços correspondentes após as ações explícitas da pessoa autorizada. Salvar o rascunho de receita envia os campos revisados ao serviço de receitas. A emissão de exames pelo serviço também tenta assinar; exige revisão antes de confirmar, e seu envio é uma ação separada. Períodos financeiros são enviados ao serviço financeiro autorizado. Histórico factual não solicita resumo com IA automaticamente. A transcrição tem autorizações e processamento próprios descritos abaixo. As tarefas clínicas preparadas permanecem em memória durante a sessão, inclusive ao sair da tela da LARI. Trocar de clínica, atualizar os acessos, sair da conta ou encerrar o aplicativo descarta esse estado local. Ele não constitui histórico persistente de execução; operações sem confirmação precisam ser conferidas no serviço antes de repetição.
- Chat da equipe: identificadores dos participantes, conteúdo e horários das mensagens enviados ao serviço da clínica, acessíveis aos participantes conforme as regras do serviço.
- Comunidade: texto, nome profissional, especialidade, biografia, canais públicos, relações entre colegas, mensagens diretas, visibilidade e interações enviados ao serviço. Publicações podem ser vistas pela comunidade profissional conforme a visibilidade escolhida. Não devem incluir informações que identifiquem pacientes.
- Consultas ao catálogo e indicadores: termos de busca de CID/medicamentos e período dos relatórios enviados aos serviços correspondentes.
- Comunicações de suporte: informações que você decide encaminhar aos canais de atendimento. Evite enviar prontuários, senhas ou códigos de autenticação por e-mail.

Informações sobre saúde são dados pessoais sensíveis. O acesso a essas informações é restrito às finalidades do atendimento e às atribuições autorizadas. Esta versão do cliente não integra HealthKit, publicidade, análise de comportamento por SDK externo, câmera ou localização do dispositivo. A transcrição opcional foi implementada no incremento38, utiliza o microfone e depende de autorização. Sua execução em dispositivo e com o serviço de transcrição ainda precisa de homologação; ela não está contida no Archive37.

A infraestrutura recebe as requisições de rede do aplicativo. Categorias e prazos de logs, auditoria, endereços IP e diagnóstico precisam ser conferidos na operação do serviço e incluídos na versão publicada desta política e nas declarações da App Store.

## 4. Finalidades e fundamentos

Os dados são utilizados para autenticar usuários, aplicar permissões, disponibilizar informações da clínica, processar ações solicitadas, manter a segurança e atender solicitações de suporte e direitos.

O fundamento de cada operação deve ser definido pelo controlador conforme a LGPD. Dados de conta podem ser necessários à execução da relação contratual e a obrigações aplicáveis. O tratamento de dados sensíveis de saúde exige fundamento compatível com o artigo 11; a tutela da saúde tem condições próprias e não deve ser presumida para publicidade ou qualquer atividade da plataforma.

Não se considera que aceitar um termo de uso autorize indistintamente todo tratamento de saúde. Quando uma operação depender de consentimento, sua finalidade deve ser específica e a escolha deve ser informada, com mecanismo de revogação aplicável.

## 5. No aparelho e na comunicação

O cliente utiliza conexões HTTPS e armazena tokens de sessão no Keychain do sistema com acesso condicionado ao aparelho desbloqueado, sem sincronização desses itens para outros aparelhos. A sessão de rede do cliente não mantém um cache persistente de respostas nem um armazenamento de cookies de login.

As informações clínicas, imagens da comunidade e PDFs carregados permanecem na memória para exibição. Ao compartilhar um PDF, o usuário escolhe um aplicativo ou destinatário pela folha de compartilhamento do sistema. Esse destino recebe uma cópia fora do controle do AtendeBem; o compartilhamento não acontece automaticamente. Preferências de abas e da página inicial ficam em UserDefaults por conta e clínica; não contêm o conteúdo do prontuário. Esta versão não grava uma base de prontuários em arquivos para consulta sem internet. Ao sair, a interface remove os dados carregados e a sessão local. Isso não exclui a conta ou os registros existentes no servidor.

Essas medidas não são uma afirmação de criptografia de ponta a ponta. O servidor precisa processar dados para prestar o serviço. Proteções de bancos, backups, suporte, integrações e localização da infraestrutura devem ser documentadas conforme a operação real.

## 6. Compartilhamento e transferências

Na emissão de receitas, o aplicativo apresenta o documento e os contatos do paciente para revisão. A assinatura confirmada no serviço publica um evento que solicita o envio aos canais cadastrados, atualmente WhatsApp e e-mail conforme o serviço. O aplicativo não repete automaticamente um pedido de envio após assinar. A confirmação da assinatura não é confirmação de entrega. O compartilhamento manual de relatórios financeiros abre a folha de compartilhamento do sistema; o usuário escolhe o destino e deve conferir sua autorização. Fornecedores e condições dos canais de comunicação ainda precisam da conferência operacional descrita nesta minuta.

Ao solicitar um resumo para preparar uma consulta, o serviço consulta dados do prontuário aos quais o profissional tem acesso e pode enviar fatos estruturados aos provedores de inteligência artificial para compor uma narrativa. A tela solicita autorização antes de gerar e apresenta os fatos e trechos originais recebidos para conferência. O resumo não se transforma automaticamente em evolução nem em documento assinado. O serviço pode manter uma trilha do processamento; sua retenção e condições devem ser confirmadas no inventário operacional.

Solicitar confirmação de agendamento é uma ação separada de consultar a agenda: após confirmação do usuário, o serviço pode encaminhar uma comunicação pelos canais habilitados da clínica. A solicitação registrada não significa mensagem entregue ou consulta confirmada pelo paciente. Os fornecedores e as condições desses canais devem constar do inventário final.

O acesso no serviço depende dos vínculos e permissões da conta e da clínica. Fornecedores que processam dados para a prestação do serviço devem atuar sob condições de proteção e finalidades compatíveis. A relação efetiva de fornecedores, categorias de destinatários e países de processamento deve integrar a documentação final.

Transferências internacionais, se realizadas, devem ter mecanismo aplicável e transparência ao titular. Não se afirma nesta minuta que todos os dados permanecem no Brasil. O cliente nativo inspecionado não inclui SDK de publicidade. A interface LARI envia conteúdo clínico ao serviço de sugestões. Não se presume que o processamento seja local no aparelho: Anthropic e Google Gemini foram confirmados; verificar as condições contratuais efetivas, finalidade, retenção, países e autorização aplicável antes da distribuição. As políticas públicas dos fornecedores não substituem a verificação dos contratos de API da operação.

## 7. Guarda, encerramento e exclusão

O encerramento do acesso profissional, o cancelamento de uma contratação e a exclusão de registros de pacientes são processos distintos. Determinados registros clínicos, fiscais ou de segurança podem precisar ser conservados por obrigação aplicável, finalidade legítima documentada ou exercício regular de direitos.

O controlador deve estabelecer e divulgar critérios de retenção por categoria, inclusive backups, acesso restrito durante a guarda e destinação ao final do prazo. Não se aplica automaticamente um único prazo a todos os dados do serviço. Desinstalar o aplicativo não solicita exclusão no servidor.

## 8. Seus direitos

Você pode solicitar confirmação de tratamento, acesso, correção e os demais direitos previstos na LGPD, conforme o tipo de dado e as condições legais aplicáveis. Pedidos de exclusão, anonimização, portabilidade, informação sobre compartilhamento, oposição ou revogação de consentimento são analisados conforme o caso.

Escreva a privacidade@atendebem.io com uma descrição do pedido e um canal para retorno. Não inclua documentos clínicos no primeiro contato. Pode ser necessária uma verificação proporcional de identidade, sem exigir informações excessivas. Informaremos o encaminhamento, eventuais restrições justificadas e os prazos aplicáveis ao pedido. Também é possível procurar a Autoridade Nacional de Proteção de Dados.

## 9. Crianças e adolescentes

O aplicativo é destinado a profissionais e equipes autorizadas, e não a contas infantis de autosserviço. Registros de pacientes podem incluir crianças e adolescentes; o tratamento precisa respeitar seu melhor interesse, a finalidade assistencial e a representação ou participação cabível. A classificação etária da loja não substitui essas obrigações.

## 10. Alterações e contato

Mudanças relevantes devem ser comunicadas de forma acessível no serviço e refletidas neste documento. A versão publicada deverá informar sua data de vigência. Privacidade: privacidade@atendebem.io. Suporte: contato@atendebem.io.

**Condições antes da publicação:** confirmar responsável, inventário de backend/SDKs, fornecedores/países, retenção, canal operacional de direitos, base legal por finalidade e compatibilidade com a política geral existente. Ver `../privacy/DECISOES.md`.


## Transcrição opcional — incremento em homologação

Antes de gravar a consulta, o profissional deve confirmar a autorização dos participantes. A permissão do microfone concedida pelo iOS é distinta dessa autorização e do consentimento específico para enviar o áudio ao serviço e ao Google Gemini. A gravação deve ter indicação visível e controles para interromper e descartar. O texto transcrito precisa de revisão; transcrever não salva nem assina o prontuário automaticamente.

O aplicativo prepara áudio temporário protegido e excluído do backup para o envio solicitado. Ao iniciar o envio, carrega o áudio para a requisição em memória e verifica a remoção do arquivo local antes da transmissão. O descarte também verifica a remoção; uma falha de exclusão é exibida com opção de tentar novamente. Uma falha de processamento exige nova gravação, sem repetição automática. Essa remoção no aparelho não comprova exclusão no servidor ou no provedor. Ainda é necessário verificar a retenção efetiva, os contratos e os países de processamento no serviço e no provedor; não se declara processamento exclusivamente local nem retenção zero por terceiros. O inventário App Privacy precisa incluir a avaliação de Audio Data e Health antes da publicação desta funcionalidade. Esta minuta não foi publicada na versão web.
