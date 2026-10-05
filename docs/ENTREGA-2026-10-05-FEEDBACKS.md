# Correções para a próxima entrega — 05/10/2026

## Feedbacks consultados no TestFlight

Os quatro relatos mais recentes observados são da versão 1.3.0 (40), em 03/10/2026: busca de CID, erro ao iniciar gravação, ausência do logo do Meu Prontuário e alinhamento da LARI. A leitura dos anexos não reproduziu a causa clínica ou técnica dos dois primeiros problemas.

- CID: campo de busca visível por código ou descrição, estados inicial/vazio/erro, limpeza e nova tentativa; o contrato continua `GET /sugestoes/cid?q`. Resultados e seleção exigem o mesmo termo, clínica e acesso da requisição.
- Áudio: contexto conferido antes da permissão, diagnóstico por etapa e mensagens de gravação específicas. Autorizações de participantes e de processamento continuam separadas; parar não envia automaticamente. A guarda de acesso atual verifica contexto/cancelamento, não disponibilidade do serviço ou plano.
- Meu Prontuário: PNG original do kit de imprensa, com proveniência em `MEU-PRONTUARIO-LOGO-PROVENANCE-2026-10-05.json`; nenhuma promessa de sincronismo entre os aplicativos independentes foi acrescentada.
- LARI: cabeçalho compacto, quatro tarefas permitidas inicialmente, expansão e busca por todas as tarefas autorizadas. Cartões de altura flexível, largura máxima de 840 pontos no iPad e uma coluna com tamanhos de texto de acessibilidade. Rotas, rascunhos e consentimentos preservados.
- Cadastro: removidos identificadores dos contêineres que substituíam os identificadores dos controles no Cloud 10003. O teste exige ações e campos acessíveis ao toque. A oferta informa que há planos elegíveis, conforme o catálogo.

## Validação e seus limites

A revisão independente dos diffs não encontrou regressão concreta. Parse Swift, conferência do catálogo e `git diff --check` passaram. O build de SDK anterior compilou app e testes, mas antecede as quatro alterações de feedback; ele não valida o código final.

O runtime oficial iOS 27.0 foi instalado. A tentativa local de executar os testes públicos foi cancelada antes de iniciar casos: Simulator no logo Apple, falhas IOSurface e `NSMachErrorDomain -308` no runner. Foram encerrados somente os processos dessa tentativa e desligados os dois dispositivos de QA; dados, runtimes, projetos e Archives preservados. Não há captura do app dessa rodada nem aprovação de testes funcionais.

A próxima execução do Xcode Cloud deve compilar e testar o SHA efetivamente publicado. Testes de telas clínicas continuam pulando quando não existe sessão de homologação; os públicos não substituem consulta real de CID, gravação, transcrição ou sincronismo. Não encerrar esses feedbacks como resolvidos em execução antes dessa validação.

## Preparação da loja e decisão do usuário

O usuário decidiu manter a comunidade e aguardar a implementação dos controles no serviço. Filtro, denúncia, bloqueio e atendimento da moderação continuam necessários; o cliente não recebeu botões com efeitos fictícios. A submissão pública permanece pendente dessa implementação e da validação dos demais itens de revisão.

Foi autorizada uma única exceção à preservação da web: atualizar a política pública de privacidade. O texto é preparado numa cópia isolada do repositório da landing; nenhum arquivo do checkout compartilhado, serviço ou banco faz parte dessa autorização. Publicação e vigência só serão registradas após confirmar a página pública.

Na Apple foram observados: versão 1.3.0 em preparação, sem build selecionado e sem mídia; contato de revisão preenchido; credenciais demonstrativas ausentes; tipos de dados selecionados, ainda sem configuração completa; direitos sobre conteúdo e declaração regulatória pendentes. Não preencher campos desconhecidos como se estivessem comprovados. Capturas e vídeo finais precisam mostrar o app real, com origem e dados sintéticos conferidos.

Evidências locais: `release/app-store/evidence/2026-10-05-feedback-cid-audio/`, `2026-10-05-simulator-environment/`, `2026-10-05-store-audit/`. Relatórios locais não constituem aprovação da Apple ou prova de publicação.
