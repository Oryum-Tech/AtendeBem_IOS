# Validação — 29/09/2026

## Atualização após instalação do Xcode

### Instalação em iPhone físico

O AtendeBem 0.1.0 (1) foi instalado com sucesso em um iPhone 17 Pro Max conectado, usando o bundle de desenvolvimento já compilado. Antes disso, a preparação de símbolos pelo Xcode falhava com código 908 e o ambiente chegou a retornar `No space left on device`. A remoção restrita aos temporários inativos dessa extração recuperou 7,1 GiB, preservando os símbolos já extraídos. A tentativa de abertura direta foi recusada porque o iPhone estava bloqueado. Login e validação funcional continuam pendentes. Evidências em [IPHONE-DIAGNOSTICO.md](IPHONE-DIAGNOSTICO.md).

### Compilação e histórico do Simulator

O usuário instalou **Xcode 27.0 (27A266a)** e o runtime **iOS 27.0** durante a preparação para a App Store. A compilação para simulador arm64 passou, incluindo o catálogo AppIcon de 1024 px, sem erros ou avisos no build final. A configuração Debug foi corrigida para usar `ONLY_ACTIVE_ARCH = YES`, compatível com os produtos do pacote local.

Os **13 testes Swift passaram novamente com o Xcode instalado**. Os **6 testes do pacote de publicação** também passaram. O ícone foi exportado do vetor existente e verificado como PNG de 1024 × 1024 sem alpha. O projeto continua em desenvolvimento, com quatro abas e escopo funcional parcial.

A instalação/execução encontrou falhas do CoreSimulator, inclusive `Mach -308` e `launchd failed to respond`. O usuário confirmou travamento/fechamento do Simulator também na abertura manual. Foram realizadas recuperação direcionada do dispositivo e reinicialização do serviço do simulador. Essas ações não equivalem à validação da interface ou ao login de homologação.

Evidências atualizadas: [compilação iOS](../release/app-store/evidence/IOS-BUILD.md), [testes Swift](../release/app-store/evidence/TESTES-SWIFT.txt), [publicação](../release/app-store/README.md). A conta de homologação será acessada manualmente pelo usuário; nenhuma credencial foi solicitada para armazenamento no projeto.

## Evidências da etapa inicial, antes da instalação do Xcode

- Pasta iOS inicialmente vazia, exceto por metadado do Finder.
- Contratos lidos no checkout da web e dos serviços de identidade, agenda, pacientes e gateway.
- Projeto `.pbxproj` validado sintaticamente com `plutil -lint`; referências internas e scheme compartilhado também conferidos.
- Fontes Swift passaram pela verificação sintática. Núcleo, telas SwiftUI e previews compilaram no target macOS do pacote, com Swift 6 e sem dependências de terceiros.
- Script `scripts/test-local.sh` validado com `bash -n`.
- API pública existente: `GET https://api.atendebem.io/v1/me` sem credenciais respondeu **HTTP 401**, confirmando alcance da rota protegida. Não foi realizado login nem lido ou alterado dado clínico.
- XcodeBuildMCP não conseguiu listar simuladores: `xcrun: error: unable to find utility "simctl"`.
- `xcodebuild -version`: exige Xcode, enquanto o diretório ativo é `/Library/Developer/CommandLineTools`.
- Busca por bundle `com.apple.dt.Xcode` não localizou instalação. Não foi instalado software de sistema nesta sessão.
- XcodeGen disponível em `/usr/local/bin/xcodegen`, mas é executável Intel (`x86_64`) e falha com `bad CPU type in executable`. O projeto incluído pode ser aberto diretamente.

## Testes locais

Suite de testes Swift criada para login/MFA, renovação concorrente, 401, falha temporária, logout com resposta atrasada, troca de clínica durante leitura, proibição de replay de gravações, HTTPS/caminhos, query, ausência de informação clínica, permissões e fuso da agenda.

**Resultado final: 13 testes aprovados, sem falhas.** Comando: `bash scripts/test-local.sh`. A última compilação incremental concluiu em 5,57 segundos; a execução dos testes em 0,069 segundos. Evidência completa em [TESTES-SWIFT.txt](TESTES-SWIFT.txt).

Primeiro houve falha de acesso ao cache; com caches temporários, o sandbox interno do SwiftPM foi recusado pelo ambiente. A execução local foi então autorizada fora dessa restrição. Também foi necessário informar os caminhos do framework Testing e de `lib_TestingInterop.dylib`, ambos já instalados nas Command Line Tools. O script encapsula essa configuração, sem mudar o sistema. Depois de recompilar, a suíte rodou e passou. Nenhuma falha de configuração foi contada como aprovação.

Os testes usam transporte simulado e dados sintéticos, e verificam invariantes do cliente. **Não comprovam execução em iOS, acesso ao Keychain no iPhone nem sincronismo autenticado com produção.**

Os hashes dos quatro arquivos web usados como referência de navegação/contratos permaneceram iguais durante a verificação final. O status Git mostra a pasta `AtendeBem IOS/` como nova no repositório pai; não foi feito commit nem push.

## O que ainda não foi comprovado

- Lançamento e comportamento em simulador/aparelho; a compilação para SDK iOS já foi comprovada na atualização acima.
- Login real, MFA real e persistência real do Keychain em iPhone.
- Gravação pela UI nativa e comparação com a versão web.
- Notificações APNs, atualização em segundo plano e conflitos entre edições simultâneas.
- VoiceOver, Voice Control, Dynamic Type máximo, contraste, redução de transparência/movimento, modo escuro e teclado em dispositivos.
- Funcionamento integral de prontuário, prescrição, exames, especialidades, gestão e demais módulos planejados.

## Próxima execução com Xcode

1. SDK/runtime instalados e compilação para iOS verificados; estabilizar o CoreSimulator.
2. Instalar o binário compilado e executar as telas.
3. Validar a experiência de autenticação com conta de homologação; não colocar senha/token no repositório.
4. Abrir o mesmo paciente e agenda na web e no app, comparar IDs, clínica, horários, escopo e campos omitidos.
5. Em dados de homologação, confirmar agendamento no app e observar a leitura da mesma alteração na web; repetir alteração permitida na web e observar a atualização no app.
6. Testar conexão interrompida depois do envio, 401/403/409/429/5xx, troca de clínica durante resposta e logout durante renovação.
7. Auditar iPhone pequeno, iPad, rotação, maiores fontes, VoiceOver e alcance das ações nos formulários.
8. Corrigir problemas observados antes de considerar a base apta a uso clínico ou distribuição.
