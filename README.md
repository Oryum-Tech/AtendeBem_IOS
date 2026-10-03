# AtendeBem iOS

Aplicativo nativo em Swift 6 e SwiftUI para profissionais e clínicas, com quatro abas: Hoje, Agenda, Pacientes e Mais. Consome os mesmos serviços usados pela web, respeitando contexto de clínica e permissões. A paridade completa ainda está em desenvolvimento.

## Abrir e compilar

Abra `AtendeBem.xcodeproj` e selecione o scheme compartilhado **AtendeBem**. O pacote `Packages/AtendeBemKit` está incluído no repositório; não exige um checkout dos serviços. Deployment target iOS 17.0, Swift 6. O identificador é `io.atendebem.app`, equipe Apple `FWVSMZ9APG` e Apple ID `6762195438`.

`Config/App.xcconfig` define nome e versão. `project.yml` permite regenerar o projeto com XcodeGen, mas o projeto já incluído abre diretamente no Xcode.

## Testar

```sh
bash scripts/test-local.sh
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Os testes locais verificam contratos, sessão, permissões, estado e automação. Não substituem validação autenticada no serviço nem execução e acessibilidade em iPhone/iPad.

## Entrega e nuvem

O build **1.3.0 (40)** foi processado pela Apple em 03/10/2026 e está disponível no TestFlight. A submissão pública ainda depende de QA, materiais reais, conta demonstrativa, contato de revisão e requisitos operacionais de privacidade e moderação.

Abra **Preparar AtendeBem.command** para preparar Archive, exportar IPA e abrir o Transporter. O envio é explícito. Credenciais ficam fora do projeto. Consulte [Archive e Transporter](docs/ARCHIVE-E-TRANSPORTER.md).

O destino Git é [Oryum-Tech/AtendeBem_IOS](https://github.com/Oryum-Tech/AtendeBem_IOS). GitHub Actions valida o código e compila sem assinatura. Os scripts do Xcode Cloud estão preparados; a conexão e a execução remota precisam de confirmação na Apple. Consulte [GitHub e Xcode Cloud](docs/GITHUB-E-XCODE-CLOUD.md).

## Estrutura

- `App`: entrada iOS, ícone e manifesto de privacidade.
- `Packages/AtendeBemKit/Sources/AtendeBemCore`: contratos, rede, sessão e serviços.
- `Packages/AtendeBemKit/Sources/AtendeBemUI`: telas SwiftUI e estado.
- `Packages/AtendeBemKit/Tests`: testes de contratos e estado.
- `UITests`: jornadas nativas, sem dados de pacientes reais.
- `scripts` e `ci_scripts`: validação e preparação de entregas.
- `release/app-store`: textos e minutas para revisão; não comprova publicação.

## Produto atual

Login/MFA/recuperação, apresentação e cadastro nativos, agenda/fila, pacientes e histórico, consulta, receitas/documentos/exames, tarefas assistidas pela LARI, transcrição, relatórios, comunidade/chat, troca de clínica e configurações. Ações clínicas exigem revisão e permissões. A LARI não infere dose, frequência ou quantidade faltantes. O catálogo e o acesso ao Bulário não representam ingestão completa de todas as bulas.

Os fluxos específicos de cada profissão, sincronismo autenticado, conteúdo gerado por usuários e acessibilidade mantêm pendências registradas na [matriz de paridade](docs/PARIDADE.md). A versão web em produção permanece protegida: este projeto não modifica seus arquivos, branches, deploys ou banco.

Archives, IPAs, credenciais, capturas de feedback e evidências operacionais são locais e não são publicados no repositório.
