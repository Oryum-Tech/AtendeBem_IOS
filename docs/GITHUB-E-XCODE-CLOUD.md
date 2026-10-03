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
