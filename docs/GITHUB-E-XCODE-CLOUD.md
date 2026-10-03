# Repositório e compilação em nuvem

O destino do projeto nativo é `https://github.com/Oryum-Tech/AtendeBem_IOS.git`.
O projeto `AtendeBem.xcodeproj`, o scheme compartilhado `AtendeBem`, a configuração
`Config/App.xcconfig` e o pacote local `Packages/AtendeBemKit` devem ser versionados
juntos. A web e os serviços permanecem fora deste checkout.

O repositório escolhido é público. Credenciais, certificados, Archives, IPAs,
capturas de feedback, evidências operacionais e estados do detector ficam locais.
O Git remote é a origem usada pelo Source Control do Xcode; não existe uma URL de
repositório separada dentro do arquivo do projeto.

## GitHub Actions

`.github/workflows/ios-validation.yml` executa verificações Python, testes Swift
e compilação iOS sem assinatura em pushes para main e pull requests. A preparação
da loja possui pendências reais: a verificação de conteúdo não deve ser confundida
com autorização para revisão pública.

## Xcode Cloud

Os scripts executáveis em `ci_scripts` seguem a convenção da Apple. O post-clone
confere o pacote local e executa as verificações Python/Swift. O pre-xcodebuild
reserva builds de `10001` a `99999` a partir do `CI_BUILD_NUMBER`, mantendo a versão
comercial. A edição ocorre apenas no checkout temporário do Cloud. Depois da
primeira entrega Cloud, o assistente local deve receber o maior build observado
na Apple para evitar números inferiores.

Configuração a aplicar no Xcode, Integrate → Create Workflow:

- Produto AtendeBem, equipe FWVSMZ9APG, identificador `io.atendebem.app`.
- Repositório Oryum-Tech/AtendeBem_IOS e scheme AtendeBem.
- Validação: mudanças em main e pull requests; Build, Analyze e Test em iPhone/iPad.
- Distribuição: início manual, Archive Release, TestFlight interno. Publicação
  pública permanece uma ação explícita após QA e requisitos de revisão.
- Xcode com Swift 6 e SDK compatível com o código; pacote sem dependências externas.

O manifesto existente em `xcshareddata/xcodecloud` não comprova que a Apple tem
acesso ao GitHub nem que um workflow executou. A ativação só está confirmada após
conectar o provedor na Apple e obter um build Cloud real. Não guardar chaves ou
credenciais Apple no repositório.

Referências: [Scripts personalizados](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
e [Primeiro workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).

## Verificação de 03/10/2026

O pacote Swift e os recursos foram publicados em main e conferidos em um clone
limpo, que passou 57 verificações Python. O histórico Git interno do pacote foi
preservado no backup local ignorado `.local-repository-backups`; o repositório
principal agora contém os arquivos reais, sem submódulo ausente.

A execução [37142757194](https://github.com/Oryum-Tech/AtendeBem_IOS/actions/runs/37142757194)
do GitHub Actions não iniciou os trabalhos por bloqueio de cobrança da conta.
Esse bloqueio pertence ao GitHub Actions e não comprova bloqueio do Xcode Cloud.

O usuário informou ter conectado uma chave de acesso na Apple/Xcode. O controle
do navegador não está disponível nesta sessão. A consulta oficial de leitura dos
workflows com uma credencial Apple local retornou HTTP401; foi solicitado
identificar se a chave conectada é do GitHub ou da API Apple e, quando aplicável,
informar apenas o Issuer ID e Key ID. Não foi solicitado arquivo de chave ou token.

O projeto Release foi inspecionado sem compilar: nome, bundle, equipe, versão,
Swift6, destino iOS17 e famílias1/2 conferidos. `Config/XcodeCloud.plan.json`
registra o ambiente e os dois fluxos a aplicar. Esse arquivo é um plano revisável,
não um formato importável nem prova de workflow ativado na Apple. Nenhuma chave
privada, credencial clínica ou token precisa ser incluído no ambiente de build.
