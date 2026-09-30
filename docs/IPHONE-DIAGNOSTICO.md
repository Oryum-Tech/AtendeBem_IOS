# iPhone físico — 29/09/2026

## Falha de preparação no Xcode

A captura enviada pelo usuário mostra `dyld_shared_cache_extract_dylibs failed`, domínio `DVTDeviceSymbolsCoordinatorErrorDomain`, código 908, durante a preparação do dispositivo.

O ambiente tem Xcode 27.0 (27A266a). O iPhone físico conectado foi identificado pela ferramenta da Apple como iPhone 17 Pro Max, modelo iPhone18,2. A pasta de suporte corresponde ao iOS 27.0 (24A437).

O disco foi observado com 155 MiB e depois 112 MiB livres. Durante a consulta do dispositivo, o próprio `xcrun` retornou `errno=No space left on device` ao tentar criar seu cache; o shell também não conseguiu criar um arquivo temporário. A insuficiência de armazenamento ficou comprovada nesta investigação, embora não tenha sido capturado um log interno da extração atribuindo o código 908 diretamente a `ENOSPC`.

## Recuperação executada

A pasta `~/Library/Developer/Xcode/iOS DeviceSupport/iPhone18,2 27.0 (24A437)` ocupava aproximadamente 9,8 GiB: 7,1 GiB em `.tmp` e 2,7 GiB em `arm64e`, com marcadores de segmentos já processados.

Após conferir processos e verificar com `lsof` que os arquivos temporários não estavam abertos, somente o subdiretório `.tmp` dessa versão/dispositivo foi removido. O caminho, o proprietário e a ausência de links simbólicos foram conferidos antes da remoção. Os símbolos já extraídos, o projeto, os arquivos pessoais e os dados do iPhone foram preservados.

O espaço livre passou para 7,2 GiB imediatamente após a limpeza; uma medição posterior mostrou 6,5 GiB. O Xcode pode recriar os temporários em uma próxima preparação. A extração completa de símbolos ainda não foi revalidada; não iniciar novas tentativas repetidas antes de haver margem de armazenamento.

## Instalação do AtendeBem

O bundle de desenvolvimento já compilado em `~/Library/Developer/Xcode/DerivedData/AtendeBem-futneocxfaohpfgpjjssisjfagpd/Build/Products/Debug-iphoneos/AtendeBem.app` passou na verificação local de assinatura quando executada com acesso aos serviços do sistema. A primeira tentativa limitada pelo ambiente retornara erro de confiança; ela não foi tratada como confirmação de assinatura inválida após a verificação autorizada passar.

- Bundle ID: `io.atendebem.profissionais`.
- Versão: **0.1.0**, build **1**.
- SDK: iPhoneOS 27.0; versão mínima: iOS 17.0.
- `devicectl` inicialmente confirmou que o app não estava instalado.
- A instalação desse bundle no aparelho **terminou com sucesso**, pelo comando oficial `devicectl device install app`.
- O lançamento direto, sem anexar o debugger, foi recusado pelo iOS porque o aparelho estava bloqueado: `FBSOpenApplicationErrorDomain`, código 7, `Locked`.

O usuário foi orientado a desbloquear o iPhone e manter a tela acesa; pode abrir o ícone AtendeBem e entrar manualmente com sua conta de homologação. Nenhuma senha, código de desbloqueio ou sessão foi solicitada para armazenamento no projeto.

**Instalação confirmada não comprova abertura, login, sincronismo, uso clínico ou distribuição.** Essas verificações continuam pendentes até observação real. Esta instalação de desenvolvimento não é um envio ao TestFlight ou à App Store.
