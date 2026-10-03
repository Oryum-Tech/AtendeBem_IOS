# Informações clínicas e medicamentos

**Minuta para revisão. Não publicada.** Escopo considerado: cliente iOS atual, em desenvolvimento.

## Uso atual

O aplicativo permite consultar informações disponíveis nos serviços da clínica. Profissionais autorizados podem preparar receitas e solicitar sua assinatura pelo serviço. O cliente não calcula doses, avalia automaticamente interações, vende ou dispensa medicamentos. A escolha do tratamento e o conteúdo da receita são responsabilidade do profissional habilitado. O estado de assinatura é o informado pelo serviço; um rascunho ou documento importado não comprova assinatura válida. Alergias exibidas são registros fornecidos pelo serviço, sem confirmação clínica independente pelo aplicativo.

Confirme a identidade do paciente, a clínica e a data da informação. Registro ausente ou incompleto de alergias não deve ser interpretado como ausência de alergias. Decisões sobre medicamentos pertencem a profissionais habilitados e exigem avaliação do paciente e das fontes clínicas apropriadas.

O aplicativo não é um serviço de emergência. Em uma emergência no Brasil, procure o serviço de emergência ou ligue 192.

O campo de medicamento consulta o catálogo disponibilizado pelo serviço e exibe nome, princípio ativo, empresa e situação quando retornados. A seleção é manual; não recomenda substituição, não preenche doses e não comprova adequação ao paciente. A busca de CID também exige escolha e revisão do profissional. A conversa geral com a LARI apresenta fontes e aviso retornados pelo serviço, sem anexar prontuário por padrão.

## Condições de validação antes da distribuição

Os fluxos implementados ainda exigem homologação e os critérios seguintes. Nenhuma aprovação regulatória é presumida:

- Prescrição: registrar profissional, paciente, data, medicamento, apresentação, via e instruções; exigir revisão e confirmação antes de emitir. Validar assinatura e exigências aplicáveis ao tipo de receita, inclusive controle especial, antes de habilitar seu envio.
- Informação sobre medicamentos: apresentar origem e atualização de conteúdos, diferenciar informação de recomendação e preservar alertas de contexto. Não substituir os limites da fonte por uma promessa de segurança absoluta.
- Cálculo de doses: não habilitar até definir elegibilidade perante a Apple, enquadramento sanitário, validação e fontes. Um aviso de responsabilidade não corrige um cálculo não validado.
- IA clínica: não transmitir dados ou propor condutas sem análise específica de finalidade, proteção de dados, validação e revisão profissional. O cliente já oferece sugestões da LARI: confirmar provedores, destinatários, consentimento aplicável e revisão antes da distribuição.
- Venda e dispensação: avaliar requisitos próprios de operação e distribuição antes de qualquer inclusão. O aplicativo atual não tem carrinho, transação ou encaminhamento de compra de medicamentos.

## Enquadramento

O enquadramento como software médico depende da finalidade pretendida e das funcionalidades efetivamente oferecidas, incluindo publicidade. As orientações da Anvisa distinguem funções de registro e comunicação de funcionalidades com finalidade médica adicional. Essa distinção orienta a avaliação, mas não declara automaticamente o produto inteiro dispensado de regularização.

Não usar selos “aprovado pela Anvisa”, “aprovado pelo FDA”, “certificado pela Apple”, “receita válida em qualquer situação” ou “100% seguro” sem o fundamento específico correspondente. Ampliar o escopo exige reavaliar o produto e atualizar a página da loja.

Fontes: [Anvisa — perguntas e respostas sobre SaMD](https://www.gov.br/anvisa/pt-br/centraisdeconteudo/publicacoes/produtos-para-a-saude/manuais/software-como-dispositivo-medico-perguntas-e-respostas), [Apple — App Review Guidelines, 1.4](https://developer.apple.com/app-store/review/guidelines/), [Ministério da Saúde — SAMU 192](https://www.gov.br/saude/pt-br/composicao/saes/samu-192).

## Pedidos de receita na LARI

O comando pode iniciar um rascunho a partir de informações explícitas. O profissional confirma a identidade do paciente e o item do catálogo, completa posologia, quantidade e tipo e revisa os dados antes de assinar. Concentração, período de uso e uso contínuo não determinam automaticamente dose, frequência, via ou quantidade. A LARI não faz cálculo ou escolha automática da terapêutica. A assinatura já solicita o envio pelo serviço; o aplicativo informa esse efeito antes da confirmação e não afirma entrega ao destinatário sem evidência.
