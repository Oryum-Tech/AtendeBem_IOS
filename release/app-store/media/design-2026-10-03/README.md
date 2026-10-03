# Direção visual da App Store — 03/10/2026

O conjunto contém 18 layouts editáveis: oito benefícios e uma entrada complementar,
cada um com versão iPhone e iPad. `index.html` permite revisar a sequência.
`campaign.json` guarda as copys, a ordem e a tela real necessária para cada quadro.

## O que foi produzido

- Fundo editorial original, gerado pela ferramenta integrada `image_gen`, em
  azul-marinho e esmeralda. A IA produziu somente decoração; nenhuma interface.
- Marca oficial copiada do catálogo nativo e composição tipográfica determinística.
- Prévia `09-entrada-iphone-preview.png`, 1320 × 2868, opaca, com o login realmente
  capturado no Simulator. A imagem original é preservada em `assets/login-real.png`.
  O enquadramento mantém a proporção e o conteúdo; não fabrica dados, controles,
  assinatura, resultado clínico ou resposta da LARI.
- Layouts iPad em 2064 × 2752, aguardando as capturas próprias de iPad.

A captura do login veio do Debug40, realizada antes da inclusão final do fluxo de
exclusão de conta. Não é evidência visual do Archive40 nem do build Cloud10001.
A prévia foi inspecionada quanto a legibilidade e dimensões. Ainda requer recaptura
do binário final e revisão de procedência antes de uma submissão pública.

Os oito quadros principais mostram **CAPTURA REAL PENDENTE** enquanto não houver
sessão de homologação validada. Eles são modelos editoriais, não capturas prontas.
Nenhum modelo ou comprovante falso foi colocado em `media/final` ou enviado à Apple.

## Estratégia de conversão e ASO

As três primeiras imagens explicam utilidade: ação rápida, agenda e contexto do
paciente. Receitas/exames, assistente, equipe e relatórios desenvolvem a proposta;
o iPad demonstra adaptação quando sua captura própria estiver disponível.
Login é complementar e não deve ocupar a primeira posição da página pública.

Um benefício e uma tela por quadro. Títulos curtos em português, contraste forte,
área de texto consistente e interface predominante. A própria UI é a prova do
benefício; texto promocional sozinho não comprova uma funcionalidade.

Termos relevantes aparecem em contexto, sem repetição artificial: agenda,
prontuário, receitas, exames e gestão clínica. Imagens ajudam a compreensão e a
conversão; não se deve afirmar que o texto embutido em imagem melhora diretamente
a indexação de palavras-chave da loja.

Depois da publicação e com volume suficiente, comparar o primeiro quadro atual
com uma variante `Sua rotina clínica. Mais perto de você.` usando Product Page
Optimization. Medir conversão por origem e período comparáveis; não declarar
uma variante vencedora antes dos resultados. Nenhum experimento foi criado.

## Limites das alegações

Não prometer automação ilimitada, leitura integral de todas as bulas, ausência de
interações, resultados clínicos, avaliações fictícias ou aprovação pela Apple.
Transcrição não recebe um quadro promocional enquanto o erro do feedback40 não
for reproduzido e resolvido. A comunidade só entra na seleção pública quando
denúncia, bloqueio e moderação estiverem validados.

O usuário informou 14 dias grátis. Como a oferta é consultada no catálogo durante
o cadastro e pode mudar, este conjunto não fixa preço/oferta no texto externo.
A oferta real pode aparecer na captura de cadastro do build final, depois de
conferida para o plano e a região mostrados.

## Prompt do fundo

Use case: ads-marketing. Premium abstract portrait backdrop for AtendeBem's
Brazilian healthcare App Store campaign, aspect 1320:2868. Calm midnight navy
upper 40 percent with empty space for headlines; restrained emerald/mint glass
ribbons intersecting at lower right, connected-care theme, architectural soft
lighting. No text, logos, people, medical objects, devices, interface, glitter,
neon or watermark. Decorative backdrop only; composite real app UI separately
without altering it. Built-in image generation, not CLI/API fallback.

## Referências oficiais

- [Especificações de imagens](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Diretrizes de revisão, metadados precisos](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)
- [Product Page Optimization](https://developer.apple.com/app-store/product-page-optimization/)
- [Configuração de ações do Xcode Cloud](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)

Xcode Cloud pode executar UI tests e disponibilizar capturas anexadas aos resultados.
Os testes não possuem uma conta clínica configurada nem anexos das oito cenas
autenticadas. Agora há anexos explícitos de entrada, apresentação, cadastro vazio
e privacidade; eles aguardam execução Cloud após a correção da preparação de fontes.
Habilitar Test não equivale a gerar o conjunto completo de capturas.
