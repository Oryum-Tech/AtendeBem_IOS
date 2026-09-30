# Simulator — diagnóstico de 29/09/2026

O bloqueio ocorre antes de o AtendeBem executar. O usuário confirmou que o Simulator trava ou fecha também ao ser aberto manualmente.

## Evidências

- Xcode 27.0 (27A266a) e runtime iOS 27.0 instalados.
- Build Debug arm64 com a interface, núcleo e ícone concluído sem erros ou avisos.
- Verificação local de assinatura do bundle de simulador passou; não é assinatura de distribuição.
- CoreSimulator retornou `Mach -308`, `CoreSimulator server died` e `launchd failed to respond`.
- O log do CoreSimulator registra `Failed to start launchd_sim: could not bind to session, launchd_sim may have crashed or quit responding`.
- Uma inicialização chegou a `bootstatus: Finished`, mas a instalação não respondeu. A tentativa foi encerrada.
- Após recuperação direcionada do serviço, a última tentativa no iPhone 18 Pro Max excedeu 150 segundos em `bootstatus`; a instalação e o lançamento não chegaram a ser executados nessa tentativa.
- A medição posterior do disco mostrou **1,6 GiB livres**. Esse espaço reduzido é um possível fator contribuinte; o log inspecionado não comprovou erro `ENOSPC` como causa.

## Próxima recuperação

1. Salvar o trabalho aberto e reiniciar o Mac manualmente, para reiniciar também os serviços de simuladores. O Mac não foi reiniciado pelo agente.
2. Conferir Armazenamento nos Ajustes do Sistema e recuperar espaço com arquivos que o proprietário reconheça. Não remover projetos, simuladores ou arquivos pessoais indiscriminadamente.
3. Abrir o Simulator com um único iPhone e verificar se ele alcança e mantém a tela inicial antes de tentar instalar o app.
4. Com a tela inicial estável, instalar o bundle em `DerivedData/Build/Products/Debug-iphonesimulator/AtendeBem.app`, ou executar o scheme AtendeBem pelo Xcode.
5. O usuário entra manualmente com a conta de homologação. Validar autenticação, escopo de clínica, sincronismo e interface antes de produzir capturas e vídeos.

Se a inicialização continuar falhando após reinício e recuperação de espaço, coletar um diagnóstico do CoreSimulator e revisar o runtime instalado antes de recriar dispositivos. Apagar simuladores remove seus dados e não foi usado como solução indiscriminada nesta tarefa.

Nenhuma captura, gravação ou validação autenticada foi considerada concluída por causa de um build bem-sucedido.

## Erro de gravação do workspace no Xcode

O usuário relatou `Couldn't create workspace arena folder` na pasta `~/Library/Developer/Xcode/DerivedData/AtendeBem-futneocxfaohpfgpjjssisjfagpd`, com falha ao escrever `info.plist`.

- A primeira medição desta investigação encontrou **118 MiB livres e 100% de uso**; medições seguintes variaram para aproximadamente **1,06 GiB livres**.
- A pasta e o arquivo pertencem ao usuário `kalleby`, com permissão de escrita para o proprietário e sem flags de imutabilidade observadas.
- `plutil -lint` validou o `info.plist`, cujo `WorkspacePath` aponta para este projeto.
- Um teste fora do sandbox gravou e sincronizou (`fsync`) um arquivo temporário de **1 MiB na pasta exata** com sucesso. O arquivo temporário foi removido imediatamente.
- Não foi necessário alterar permissões, propriedade ou configuração do projeto. Não foi observada uma falha persistente de permissão nessa verificação.

O espaço livre criticamente baixo é a causa mais provável da falha de gravação relatada, mas o erro original não contém `ENOSPC` para confirmação definitiva. A gravação pontual passou; a compilação completa não foi repetida nessas condições de armazenamento. Recuperar espaço antes de retomar Xcode e Simulator.

## Limpeza limitada ao projeto

O cache SwiftPM `.build` deste projeto foi removido após a conclusão dos testes, recuperando cerca de 423 MiB. Código, testes, evidências e o bundle compilado em `DerivedData` foram preservados. Apesar da recuperação, outra medição chegou a **0,58 GiB livres** durante a sessão; a redução continuada do espaço não teve sua causa identificada. Nenhum arquivo pessoal ou projeto externo foi removido. Não foram iniciados novos simuladores após essa constatação.
