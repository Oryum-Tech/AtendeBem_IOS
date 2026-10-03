# Campos e decisões do App Store Connect

Registro local de preparação para **1.3.0 (40)**, atualizado em 03/10/2026. O registro do aplicativo e algumas respostas foram salvos em rodadas anteriores conforme `../release-status.json`; isso não confirma os campos, o upload ou a revisão do build 40. Conta demonstrativa, QA em dispositivo e submissão continuam dependentes de evidências próprias.

| Campo | Preparação | Condição |
|---|---|---|
| Nome/localização | AtendeBem - Gestão Clínica / pt-BR | Cadastro conferido no App Store Connect, Apple ID6762195438 |
| Bundle ID | io.atendebem.app | Identidade conferida no cadastro e em Archives/IPAs anteriores; equipe FWVSMZ9APG. Conferir novamente no Archive40 |
| Categoria | Medical | Confirmar com finalidade final |
| Plataformas | iPhone e iPad, iOS 17+ no projeto | Validar distribuição e SDK atual exigido pela Apple |
| Versão em preparação | 1.3.0 (40) | Compilação de Simulator reportada pela validação central; Archive/IPA40, execução autenticada e upload ainda não comprovados neste registro |
| Preço/territórios | Pendente de decisão operacional | Proposta preservada: Brasil e download gratuito. Conta existente ou cadastro gratuito nativo; condições para experimentar consultadas no catálogo |
| Criação de conta | Cadastro nativo de clínica/consultório implementado | Catálogo público antes da escolha; cadastro real e retorno ao login exigem homologação |
| Exclusão de conta | Início nativo implementado | Mais → Configurações → Minha conta → Excluir minha conta. Operação DPO e QA pendentes; não confirma conta apagada nem protocolo de API |
| LARI e consentimento | Texto geral persistente por conta/clínica/aparelho e versão, revogável | SOAP, paciente e áudio mantêm autorização própria; retenção/provedores/países ainda exigem confirmação operacional |
| Relatórios e avatares | Até oito intervalos reais por página; avatares com anonimato preservado | QA no aparelho e checagem de perfis/contextos pendentes; moderação não decorre da presença de avatar |
| Direitos de conteúdo | Marca e registros de demonstração | Confirmar autorização e nenhuma informação de pacientes reais |
| Publicação | Manual | Revisar build, materiais e aprovação antes de liberar |
| EULA | Pendente de decisão | Avaliar licença padrão Apple e termos do serviço; não inventar obrigações Apple |
| Sign-in with Apple | Sem login social no código atual | Reavaliar caso inclua provedores externos |
| Criptografia | HTTPS/Keychain do sistema | Confirmar archive e questionário; Info.plist usa criptografia isenta, não “nenhuma criptografia” |
| Tracking/ATT | Nenhum observado no cliente | Confirmar backend e dependências antes de responder |
| Conteúdo de terceiros | Marca própria e dados autorizados | Não usar material clínico de terceiros sem licença |

## Cobrança

Separar serviço institucional vendido a organizações de planos vendidos a profissionais individualmente. Não presumir que qualquer SaaS de clínica se enquadra em Enterprise Services. Avaliar as condições de 3.1.3(c) e, quando apropriado, 3.1.3(f), considerando contratação, links e regiões efetivas. O cliente atual oferece criação gratuita de conta, sem compra, preços ou checkout externo. A oferta de experiência é lida em `GET /v1/planos`: a resposta preservada contém nove planos com 14 dias e sem cartão, enquanto Rede retorna zero dias e não é elegível. A criação usa o contrato existente, sem repetição automática de resultado incerto. Essas condições não resolvem, por si, o enquadramento comercial da contratação futura.

## Cadastro e exclusão

O cadastro aceita sete categorias profissionais para identificar o responsável. Isso não significa disponibilidade das fichas clínicas de todas essas especialidades. O catálogo de planos pode anunciar recursos da plataforma web que permanecem pendentes no cliente nativo; a descrição da loja deve continuar limitada à matriz de paridade.

