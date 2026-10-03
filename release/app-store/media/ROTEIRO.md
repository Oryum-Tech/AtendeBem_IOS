# Imagens e vídeo — produção com interface real

Direção: fundo da própria interface, foco na tarefa humana e frases curtas. Não redesenhar telas que ainda não existem, simular selos Apple, inventar avaliações ou prometer resultado clínico. As primeiras imagens precisam mostrar o uso, e não apenas login ou marca.

## Capturas

O arquivo `specification.json` contém oito cenas, copys e dimensões. Conjunto principal iPhone 6,9 pol.: **1320 × 2868 px**. iPad 13 pol.: **2064 × 2752 px**. Esses dois tamanhos são escolhas aceitas; outros tamanhos oficiais podem ser adicionados se a distribuição exigir. Não esticar uma captura de iPhone para criar iPad.

Gerar oito imagens por plataforma, em JPEG ou PNG opaco. O plano usa JPEG para evitar transparência. A ordem é Hoje, Documentos/modelos, Histórico, Agenda, LARI, Equipe, Comunidade e Relatórios. Captura de Configurações pode complementar a sequência. As frases são diretrizes editoriais; a primeira entrega pode usar a captura nativa inteira, sem texto sobreposto. Na composição final, preservar legibilidade e proporções, usando a captura real como elemento principal.

Capturar no build final com conta demonstrativa, data controlada, notificações pessoais ausentes e dados fictícios. Guardar o original e um recibo de procedência com build, dispositivo/OS, cena, data e SHA-256 do arquivo. O recibo não contém credenciais. Inspecionar toda a imagem antes de marcar ausência de dados pessoais.

O validador verifica formato, dimensões, ausência de alpha e hash correspondente ao recibo. A revisão humana da veracidade, legibilidade e privacidade continua necessária. Não preencher os recibos até a captura real.

## Vídeo de 25 segundos

Gravar a navegação real; cortes só entre tarefas coerentes. Não utilizar animações que representem recursos inexistentes. O vídeo pode ser compreendido sem som; as legendas estão em `preview.pt-BR.srt` e a locução é opcional.

| Tempo | Captura | Texto/locução |
|---|---|---|
| 0–5 s | Hoje com quatro atalhos | Comece pelo que precisa fazer. |
| 5–10 s | Modelo de receita fictício e revisão dos itens | Menos repetição. Revisão em cada cuidado. |
| 10–15 s | Histórico unificado de paciente fictício | Acompanhe a continuidade do atendimento. |
| 15–20 s | LARI: relatório financeiro de período conhecido em clínica fictícia, ou receita com paciente fictício em revisão | Peça uma tarefa. Confira cada etapa. |
| 20–25 s | Configurações e atalhos | Seu jeito de trabalhar. AtendeBem. |

Poster sugerido: segundo 3, com os atalhos da Hoje visíveis. Se o corte acontecer exatamente nesse frame, ajustar o poster para um quadro estável e atualizar o recibo. Gravar cada plataforma com seu próprio layout; não converter o vídeo de iPhone em uma falsa interface iPad.

Exportar iPhone em **886 × 1920** e iPad em **1200 × 1600**, H.264 progressivo, máximo 30 fps, alvo 10–12 Mbps, até 500 MB; duração admitida 15–30 segundos. O script de exportação usa 25 s/30 fps e áudio AAC estéreo 48 kHz se fornecido. Usar apenas áudio próprio/licenciado, com comprovante de direitos. Nenhuma faixa de terceiros é incluída neste pacote.

O arquivo SRT não é um campo de legenda separado de App Store Connect: serve para a edição e para versões acessíveis fora da loja. As palavras essenciais precisam ser legíveis na própria imagem quando utilizadas; a narração não pode ser a única forma de entender o vídeo.

## Captura técnica

Preferir as ferramentas de simulador do plugin Build iOS Apps. Para uma captura JPEG sem alterar pixels ou proporções, o comando nativo do simulador pode ser usado após selecionar o dispositivo correto:

```sh
xcrun simctl io "$ATENDEBEM_SIMULATOR_UDID" screenshot --type=jpeg /caminho/da/captura.jpg
```

O identificador deve vir da listagem real dos simuladores. Não usar `booted` quando houver mais de um dispositivo aberto. A gravação é feita com o app em execução; não preencher os arquivos de destino com telas de apresentação ou vídeos gerados por IA.

**Situação:** roteiro e especificação preparados; capturas e vídeos ainda não produzidos. Xcode instalado; Archive 1.3.0 (30) gerado. Capturar somente após homologação do build final. Sem conta demonstrativa e integração validada, login isolado não representa a página completa solicitada.

Para as tarefas LARI do incremento 36, capturar somente interface executando na versão correspondente. Receita deve mostrar a etapa de conferência, sem simular assinatura ou entrega; relatório deve conter valores fictícios conhecidos e período visível. Não usar o comando com nome real em imagens da loja. Modelos clínicos fora do atalho e relatórios parciais não devem ser anunciados como automação completa.
