# Archive e Transporter

Configuração única em `Config/App.xcconfig`, aplicada ao target do app tanto no projeto Xcode existente quanto no `project.yml`. Nome no aparelho, nome do bundle e produto: **AtendeBem**. Identificador: **io.atendebem.app**, confirmado no App Store Connect para **AtendeBem - Gestão Clínica**, Apple ID **6762195438**, SKU `atendebem-ios`. O antigo build 1.0.0 (2) usava `io.atendebem.profissionais` e não corresponde a esse cadastro; não utilizá-lo para envio. Versão preparada: **1.3.0 (26)**. A versão de distribuição identifica o binário; não declara paridade completa nem aprovação da Apple.

## Caminho simples

Abra **Preparar AtendeBem.command** na raiz do projeto. Ele executa, na ordem:

1. Confere pelo menos 8 GiB livres, sem apagar arquivos. Esse limite é uma proteção inicial; a necessidade real depende dos caches e do SDK.
2. Incrementa o número de build, considerando a configuração atual, os Archives desse bundle no projeto e no Organizer do Xcode e o último build observado no TestFlight, registrado em `app-store-connect.json`. Reserva o número mesmo se uma etapa posterior falhar, evitando reutilização local.
3. Gera um Archive **Release para iOS**, com assinatura, dSYM e manifesto. Usa `DerivedData` deste projeto.
4. Confere nome, bundle ID, versão, build e equipe no aplicativo e nos metadados do Archive. O identificador também precisa corresponder ao cadastro conferido em `release/app-store/app-store-connect.json`. Registra resultado, logs e recibo local.
5. Exporta um IPA para **App Store Connect**, sem enviá-lo. Xcode pode atualizar certificados/perfis da equipe autenticada durante a exportação.
6. Confere a identidade do IPA e solicita sua abertura no **Transporter**. Confira se o pacote aparece; algumas versões exigem **Adicionar Pacote** e a seleção do IPA. A abertura do aplicativo não comprova importação nem entrega.

O assistente para na primeira falha. Ele não publica, não submete para revisão e não envia ao TestFlight automaticamente. Também não altera repositórios web nem avança o baseline de sincronismo. Não execute Archive no Xcode e este assistente ao mesmo tempo: o lock protege as execuções do assistente entre si.

## Comandos separados

```sh
# Ver identidade, armazenamento e presença do Transporter.
python3 scripts/release_ios.py status

# Reservar próximo build; opcionalmente trocar a versão pública.
python3 scripts/release_ios.py prepare --version 1.3.0

# Compilar exatamente a versão e o build já reservados.
python3 scripts/release_ios.py archive

# Exportar um Archive já conferido; não refaz a compilação.
python3 scripts/release_ios.py export 'release/builds/AtendeBem-1.3.0-26/AtendeBem.xcarchive'

# Conferir um Archive ou IPA sem enviar.
python3 scripts/release_ios.py inspect 'release/builds/AtendeBem-1.3.0-26/AtendeBem.xcarchive'

# Abrir o IPA já exportado no Transporter.
python3 scripts/release_ios.py transporter 'release/builds/AtendeBem-1.3.0-26/AppStore/AtendeBem.ipa'
```

Os caminhos acima exemplificam o build 26. Cada nova preparação informa sua pasta. Nenhum Archive existente é sobrescrito. Se a exportação falhar e deixar uma pasta `AppStore`, preserve o log e mova essa pasta incompleta antes de repetir somente a exportação. O assistente recusa sobrescrevê-la.

## Entrega automatizada opcional

O comando `upload` está separado do comando `release`. Só use depois de decidir enviar o IPA específico. Requer uma chave de equipe do App Store Connect: `ASC_KEY_ID` e `ASC_ISSUER_ID` no ambiente; arquivo `AuthKey_<ID>.p8` em `~/.appstoreconnect/private_keys/`, com acesso restrito. Não coloque a chave no projeto, no chat, nos recibos nem no controle de versão. O script não lê nem copia a chave; o Transporter da Apple a utiliza.

```sh
python3 scripts/release_ios.py upload '/caminho/AtendeBem.ipa' --confirm-upload
```

Não há senha incorporada. A interface do Transporter permite a alternativa de autenticar manualmente com a conta Apple. Não automatizamos sua senha nem a autenticação em dois fatores.

O registro do aplicativo no App Store Connect deve ter exatamente o identificador configurado. O incremento considera o último build remoto registrado, mas não consulta a Apple em tempo real. Confira o TestFlight antes da entrega e atualize `last_observed_build` se outra máquina enviou uma versão mais recente. A conferência de 02/10/2026 encontrou 1.2.1 (25), por isso esta entrega continua em 1.3.0 (26). Não reutilize um build recebido pela Apple. O número não é alterado silenciosamente na exportação (`manageAppVersionAndBuildNumber=false`).

Se o Transporter informar **“Nenhum registro de aplicativo adequado foi encontrado”**, confira a conta/equipe selecionada e o cadastro do app em App Store Connect. A existência de um certificado ou perfil para o bundle ID não cria esse cadastro. Corrija o registro ou a equipe antes de repetir a importação; não troque o identificador arbitrariamente nem gere outro build para esse erro.

## Evidências e limites

Saídas ficam em `release/builds/AtendeBem-<versão>-<build>/`, ignoradas pelo Git. `archive.log`, `signature.log`, `archive-receipt.json`, `export.log` e `export-receipt.json` registram as etapas efetivamente concluídas. O recibo de exportação contém o SHA-256 do IPA. Uma etapa interrompida não gera recibo de sucesso.

Um Archive assinado com certificado de desenvolvimento pode ser re-assinado na exportação para distribuição. Não confundir a assinatura do Archive com um IPA já elegível para envio. O Xcode precisa de conta, associação ao Apple Developer Program, certificados e perfis válidos para a equipe configurada. O projeto não afirma que essas condições foram atendidas só por conter um Team ID.

O pacote de textos e políticas é preparado separadamente por `scripts/app_store_bundle.py`. Capturas reais, vídeo, auditoria de privacidade, acessibilidade, QA com homologação e revisão da loja continuam com seus critérios em `release/app-store/release-status.json`. Transferência concluída pelo Transporter também não comprova processamento, aprovação ou publicação pela Apple.

Referências verificadas em 02/10/2026: [Apple — upload de builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [Apple — preparação para distribuição](https://help.apple.com/xcode/mac/current/en.lproj/dev91fe7130a.html), [Transporter](https://support.apple.com/guide/transporter-app/welcome/mac). As opções de exportação e upload foram conferidas também na ajuda do Xcode 27 e do Transporter 4.1 instalados.
