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
confere o pacote local e executa as verificações Python/Swift. O número final do
pacote é controlado pela sequência do produto na Apple. A primeira execução confirmou
que o valor provisório editado pelo pre-build é substituído pelo Xcode Cloud: o
build8 chegou ao TestFlight como8, não10008. A faixa foi então reservada no ajuste
oficial **Próximo número da compilação =10001**, salvo e conferido na Apple.
Depois de cada entrega Cloud, o assistente local deve receber o maior build observado
na Apple para evitar números inferiores. A versão comercial permanece1.3.0.

Configuração do produto e evolução dos workflows:

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

O acesso ao navegador oficial foi recuperado. Na Apple, o produto AtendeBem já
existia, mas o workflow Default ainda apontava para o repositório pessoal antigo.
A Apple confirmou o acesso a Oryum-Tech/AtendeBem_IOS e o workflow existente foi
salvo em03/10 às15:29 como **AtendeBem — Archive**, mantendo seu identificador
`40B7B87F-3D47-437C-88F0-CEE4969A022F`.

Configuração remota observada: projeto AtendeBem.xcodeproj; scheme AtendeBem;
branch main; autocancelamento; cache habilitado; Latest Release, então Xcode27
(27A266a) e macOS Golden Gate27 (26A428); Archive iOS com preparação para TestFlight
interno. Foram removidas somente as duas variáveis Supabase herdadas deste workflow,
que não são referenciadas pelo projeto atual. Não foram alterados serviços ou bancos.
Às15:39 foi salva a pós-ação Teste interno do TestFlight para o grupo existente
Beta Interna, com3 membros. Essa pós-ação será exercitada no próximo build.

A **Compilação8**, iniciada manualmente às15:30, confirmou o checkout do commit
`76dc1dcf588986eef9fbbe0a7c62ae70e6f907ff`. Seus registros confirmam57 testes Python,
22+334 testes Swift, resolução do pacote local, execução do pre-build e Archive
aprovados. A exportação para App Store e a preparação para App Store Connect também
foram aprovadas. Uma exportação adicional ad-hoc apresentou exit-code70, embora
uma tentativa subsequente conste como executada com sucesso. O resumo global confirmou **Processada com sucesso**, e o TestFlight listou
**1.3.0(8), Internos, Pronto para testar**. O erro transitório de ad-hoc não impediu
o resultado final. A numeração10001 foi salva depois dessa prova.

[Compilação8](https://appstoreconnect.apple.com/teams/bcf479dd-cead-46a2-8c30-e0bf4d977f00/xcode-cloud/products/069897D5-9B36-4398-8D07-275169FF2425/builds/d69137c7-c684-495d-87c0-650d77ccd0e9/summary).

O projeto Release foi inspecionado sem compilar: nome, bundle, equipe, versão,
Swift6, destino iOS17 e famílias1/2 conferidos. `Config/XcodeCloud.plan.json`
registra o ambiente e os dois fluxos a aplicar. Esse arquivo registra configuração observada e evoluções planejadas; não é um
formato importável. A ativação é comprovada pela configuração salva e compilação8. Nenhuma chave
privada, credencial clínica ou token precisa ser incluído no ambiente de build.
