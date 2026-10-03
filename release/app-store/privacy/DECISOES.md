# Privacidade: inventário e decisões de publicação

Estado: revisão pendente. A política, o formulário App Privacy e o manifesto do archive devem refletir o mesmo build e as práticas reais de todos os serviços relevantes. Não concluir “dados não coletados” a partir de uma busca apenas no código Swift.

## Evidência atual

- Pacote Swift sem dependências externas. Transporte HTTPS, URLSession efêmera sem cookies/cache persistente, tokens em Keychain.
- Sem HealthKit, SDK publicitário, rastreamento de terceiros, compras, push, localização ou câmera no código atual. O incremento de transcrição de 03/10 acrescenta microfone opcional; não pertence ao Archive37 já gerado.
- Backend compartilhado recebe login, consultas com IDs/termos de busca, cadastros, alergias, alterações de agenda, rascunhos, receitas, documentos, exames e texto enviado à LARI. Receber uma resposta no aparelho não prova, isoladamente, coleta adicional retida no servidor.
- O incremento de exames externos acrescenta envio explícito de laudos e arquivos selecionados, data opcional e laboratório. Revisar saúde e conteúdo do usuário no inventário/App Privacy; não declarar que o recebimento ocorre apenas no aparelho. O acesso da recepção segue o contrato de exames, sem ampliar acesso ao prontuário. O código mantém cópias em memória; compartilhamento é uma escolha separada do usuário e pode entregar uma cópia a outro aplicativo.
- Preparar consulta acrescenta uma solicitação explícita de resumo longitudinal: o serviço consulta o extrato autorizado, usa fatos estruturados na geração e pode registrar a trilha da IA. A resposta diferencia narrativa, fatos e trechos originais. A operação não é processamento exclusivamente local; exige revisão de saúde, conteúdo, provedores e retenção. Não cria evolução nem assinatura automática.
- Pedir confirmação de agendamento solicita comunicação pelo serviço somente após ação confirmada. Consultar fila ou abrir agendamento não dispara mensagens. Pedido registrado não comprova entrega ao destinatário. Revisar a operação dos fornecedores de comunicação no inventário final.
- Ainda não auditados: logs do gateway, retenção de buscas, auditoria de acesso, fornecedores, diagnósticos, mecanismos de suporte e relatório agregado do archive.
- Build 27: acrescenta texto e participantes do chat da equipe, publicações/interações da comunidade, conversas gerais da LARI, buscas de CID/medicamentos e período dos relatórios. Incluir conteúdo de mensagens/publicações e suas finalidades, visibilidade, retenção e destinatários na declaração final; nenhuma categoria foi marcada como dispensada automaticamente.

## Matriz proposta para App Privacy

| Categoria Apple | Dados no fluxo | Situação a confirmar | Finalidade proposta se houver coleta | Vinculado / tracking |
|---|---|---|---|---|
| Name | Nome de usuário/paciente no serviço | Retenção relevante para uso do app | App functionality | Sim / não observado |
| Email Address | Login, recuperação, conta e pacientes | Backend e suporte | App functionality | Sim / não observado |
| Phone Number | Contato de pacientes e suporte | Retenção e destinatários | App functionality | Sim / não observado |
| User ID | Conta, clínica, profissional e paciente | Sessão e auditoria | App functionality | Sim / não observado |
| Health | Alergias, consultas, agendamentos associados a paciente | Persistência e auditoria | App functionality | Sim / não observado |
| Other Data Types | Nascimento e documento mascarado | Campos realmente tratados e sua classificação | App functionality | Sim / não observado |
| Search History | Termos enviados para busca de pacientes | Se há retenção além de atender a requisição | App functionality | Sim se retido / não observado |
| Product Interaction | Ações e acessos associados à conta | Auditoria e telemetria | App functionality | Sim se retido / não observado |
| Other Diagnostic Data | Logs técnicos/IP quando aplicável | Existência, retenção e classificação por uso | App functionality | A determinar / não observado |
| Conteúdo do usuário — classificação final pendente | Mensagens da equipe, conversas LARI e publicações da comunidade | Retenção, destinatários, moderação e correspondência às categorias oficiais | App functionality | Associado à conta / tracking não observado |
| Audio Data / Health — transcrição em desenvolvimento | Áudio da consulta enviado por ação explícita ao serviço e Google Gemini | Confirmar retenção do gateway, do serviço e do provedor; não presumir isenção por processamento em tempo real | App functionality | Pode identificar participantes / tracking não observado |

