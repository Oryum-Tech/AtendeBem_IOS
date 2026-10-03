> Incremento em preparação: **1.3.0 (40)**, com cadastro nativo, oferta consultada no catálogo, autorização de texto geral da LARI persistente/revogável, avatares e relatórios mais legíveis. A compilação para Simulator foi confirmada pela validação central, mas este registro não confirma execução autenticada, Archive/IPA40, upload ou conta demonstrativa. O início nativo de exclusão de conta está implementado; operação DPO/QA, comunidade/moderação e demais requisitos de revisão pública continuam pendentes.

> Histórico preservado: o incremento35 teve 200 testes locais aprovados, Archive/IPA assinados e importação no Transporter, com entrega então pendente por falha do controle da janela. [Evidências35](evidence/ARCHIVE-1.3.0-35.md). O registro34 documenta entrega e prontidão para teste interno naquele momento; esses resultados não validam o40.

# AtendeBem — pacote de preparação para a App Store

Atualizado em 03/10/2026 para 1.3.0 (40). Idioma: português do Brasil. Público: profissionais e clínicas. **Ainda não é uma submissão pronta.** O app completo continua em desenvolvimento; esta pasta prepara sua publicação e registra os impedimentos reais.

## Materiais

- `metadata/pt-BR.json`: fonte única dos campos da loja, limitada às funcionalidades implementadas.
- `metadata/pt-BR/`: textos separados para copiar para App Store Connect, gerados pelo script.
- `preview/index.html`: página local para revisar textos, roteiro de imagens e pendências. Não é uma página publicada nem contém capturas fictícias.
- `policies/`: minutas de privacidade, termos do aplicativo, direitos/exclusão, uso clínico/medicamentos e suporte.
- `site/`: versões HTML dessas minutas, com aviso de revisão e bloqueio de indexação. Não foram publicadas.
- `privacy/`: inventário, respostas propostas e manifesto candidato. Não declarar coleta como inexistente apenas porque o app usa Keychain.
- `review/`: notas em inglês, roteiro da conta demonstrativa, TestFlight e questionários de classificação/comercialização.
- `media/`: oito cenas por dispositivo, texto das imagens, roteiro de vídeo de 25 segundos, legendas e especificações.
- `brand/`: marca original, ícone de 1024 px exportado e inspecionado, incluído no catálogo do projeto.
- `release-status.json`: evidências que precisam existir antes do envio. Nenhum item é concluído automaticamente por produzir uma minuta.
- `SOURCES.md`: referências oficiais e data de consulta.

## Gerar e conferir

Na raiz do projeto:

```sh
python3 scripts/app_store_bundle.py render
python3 scripts/app_store_bundle.py validate
python3 scripts/app_store_bundle.py validate --submission
python3 scripts/app_store_bundle.py package
```

O segundo comando valida os materiais disponíveis. O terceiro também exige evidências de publicação, mídia real e binário; **deve falhar enquanto houver pendências**. O ZIP chama-se pacote de preparação e não inclui senhas, certificados, registros clínicos ou mídia bruta.

## O que falta para declarar pronto

1. Concluir e validar no iOS o escopo do app completo registrado em `../../docs/PARIDADE.md`.
2. QA em simuladores e dispositivos. O histórico registra Archives Release e targets de testes iOS compilados no Xcode 27; cada resultado deve ser associado ao seu build. Para o40, execução de UI, acessibilidade e sincronismo com homologação permanecem pendentes neste registro; a instalação de runtime anterior não comprova disponibilidade atual do Simulator.
3. Concluir entidade publicadora, contratos, territórios e modelo comercial. O cadastro do app já foi conferido: `io.atendebem.app`, Apple ID 6762195438, equipe FWVSMZ9APG. Dados corporativos encontrados no site ainda aguardam confirmação operacional.
4. Confirmar inventário do backend, retenção, fornecedores e transferências; consolidar política e declarações da loja, manifesto e archive.
5. Capturar telas e vídeos do build final com dados sintéticos. Dimensionamento correto sem autenticidade não basta.
6. Publicar e testar URLs de privacidade e suporte, disponibilizar conta demonstrativa isolada e concluir TestFlight.
7. Gerar e conferir Archive/IPA40, entregar somente o pacote autorizado e observar o resultado real no Transporter/App Store Connect. Histórico: a entrega do **1.3.0 (34)** foi confirmada no Transporter em02/10 às21h40, com processamento concluído; incrementos posteriores têm evidências próprias. [Recibo do34](evidence/ARCHIVE-1.3.0-34.md). O resultado antigo não comprova entrega do40.
8. Validar a operação DPO e o QA da exclusão, cujo início nativo está em Mais → Configurações → Minha conta → Excluir minha conta. Iniciar o fluxo não comprova conta apagada nem protocolo de API. Preparar denúncia, bloqueio e moderação da comunidade antes da revisão pública; as funções de comunidade permanecem no escopo, sem ocultação silenciosa.

As políticas contêm textos substanciais para revisão; não constituem certificação jurídica, enquadramento sanitário definitivo ou garantia de aprovação pela Apple. Os pontos factuais específicos ainda desconhecidos estão no registro de pendências, sem inventar práticas.

Nenhum arquivo da web, backend ou infraestrutura foi alterado. A política geral atualmente acessível pelo app é a já publicada no site; o complemento específico de iOS precisa ser consolidado e publicado antes do lançamento.

As notas e o roteiro atual estão em `review/NOTAS-EN.txt`, `review/CONTA-E-TESTFLIGHT.md` e `review/QUESTIONARIOS.md`; os roteiros numerados anteriores permanecem como histórico. As condições do cadastro são consultadas no catálogo público; sete categorias de cadastro não significam módulos clínicos especializados concluídos. Comunidade e comunicação têm limitações registradas; a preparação não deve ser confundida com submissão pública pronta.
