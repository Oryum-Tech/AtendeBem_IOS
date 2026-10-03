# Revisão Apple e TestFlight

Preparação para **1.3.0 (40)**, em 03/10/2026. Não confirma conta demonstrativa provisionada, QA no aparelho, upload ou revisão pública. Credenciais de rodadas anteriores precisam de nova verificação no build selecionado.

## Conta demonstrativa

Provisionar pelo processo existente do serviço, sem alterar papéis ou contornar MFA de usuários reais. Usar clínica isolada, conta dedicada e apenas registros integralmente sintéticos. Não extrair pacientes de produção para popular a demonstração.

O responsável precisa fornecer nome, e-mail e telefone de revisão em formato internacional nos campos do App Store Connect. Credenciais ficam no gerenciador seguro e nos campos próprios da revisão; não entram no Git, no ZIP, nos scripts nem em prints. Não inventar uma senha ou afirmar que existe uma conta testada.

A conta deve continuar disponível durante a revisão. Se houver MFA, prover um mecanismo legítimo e reproduzível para a equipe revisora sem depender do telefone pessoal de alguém; alinhar com Apple quando necessário. Documentar clínica, perfil, data de agenda, identificadores sintéticos e limites de gravação.

## Dados para captura

Usar nome visivelmente fictício como “Paciente Demonstração A”, e-mail em domínio reservado `.invalid`, sem CPF real, telefone real, foto de pessoa ou conteúdo clínico extraído de atendimento. Preferir alergia “Informação não registrada” ao inventar uma recomendação clínica. Dados de teste precisam ser criados por um fluxo autorizado e ficar separados das clínicas reais.

Screenshots de previews SwiftUI podem ajudar QA visual. Não provam integração, não devem ocultar funcionalidades incompletas e não substituem a execução do fluxo final no build distribuído.

## QA de publicação

- Login, erros, recuperação de senha, MFA, expiração e encerramento de sessão.
- Entrada/apresentação e cadastro nativos: carregar planos elegíveis, confirmar condições atuais, criar apenas uma clínica fictícia autorizada, conferir resultado e acesso posterior. Resposta perdida não deve levar a criação repetida; a leitura pública do catálogo não prova sucesso de cadastro.
- LARI: texto geral lembrado apenas na mesma conta/clínica/aparelho; revogar nas Configurações e verificar telas/janelas abertas. SOAP, paciente e áudio devem continuar pedindo autorização própria.
- Relatórios com oito intervalos por página, valores exatos, zeros e ausência/inconsistência de distribuição. Avatares da comunidade com foto ausente, falha de mídia, anonimato e troca de contexto.
- Isolamento entre clínicas, papéis e contas; tentativa de voltar a uma ficha após troca/logout.
- Agenda e pacientes nas mesmas contas web e iOS; confirmar uma alteração autorizada e observar a leitura correspondente em ambos.
- Conexão lenta, ausência de rede, retomada, duplo toque de confirmação, falha após gravação e repetição sem duplicação.
- iPhone e iPad; orientação, tamanho de texto acessível, VoiceOver, contraste, tema escuro, foco e teclado.
- Privacidade/termos/suporte sem login, URLs públicas e procedimento de direitos. Início nativo da exclusão implementado em Mais → Configurações → Minha conta → Excluir minha conta; operação DPO e QA pendentes. Validar recebimento, desfecho e retenções antes da revisão pública. Não registrar a conta como apagada ou um protocolo de API apenas por iniciar o fluxo.
- Primeiro lançamento limpo, atualização de versão, memória e ausência de dados pessoais em logs/capturas.
- TestFlight com build assinado, IPv6 e servidor acessível à revisão.
- Comunidade: denúncia, bloqueio e moderação continuam pendentes para revisão pública; presença de chat ou avatar não satisfaz esses fluxos.

## Texto de TestFlight

“Teste a navegação em Hoje, Agenda, Pacientes e Mais usando apenas a clínica de demonstração. Confira acesso, busca, atualização dos dados, confirmação de agendamento e troca de clínica. Relate passos, modelo do aparelho e versão do iOS, sem anexar dados pessoais. Esta versão está em desenvolvimento e ainda não reúne todas as funções do sistema web.”

O aceite deve registrar build, aparelho/OS, cenário, resultado, data e responsável. Não marcar QA concluído por aprovação de compilação.