A definição Apple de coleta considera transmissão para fora do dispositivo com retenção além do necessário ao atendimento em tempo real. Conferir exceções e práticas de suporte diretamente na documentação; não utilizar uma exceção para omitir sistematicamente dados de pacientes. Endereço IP deve ser classificado conforme seu uso real, e não convertido automaticamente em localização.

## Manifesto

`App/PrivacyInfo.xcprivacy` está integrado aos recursos do target. Declara ausência de tracking e o uso de UserDefaults com a razão CA92.1 para preferências próprias do aplicativo. A declaração de categorias de coleta continua pendente da auditoria de serviços e provedores; a ausência dessa lista no manifesto não equivale a “dados não coletados”. O arquivo `PrivacyInfo.candidate.xcprivacy` é uma referência de preparação e não é o recurso compilado.

Conferir o manifesto efetivamente contido no Archive e o relatório agregado. A presença do arquivo não conclui App Privacy. Revisar especialmente saúde, conteúdo clínico enviado à LARI, assinatura, documentos, dados financeiros, suporte e auditoria do backend antes de distribuir.

## Divergências encontradas na política geral do site

1. A expressão “criptografia de ponta a ponta” não está demonstrada por TLS/Keychain. Validar a arquitetura e corrigir a comunicação aplicável antes de lançar.
2. Localização exclusivamente brasileira, algoritmos de proteção de bancos/backups e prazos operacionais exigem evidência de infraestrutura.
3. Guarda clínica e exclusão de conta não compartilham automaticamente o mesmo prazo. Confirmar matriz de retenção por categoria e fundamento.
4. Não usar o prazo de um tipo de solicitação LGPD como promessa universal para todas as solicitações.
5. Não estender afirmações de assinatura, IA, receituário, TISS, pagamentos ou integrações da web a funções ausentes no app.

Nada foi alterado na política geral, no site ou nos serviços. A nova página iOS é um complemento em revisão, não uma forma de evitar a correção de inconsistências do serviço.

## Registro necessário do responsável

Para cada linha do inventário: indicar sistema/fornecedor, finalidade, categorias, fundamento, país, retenção, controle de acesso, responsável e evidência. Não colocar credenciais, logs de pacientes ou contratos confidenciais no pacote público.

Referências: [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/), [manifestos](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [LGPD](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm), [ANPD](https://www.gov.br/anpd/pt-br/acesso-a-informacao/perguntas-frequentes/perguntas-frequentes).

- Continuidade de consulta após build36: o aplicativo retém a instância do rascunho em memória durante a sessão, sem arquivos locais/Keychain/UserDefaults para as anotações. Saída da conta, troca de clínica e atualização de contexto invalidam conteúdo. Salvar no servidor continua explícito. Não declarar persistência offline nem recuperação após encerrar o aplicativo.

## Incremento de transcrição e análises — 03/10/2026

Preparação local, ainda sem novo Archive ou homologação: finalidade do microfone declarada em `Config/App.xcconfig`. A autorização do microfone não substitui a autorização dos participantes nem o consentimento específico para compartilhar áudio com o serviço e Google Gemini. A interface precisa apresentar gravação em andamento, interrupção e descarte; a transcrição deve ser revisável e não salvar ou assinar automaticamente uma evolução. Não usar reconhecimento de voz da Apple nesta implementação, portanto não solicitar uma permissão de Speech desnecessária.

O endpoint de transcrição observado no código do serviço utiliza Gemini; Anthropic continua pertinente aos outros fluxos LARI conforme a configuração. Confirmar implantação e retenção reais antes da declaração final da loja. O suporte de arquivos temporários no cliente não comprova retenção zero fora do aparelho. O App Privacy remoto continua pendente de auditoria e autenticação; nenhum campo foi marcado como concluído nesta rodada.

Relatórios de sazonalidade e distribuição municipal consultam dados agregados autorizados, com fontes, período e lacunas retornados pelo serviço. Dados demográficos de município não devem ser apresentados como perfil individual dos pacientes da clínica. A consulta de interações usa uma base curada limitada; não enviar prontuário inteiro nem acrescentar provedores não usados. A ausência de alertas não é certificação de segurança.

Referências verificadas em 03/10/2026: [microfone](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription), [privacidade na HIG](https://developer.apple.com/design/human-interface-guidelines/privacy/), [App Review — dados e terceiros](https://developer.apple.com/app-store/review/guidelines/uk/).