Com criação de conta no aplicativo, a exclusão deve ser revisada no escopo completo. O início nativo está implementado em **Mais → Configurações → Minha conta → Excluir minha conta**. A operação do responsável por privacidade/DPO e o QA continuam pendentes: observar recebimento, encaminhamento, desfecho, prazos e retenções aplicáveis. O início não comprova conta apagada nem emissão de protocolo por API; encerramento de sessão não é exclusão. A [orientação oficial de exclusão de conta](https://developer.apple.com/support/offering-account-deletion-in-your-app/) prevê cuidados para setores regulados, mas não dispensa validar o fluxo nem permite presumir conformidade.

## Classificação etária

Reavaliar o questionário salvo conforme o conteúdo clínico e as funções finais, sem escolher arbitrariamente uma idade. O cliente inclui comunidade e comunicação, portanto não declarar ausência desses recursos. As limitações de denúncia, bloqueio e moderação permanecem registradas em `../release-status.json`. Acesso a links fixos de política no navegador do sistema não equivale automaticamente a navegação irrestrita dentro do app.

Fotos de perfil agora são apresentadas com mídia autenticada e proteção de anonimato. Isso não implementa denúncia, bloqueio ou operação de moderação. **Comunidade e moderação continuam pendências da revisão pública**; não foram retiradas das funções ou dos anúncios para ocultar essa lacuna.

Registrar cada resposta e a classificação calculada pelo App Store Connect, inclusive resultados regionais. A intenção de uso profissional não é justificativa automática para escolher 18+ nem 4+.

## Dispositivo médico regulado

Se distribuir em regiões onde a declaração é exigida, responder por região conforme o enquadramento documentado. A categoria Medical não prova que o app é um dispositivo médico regulado, e uma frase de isenção não prova o contrário. Reavaliar ao incluir decisão clínica, cálculo ou recomendação.

## Acessibilidade

O código usa fontes semânticas e componentes nativos. Isso ainda não comprova suporte completo para os selos da loja. Executar as tarefas principais com VoiceOver, Larger Text, contraste suficiente, diferentes temas, Reduce Motion e controles disponíveis. Marcar os recursos somente após evidência por dispositivo. Não publicar “100% acessível”.

## Escopo das políticas

Obrigatório preparar privacidade pública e acesso dentro do app; demais documentos cobrem obrigações e características aplicáveis ao produto. Não são todos formulários obrigatórios separados da Apple. Cookies são pertinentes às páginas web e aos recursos realmente utilizados, e não justificam um banner genérico no cliente nativo sem cookies. Permissões e textos de propósito para câmera/microfone/HealthKit só devem ser adicionados quando existir a respectiva função.

Consultar as fontes oficiais em `../SOURCES.md` antes do envio, pois campos e exigências podem mudar.

## Campos que dependem de dados reais do responsável

Nenhum valor abaixo pode ser deduzido apenas da marca, de um nome de usuário, do endereço publicado no site ou de um build assinado. Preparar o campo e confirmar a informação real são passos diferentes.

| Campo Apple ou dado que o sustenta | Informação real necessária | Estado deste registro |
| --- | --- | --- |
| App Review Information — Contact Information | Nome, sobrenome, e-mail e telefone internacional da pessoa que responderá à Apple | Pendente de confirmação do responsável; não preenchido com identidade inferida |
| App Review Information — Sign-in Information | Conta dedicada funcional, clínica/perfis sintéticos e acesso reproduzível durante a revisão | Credenciais devem ser inseridas diretamente no App Store Connect; conta demonstrativa não foi declarada testada |
| Entidade publicadora/conta Apple Developer | Confirmar uso da conta individual atual ou da organização, razão social e autoridade de quem administra a conta; documentos devem corresponder à modalidade escolhida | TechBem LTDA no material de marca não comprova conta organizacional ativa nem transferência concluída |
| Copyright | Titular efetivo dos direitos e ano correspondente | Texto existente preservado como candidato; titularidade depende de confirmação |
| Support URL | Página pública funcional com contatos reais e equipe responsável pelo atendimento | URL preparada; confirmar operação, entidade, e-mail/telefone/endereço aplicáveis |
| Privacy Policy URL e política publicada | Entidade responsável pelo tratamento, contato real para privacidade/direitos e práticas efetivas dos serviços/IA | Política iOS e inventário precisam refletir cadastro, exclusão, áudio e provedores; não inventar retenção ou países |
| DSA/trader, se houver distribuição na União Europeia | Enquadramento real, endereço, telefone e e-mail verificáveis e documentos exigidos pela Apple | Condicional aos territórios e ao enquadramento; não marcar automaticamente trader ou não trader |

Referências consultadas em 03/10/2026: [campos da versão e revisão](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information), [detalhes de revisão na API da Apple](https://developer.apple.com/documentation/appstoreconnectapi/app-store-review-details) e [informações de comerciante para a União Europeia](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements). Este quadro não substitui a conferência do formulário atual no App Store Connect.
