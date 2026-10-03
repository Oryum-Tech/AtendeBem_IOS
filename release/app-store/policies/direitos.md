# Direitos de privacidade e encerramento de conta

**Minuta para revisão. Não publicada.** O início nativo da exclusão está implementado no incremento 1.3.0 (40). A operação do responsável por privacidade/DPO e o QA do fluxo completo ainda precisam de validação.

## Iniciar pelo aplicativo

Abra **Mais → Configurações → Minha conta → Excluir minha conta** e confira as informações e os efeitos apresentados antes de continuar. Esse caminho inicia a solicitação; não comprova, por si só, recebimento pelo responsável, conta apagada ou emissão de protocolo por API.

O acompanhamento e a comunicação do resultado dependem do procedimento operacional do responsável por privacidade, ainda por validar. Nenhum prazo ou conclusão deve ser anunciado sem confirmação real.

## Pedir orientação

O canal público é privacidade@atendebem.io. Informe o tipo de solicitação e um meio para retorno. Não envie senha, código de autenticação ou cópia de prontuário no primeiro contato. Pode ser necessário confirmar sua identidade de maneira proporcional à solicitação.

Dados de atendimento são administrados pela clínica ou pelo profissional responsável. Podemos orientar o encaminhamento ao responsável adequado. A resposta deve explicar as ações, as condições legais e os prazos efetivamente aplicáveis.

## Entender o alcance

- Sair da conta remove a sessão local. Não exclui a conta.
- Desinstalar o app não comunica um pedido de exclusão ao serviço.
- Encerrar a conta de um profissional não autoriza apagar automaticamente os prontuários dos pacientes de uma clínica.
- Registros cuja conservação seja necessária por obrigação aplicável podem permanecer com acesso restrito pelo período cabível. As categorias e a justificativa devem ser informadas ao solicitante.
- Cancelamento de assinatura, revogação de vínculo com uma clínica e exercício de direitos de dados têm efeitos diferentes e precisam ser tratados separadamente.

## Requisito para a versão final

O aplicativo inclui cadastro nativo e início de exclusão. Antes da revisão pública, validar o fluxo completo conforme as regras aplicáveis da Apple. Não substituir exclusão por simples desativação. Não presumir que o setor de saúde dá uma exceção automática para exigir apenas contato por e-mail.

Antes de publicar, registrar a análise e as evidências do fluxo final: autenticação, descrição de efeitos, confirmação, encaminhamento, andamento e conclusão. O início nativo implementado não encerra essas verificações. Operações devem se restringir à conta e ao controlador correto; nunca reutilizar uma rota de exclusão de paciente como se fosse exclusão do usuário.

O procedimento operacional precisa definir responsáveis, verificação de identidade, categorias e prazos de guarda, fornecedores envolvidos, comunicação de resultado e evidência de atendimento. Esta minuta não afirma que esse processo já existe ou foi aprovado.

Referência: [Apple — Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
