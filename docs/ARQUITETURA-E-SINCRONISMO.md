# Arquitetura e sincronismo

## Limite deste projeto

Todo o código novo fica nesta pasta. Os repositórios web, gateway e microsserviços foram consultados em modo leitura. Não foi aplicado deploy, migração, mudança de API nem alteração em seus arquivos. Há alterações preexistentes na versão web, que não pertencem a este trabalho.

O app é um cliente SwiftUI do gateway já usado pela web: `https://api.atendebem.io/v1`. O banco e as regras de negócio permanecem nos serviços existentes. Não existe segundo banco do AtendeBem no dispositivo, ponte WebView nem cópia de credenciais administrativas.

## Organização

- `App`: entrada do aplicativo iOS.
- `AtendeBemCore`: contratos Codable, transporte URLSession, sessão e serviços; testável como Swift Package.
- `AtendeBemUI`: SwiftUI e Observation, estado por tela, navegação e sessão global.
- `AtendeBem.xcodeproj`: aplicativo iPhone/iPad, iOS 17+, Swift 6.
- `project.yml`: especificação equivalente para regenerar com XcodeGen compatível.

## Contratos conferidos no código existente

| Operação | Contrato usado |
| --- | --- |
| Login | `POST /auth/login`, `{email, senha}` → tokens ou `mfaTicket` |
| Segundo fator | `POST /auth/mfa/verificar`, `{mfaTicket, codigo}` |
| Renovação | `POST /auth/refresh`, `{refreshToken}` → par rotativo |
| Recuperação de senha | `POST /auth/senha/solicitar`, `{email}`, mensagem sem revelar existência da conta |
| Troca obrigatória de senha | `PUT /usuarios/me/senha`, `{senhaAtual, novaSenha}`; 12 caracteres, letra, número e diferença da anterior |
| Conta e permissões | `GET /me`, incluindo `papeis`, `recursos`, `deveTrocarSenha` |
| Clínicas | `GET /clinicas-do-usuario`; contexto ativo identificado pelo claim `clinicaId` somente para apresentação |
| Mudança de clínica | `POST /auth/trocar-clinica`, `{clinicaId}` → novos tokens |
| Agenda | `GET /agendamentos?dia=YYYY-MM-DD` → `{meta, itens}` |
| Fila | `GET /agendamentos/fila?dia=YYYY-MM-DD` |
| Confirmação | `PATCH /agendamentos/{id}`, `{status: "confirmed"}` |
| Pacientes | `GET /pacientes?busca=...&page=...&perPage=25`; nomes em lote por `ids`, máximo de 100 por lote |
| Ficha | `GET /pacientes/{id}`; servidor mantém escopo/vínculo e mascaramento |
| Resumo de consultas | `GET /agenda/pacientes/{id}/historico` |

Fontes locais: `atendebem-svc-identidade/src/auth`, `src/usuarios`; `atendebem-svc-agenda/src/modules/agendamentos`; `atendebem-svc-pacientes/src/modules/pacientes`; `atendebem-webapp/lib/auth`, `lib/nav.ts` e componentes correspondentes. Contrato lido no checkout não comprova a versão implantada: E2E autenticado permanece necessário.

## Sincronismo implementado e limites

- Leituras diretamente no servidor ao abrir a tela, retornar ao primeiro plano, puxar para atualizar e a cada 30 segundos nas listas/ficha enquanto suas tarefas estiverem ativas.
- A mesma fonte de dados permite que uma confirmação feita no iOS fique disponível à web quando esta consultar a API. A atualização imediata da interface web depende do mecanismo existente nela; não foi alterado.
- Escritas aguardam o servidor e não são repetidas automaticamente. Depois de falha ambígua, o app relê o registro. Não há fila de escrita offline.
- Trocar clínica invalida respostas em andamento e recria a navegação. Sair invalida tarefas de renovação, remove a sessão e os dados da interface.
- Renovações concorrentes compartilham uma única operação. Isso evita reutilizar o refresh token rotativo e revogar inadvertidamente sua família.
- Erros temporários de renovação preservam a sessão; refresh rejeitado com 401 encerra a sessão.
- A UI mostra a última atualização e falhas, sem declarar sincronização concluída quando um carregamento falha. Nome não carregado não é apresentado como paciente inexistente.
- Os endpoints de agenda consultados definem o dia em UTC−03:00. A UI declara esse fuso. O webapp já possui abstração de fuso configurável: generalizar o iOS exige confirmar a configuração efetiva por clínica e a semântica do backend para não deslocar horários.

**Isso é atualização periódica dos módulos implementados. Ainda não é sincronismo total e instantâneo de todas as funções.** Push/APNs, invalidação por eventos, conflitos de edição de prontuário, trabalho offline e atualização em segundo plano precisam de projeto e testes próprios. iOS não garante execução contínua em segundo plano.

## Evolução coordenada web e iOS

O detector `scripts/sync_watch.py` acompanha mudanças locais e commits remotos de 29 repositórios sem alterá-los. A automação desta tarefa analisa o impacto e trabalha nas adaptações nativas, exigindo evidências antes de encerrar uma mudança. O fluxo, os comandos, o CI preparado e os limites de distribuição estão em [AUTOMACAO-WEB-IOS.md](AUTOMACAO-WEB-IOS.md). Esse acompanhamento de código é separado da atualização dos dados descrita acima.

## Segurança técnica do cliente

Sessão no Keychain com `WhenUnlockedThisDeviceOnly`. URLSession efêmera, sem cache, cookies ou credenciais persistentes. HTTPS obrigatório, redirecionamentos recusados, caminhos compostos por segmentos validados e query estruturada. Não há logging de token, senha, resposta clínica ou CPF. Papéis visuais ajudam a navegação; a autoridade permanece nos guards e no escopo do servidor.

O refresh token e a sessão do iOS são próprios; não copiamos a sessão localStorage da web. Não existe endpoint de logout/revogação no controller de autenticação consultado; o logout atual é local, como no cliente web. Revogação remota e gestão de dispositivos devem entrar na análise futura, sem inventar rotas.

## Verificação exigida antes de uso clínico

Compilar para o SDK iOS, executar em iPhone/iPad, testar Keychain real e acessibilidade, usar conta de homologação e comparar leituras e escritas no navegador e no dispositivo. Verificar MFA, expiração, troca de clínica durante request, conta sem permissão, conexão interrompida após gravar, alterações concorrentes e restauração do app. Testes de transporte simulado comprovam invariantes locais; não comprovam sincronismo em produção.
