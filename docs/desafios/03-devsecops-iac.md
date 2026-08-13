# Fase 3 — Análise de segurança na esteira de IaC

Notas de decisão sobre o estágio de segurança do `iac-plan`: o que cada ferramenta acusou, o que foi corrigido, o que foi ignorado e por quê.

O objetivo do registro é que uma exceção nunca seja uma escolha silenciosa. Um `skip-check` sem justificativa escrita é indistinguível de alguém desligando o gate para o build passar.

## As duas ferramentas

| Ferramenta | O que faz | Configuração |
|---|---|---|
| **Trivy** (`trivy config`) | Misconfiguration em HCL | [`trivy.yaml`](../../trivy.yaml), exceções em [`.trivyignore`](../../.trivyignore) |
| **Checkov** | Misconfiguration em HCL, com outro conjunto de regras | [`.checkov.yaml`](../../.checkov.yaml) |

Não é redundância. São dois motores independentes, com cobertura diferente — na primeira execução limpa, o Trivy acusou 0 e o Checkov acusou 34.

### Sobre o tfsec

O board da fase 2 previa `tfsec` + `checkov`. O tfsec foi **descontinuado e incorporado ao Trivy**: a descrição do repositório hoje é literalmente *"Tfsec is now part of Trivy"*, e a última release é de maio/2025 contra releases semanais do Trivy.

O motor de regras do tfsec (`defsec`) virou a base do `trivy config`. Não houve troca de ferramenta — as regras são as mesmas, na versão que ainda recebe manutenção. O ganho adicional é que o Trivy também cobre SCA (`trivy fs`) e imagem (`trivy image`), que as esteiras dos microsserviços vão usar: uma ferramenta, um formato de saída, uma convenção de exceção em toda a plataforma.

---

## Trivy

### O problema: o scan avaliava código de terceiros

Primeira execução: **8 achados**, sendo **7 dentro da biblioteca `terraform-aws-modules`**, não neste repositório.

O Trivy resolve os `source` remotos, **baixa os módulos** e avalia o código deles junto. Os achados eram:

| Regra | Severidade | Módulo |
|---|---|---|
| `AWS-0040` — endpoint público do EKS | CRITICAL | `eks` |
| `AWS-0041` — cluster acessível de `0.0.0.0/0` | CRITICAL | `eks` |
| `AWS-0104` — egress irrestrito (×2) | CRITICAL | `rds`, `elasticache` |
| `AWS-0164` — subnet atribui IP público (×2) | HIGH | `vpc` |
| `AWS-0051` — Redis sem transit encryption | HIGH | `elasticache` |
| `AWS-0132` — bucket de state sem chave própria | HIGH | **este repositório** |

Achado em módulo de terceiro **não é acionável aqui**: a correção seria alterar o outro repositório, publicar uma tag nova e atualizar a referência. A biblioteca tem a própria esteira para isso.

### A correção

`exclude-downloaded-modules: true` no [`trivy.yaml`](../../trivy.yaml).

A opção **não é exposta como input** pela `aquasecurity/trivy-action`, o que obrigou a usar arquivo de configuração (`trivy-config: trivy.yaml`). O nome da chave saiu do código-fonte do Trivy (`pkg/flag/misconf_flags.go`): `misconfiguration.terraform.exclude-downloaded-modules`.

Verificação local, contra o repositório real:

```
com trivy.yaml           -> 0 achados, exit 0
--tf-exclude=false       -> 5 regras distintas, HIGH+CRITICAL
```

### O achado que procedia

`AWS-0132` — o bucket de state usava `AES256` (chave gerenciada pela AWS). Foi **corrigido**, não ignorado: agora usa KMS key própria com rotação, e `bucket_key_enabled = true` para não gerar uma chamada ao KMS por objeto.

O argumento da regra tem mérito no caso específico: o state contém as senhas dos três RDS em texto claro. Com chave própria, todo acesso ao conteúdo aparece no CloudTrail e pode ser restrito pela key policy.

### Por que os outros não viraram exceção

Depois do `exclude-downloaded-modules`, os 7 achados de módulo saíram do escopo do scan — o [`.trivyignore`](../../.trivyignore) ficou **sem entradas ativas**, só com a política registrada.

Vale anotar a leitura de cada um, porque eles continuam sendo verdade sobre a infraestrutura, mesmo fora do relatório:

- **`AWS-0164`** é a mais fora de contexto. Subnet pública *precisa* atribuir IP público — é o que a torna pública. Sem isso, NAT Gateway e ALB não funcionam. A regra não distingue subnet pública de privada.
- **`AWS-0104`** é regra de *saída*, em banco dentro de subnet privada sem rota para a internet exceto pelo NAT. Restringir egress de RDS quebra funcionalidades legítimas.
- **`AWS-0040`/`0041`** é necessidade operacional: sem endpoint público, o runner do GitHub Actions não alcança a API do cluster e o stage `addons` não instala nada. A solução correta seria runner self-hosted na VPC — fora de escopo.
- **`AWS-0051`** é dívida real e conhecida: o `evaluation-service` conecta em `redis://`, sem TLS. Ligar exige mudar a aplicação.

---

## Checkov

Foram duas rodadas — a segunda porque a correção da primeira gerou achados novos.

| Rodada | Passaram | Falharam | Regras distintas |
|---|---|---|---|
| 1ª | 99 | 34 | 9 |
| 2ª | 115 | 4 | 4 |
| 3ª (esperada) | — | 0 | — |

Os 34 iniciais concentravam-se em poucas regras muito repetidas: `CKV_TF_1` sozinha respondia por 17.

### O que foi corrigido

**`CKV_AWS_149` — Secrets Manager sem KMS CMK** (2 achados)

`togglemaster/app/auth` guarda a `MASTER_KEY` do auth-service; `togglemaster/app/evaluation`, a `SERVICE_API_KEY`. São segredos de verdade, e estavam com a chave padrão do serviço.

Correção: uma KMS key dedicada em [`infra/secrets.tf`](../../infra/secrets.tf), aplicada aos **cinco** segredos — os dois de aplicação e os três do RDS.

> **Uma armadilha da análise estática.** Os três secrets do RDS *passaram* no check desde o início, e não deveriam. O módulo `secrets-manager` escreve `kms_key_id = local.kms_key_arn` no recurso, e o Checkov só verifica se o atributo **existe** — não se o valor é nulo. Com `create_kms_key = false` (o default), esse valor era `null` e a chave real era a gerenciada pela AWS, exatamente igual aos dois que falharam.
>
> A diferença entre "passou" e "falhou" era a presença literal do atributo no HCL, não a postura de segurança. Vale como lembrete de que um relatório verde de análise estática não é prova de configuração correta.

**Consequência que quase passou batido:** o External Secrets Operator lê esses segredos. Permissão em `secretsmanager` não basta — sem `kms:Decrypt` na chave nova, o `GetSecretValue` devolve `AccessDenied` citando o KMS. O sintoma apareceria como `ExternalSecret` preso em `SecretSyncedError`, sem menção óbvia à causa. A policy da IRSA em [`infra/irsa.tf`](../../infra/irsa.tf) foi atualizada junto.

**`CKV2_AWS_61` — bucket sem lifecycle configuration** (1 achado)

O bucket tem versionamento ligado, e há uma escrita de state por plan e por apply. Sem expiração, o histórico cresce para sempre.

Correção em [`bootstrap/main.tf`](../../bootstrap/main.tf): expira versões não-correntes após **90 dias** e aborta uploads multipart incompletos após 7. Os 90 dias são folgados de propósito — a versão anterior do state é a rede de segurança para recuperar um apply interrompido, e não se descobre que precisa dela no mesmo dia.

**`CKV2_AWS_64` — KMS key sem policy definida** (2 achados, em duas rodadas)

Sem policy explícita, o KMS aplica a padrão, que delega toda a decisão ao IAM da conta. Declarar a policy torna o controle visível e versionado.

A primeira declaração da policy **é obrigatória**: sem delegar ao root da conta, a chave fica órfã — nem o administrador consegue alterá-la depois, e a única saída é abrir chamado na AWS.

Duas chaves precisaram disso:

- `aws_kms_key.tfstate` ([`bootstrap/main.tf`](../../bootstrap/main.tf)) — administração pelo root + uso pelo S3, restrito por `kms:ViaService`.
- `aws_kms_key.app_secrets` ([`infra/secrets.tf`](../../infra/secrets.tf)) — administração pelo root + uso pelo Secrets Manager + **leitura direta pela role IRSA do External Secrets**.

A terceira declaração da segunda chave merece nota: o ESO decifra o segredo **direto**, não através do Secrets Manager, então a condição `kms:ViaService` não o cobre. Sem ela, o `ExternalSecret` fica preso em `SecretSyncedError` com `AccessDenied` citando o KMS.

> A chave `app_secrets` só apareceu na segunda rodada porque **ela mesma foi criada para corrigir o `CKV_AWS_149`** — e nasceu sem policy, exatamente o defeito que eu tinha acabado de corrigir na outra. Duas chaves, tratamento inconsistente. É o tipo de erro que a segunda execução do scan pega e a revisão humana deixa passar.

### A correção que gerou achados novos

Adicionar a key policy fez **três regras genéricas de IAM** dispararem sobre o documento:

| Regra | Leitura do Checkov |
|---|---|
| `CKV_AWS_111` | write access sem constraint |
| `CKV_AWS_356` | policy com `Resource: "*"` |
| `CKV_AWS_109` | permissions management sem constraint |

A leitura literal está certa: é `kms:*` sobre `*`. Mas num documento de **key policy** o `"*"` significa *esta chave* — não existe outro recurso no escopo do documento. E a declaração de administração pelo root é a que a própria AWS exige.

**A exceção foi feita inline, não no `.checkov.yaml`.** As três são regras genéricas de IAM: ignorá-las globalmente cegaria o scan para as policies de verdade deste repositório — [`infra/ci-role.tf`](../../infra/ci-role.tf) e [`infra/irsa.tf`](../../infra/irsa.tf), onde `Resource: "*"` seria um problema real.

```hcl
data "aws_iam_policy_document" "app_secrets_key" {
  #checkov:skip=CKV_AWS_111:Key policy — o "*" é a própria chave, e a delegação ao root é exigida pela AWS
  ...
}
```

O escopo do skip inline é o bloco, e só ele.

### O que foi ignorado, e por quê

Registrado com a justificativa completa em [`.checkov.yaml`](../../.checkov.yaml). Resumo:

| Regra | Achados | Motivo |
|---|---|---|
| `CKV_TF_1` — módulo sem commit hash | **17** | Regra pensada para módulo de terceiro não confiável. A biblioteca é da própria organização e as tags são imutáveis por convenção. Trocar por hash tornaria os 11 `source` ilegíveis e faria "subir de versão" deixar de ser rastreável no diff. |
| `CKV2_AWS_34` — SSM Parameter deve ser SecureString | **8** | O conteúdo é nome de cluster, ID de VPC, ARN de OIDC provider, URL de registry. Nada é segredo — o ARN da role IRSA fica visível numa annotation de ServiceAccount. `SecureString` obrigaria `kms:Decrypt` em toda leitura, acoplando mais sem proteger nada. |
| `CKV2_AWS_57` — rotação automática de segredo | 2 | Exige Lambda que troque a credencial na aplicação e no banco de forma coordenada. É trabalho, não configuração. |
| `CKV_AWS_18` — access logging no bucket | 1 | Exige um segundo bucket, que dispara as mesmas regras deste. O acesso ao state já é auditável pelo CloudTrail via a KMS key dedicada. |
| `CKV2_AWS_62` — event notifications | 1 | Não há consumidor: ninguém reage a uma escrita de tfstate. |
| `CKV_AWS_144` — replicação cross-region | 1 | O ambiente todo vive em `us-east-1`. Se a região cair, o state replicado não reconstrói nada. |

---

## Resumo do plano por IA

A saída do `terraform plan` é fiel e ilegível: centenas de linhas para descrever meia dúzia de decisões. O objetivo aqui foi **acrescentar** uma leitura em português por cima, sem tirar nada — o plano íntegro continua no mesmo `<details>` de antes.

Duas restrições definiram o desenho.

### É informativo, jamais um gate

O step tem `continue-on-error: true` e todos os seus caminhos de erro saem com `exit 0`: secret ausente, chave inválida, cota esgotada, API indisponível, resposta sem texto, plano sem mudanças. Uma indisponibilidade da API não pode reprovar um PR de infraestrutura — quem decide o merge é o `plan`, e o resumo é conveniência.

Testar esses caminhos rendeu um defeito real: `[ -s arquivo ]` testa tamanho não-zero, e `jq -r` sobre um resultado vazio grava uma quebra de linha. Um byte. A verificação passava, e uma resposta sem texto teria renderizado um bloco de resumo em branco com o rodapé embaixo. A correção testa conteúdo (`grep -q '[^[:space:]]'`) e apaga o arquivo, que é o que faz os dois steps seguintes o ignorarem.

### `terraform show -json` não redige valores sensíveis

Esta foi a descoberta que moldou o resto. Testado empiricamente com o provider `random`:

```
terraform show tfplan        → 3 ocorrências de "(sensitive value)"
terraform show -json tfplan  → "senha":{"sensitive":true,"value":"615cZvPKR6Iy19FnAXEc"}
```

O valor em texto claro fica **ao lado** do próprio `"sensitive": true`. Só a saída humana redige.

O detalhe temporal agrava: antes do primeiro apply, uma senha gerada é `(known after apply)` e nem aparece no plano. Depois do apply ela passa a viver no state — e aparece em **todo** plano seguinte. Ou seja, o dia em que o `infra` for aplicado é o dia em que os planos passam a carregar as três senhas do RDS.

Por isso o que é enviado à API não é o plano, e sim uma redução a **estrutura pura**: endereço, tipo, ação e os *nomes* dos atributos que mudam. Nenhum valor atravessa a fronteira da máquina. A redução é um filtro `jq` no próprio step, validado contra um fixture com senhas plantadas — os valores existem no plano bruto e nenhum sobrevive.

Isto também confirmou, em retrospecto, duas decisões anteriores: não subir o `tfplan` como artifact, e cifrar o bucket de state com chave gerenciada pelo cliente.

### Credencial de serviço, não de pessoa física

Provedores de LLM oferecem dois caminhos: um token derivado da assinatura pessoal, que sai de graça, e uma chave de API cobrada em crédito pré-pago.

O primeiro é uma **credencial de pessoa física** — presa a um indivíduo, fora do controle da organização, consumindo limites pessoais, e que quebra no dia em que a pessoa sai. Numa esteira, credencial é de serviço: emitida pela organização, com escopo, teto de gasto e rotação. É a mesma lógica que já vale para a AWS aqui, e foi o que decidiu a escolha.

O passo seguinte natural seria federação por OIDC, eliminando o secret estático como já foi feito com a AWS. Ficou registrado como melhoria, não implementado.

### Fornecedor: OpenAI

O resumo usa a **Responses API** (`/v1/responses`) da OpenAI, com `gpt-5.6-terra`. O modelo é uma variável no `env` do workflow — trocar é uma linha.

Vale registrar por que não foi `/v1/chat/completions`: era o endpoint que eu conhecia de cor, e a documentação atual recomenda o Responses para geração de texto. Conferir antes de escrever evitou um endpoint legado na entrega.

Um detalhe da leitura da resposta: o array `output` pode trazer itens de raciocínio **antes** da mensagem. `output[0].content[0].text` pega o item errado quando isso acontece; o filtro por `type` não.

A troca de fornecedor custou pouco justamente porque a redução do plano, os gates e a apresentação não dependem de quem responde — só o corpo do request e o `jq` que lê a resposta mudaram.

### A extração para CI compartilhado

A esteira de plano inteira saiu deste repositório e foi para [`reusable-workflows`](https://github.com/fiap-tech-challenge-devops/reusable-workflows). O `iac-plan.yml` daqui virou um caller de ~50 linhas: gatilho, concorrência e os parâmetros do projeto.

A parte interessante foi descobrir que **a peça de IA não podia ser um reusable workflow**, e o motivo não é estilo.

Um `workflow_call` roda como job próprio, em runner próprio. O resumo lê o plano binário que o step anterior gravou e escreve um arquivo que os steps seguintes consomem — nada disso atravessa a fronteira entre runners. Passar o plano exigiria `upload-artifact`, e é exatamente o que o desenho recusa desde o início: `terraform show -json` não redige, e artifact é baixável por qualquer pessoa com leitura no repositório.

Ou seja, uma restrição de segurança decidiu a forma da abstração. O resumo virou **composite action** (roda no mesmo runner) e o reusable workflow entrou por fora, definindo o job onde o action é chamado.

A fronteira do action também foi decidida por segurança: a redução do plano e a chamada à API ficaram **juntas**. O valor da peça não é a chamada — são dez linhas de `curl`. É a garantia de que nenhum valor sai da máquina. Separar num "resuma este texto" genérico permitiria a um consumidor passar o plano bruto e vazar tudo.

Dois efeitos colaterais bons: o script saiu do YAML e virou arquivo próprio (`summarize.sh`), o que o torna verificável por `bash -n` e executável em teste; e os intermediários passaram a ser escritos no `RUNNER_TEMP`, então nenhum consumidor precisa acrescentar nada ao `.gitignore` por causa do action.

### Nome de check muda ao adotar reusable workflow

Custou uma verificação antes de mergear, e teria custado um merge travado se passasse batido.

Um workflow chamado reporta o status check como `<job do caller> / <job do chamado>`. Os cinco checks obrigatórios do ruleset — `Validate (infra)`, `Validate (addons)`, `Security`, `Plan (infra)`, `Plan (addons)` — passam a se chamar `iac / Validate (infra)` e assim por diante.

O ruleset continua exigindo os nomes antigos, que ninguém mais reporta. O sintoma seria idêntico ao do `Plan (addons)` que travou em `IN_PROGRESS` naquela semana: PR verde, merge bloqueado esperando um check que não existe. Só que permanente, e em todos os PRs.

O ruleset precisa ser atualizado **junto** com o merge desta mudança.

### Só no `infra`

O `addons` lê do SSM parâmetros que só existem depois do apply do `infra`; enquanto o ambiente não subir, o plan dele falha. Resumir uma falha não ajuda ninguém.

---

## Dificuldades encontradas

Espaço para anotações do processo — o que travou, quanto custou e como foi contornado.

### Trivy avaliando a biblioteca inteira

Custou uma execução inteira até ficar claro que os achados não eram deste repositório. O sintoma enganava: os caminhos no relatório começam com `github.com/...`, mas isso se perde no meio da tabela.

### Versão de action inexistente

`aquasecurity/trivy-action@0.28.0` não existe — as tags do projeto usam prefixo `v`, e a atual é `v0.36.0`. A falha acontece no **"Set up job"**, antes de qualquer step, então o log não mostra nada além de `unable to find version`.

### Claim `sub` do OIDC com IDs de organização e repositório

A trust policy da role parecia correta e ainda assim devolvia `Not authorized to perform sts:AssumeRoleWithWebIdentity`. A organização usa a claim `sub` customizada do GitHub, que injeta IDs imutáveis:

```
repo:fiap-tech-challenge-devops@283760261/togglemaster-iac@1314140933:ref:refs/heads/main
```

O padrão clássico `repo:<org>/<repo>:*` não casa: o sufixo `@<id>` aparece **antes** da barra, onde o curinga final não alcança. Solução: `repo:<org>*/<repo>*`.

Para diagnosticar, a claim que de fato chegou está no CloudTrail:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 1 --query 'Events[0].CloudTrailEvent' --output text
```

O campo `userIdentity.principalId` traz a `sub` exata.

### `source` de módulo não aceita interpolação

Uma variável `module_ref` para centralizar a tag da biblioteca parecia natural, mas o Terraform recusa: *"Variables not allowed"*. O `init` resolve os módulos antes de avaliar qualquer expressão, então o `source` precisa ser literal. Subir de versão é find/replace.

### Instabilidade do GitHub Actions

Duas execuções seguidas falharam no "Set up job" com `Service Unavailable`, `Internal Server Error` e `Bad Gateway` ao resolver ações **aninhadas** (`actions/cache`, `aquasecurity/setup-trivy`), referenciadas por SHA dentro do `trivy-action`.

As ações declaradas no workflow baixaram normalmente — só a resolução de segundo nível falhou. Não há correção possível do lado do repositório; foi esperar e reexecutar.

### O `concurrency` compartilhado criou um impasse

`apply`, `bootstrap` e `destroy` dividiam o grupo `iac-${{ github.ref }}`. Um `apply` disparado por push ficava parado no gate de aprovação do environment e **segurava o grupo**, deixando o `bootstrap` na fila indefinidamente.

O `bootstrap` tem state independente e não disputa recurso com os outros — passou a ter grupo próprio.

**Voltou a acontecer, e a segunda vez expôs a causa de verdade.** Com o `bootstrap` já isolado, um merge disparou um `apply` que ficou esperando aprovação, e o merge seguinte enfileirou atrás dele. Grupo próprio resolvia a colisão entre workflows diferentes, não entre dois runs do mesmo workflow.

O problema não era o `concurrency` — era o gate. O environment `production` no job de `infra` pedia uma aprovação que **já tinha sido dada no pull request**: o ruleset da main exige o `plan` verde, e quem aprova o PR está decidindo aplicar, com o plano na frente para ler. A segunda aprovação não acrescentava informação e ainda travava a fila.

O gate saiu do `apply`. Continua no `destroy`, e ali por um motivo que não se aplica ao `apply`: o `destroy` roda por `workflow_dispatch`, sem PR, sem revisão e sem plano — o environment é a única confirmação humana que existe naquele caminho.

### Corrigir um achado gerou três novos

A key policy adicionada para resolver o `CKV2_AWS_64` disparou `CKV_AWS_111`, `CKV_AWS_356` e `CKV_AWS_109` — regras genéricas de IAM que leem `kms:*` sobre `*` como policy irrestrita, sem distinguir key policy de policy de identidade.

Vale como lembrete de que o número de achados não cai monotonicamente: cada correção é código novo, sujeito ao mesmo scan. Convergir levou três execuções.

### `terraform validate` não detecta ciclo de dependência

A policy da chave `app_secrets` referencia `module.irsa_eso.role_arn`, e a policy do ESO referencia `aws_kms_key.app_secrets.arn`. Parece circular.

O `validate` passa mesmo se houver ciclo — ele não constrói o grafo de dependências. Só o `plan` acusa, com `Error: Cycle:`. Aqui não havia ciclo real (a policy do ESO usa só o ARN da chave, conhecido na criação), mas a confirmação exigiu rodar um `plan` completo, não um `validate`.

### O bootstrap não convergia

A primeira versão verificava se o bucket já existia e, em caso positivo, pulava o apply. Isso evitava o `BucketAlreadyOwnedByYou` da segunda execução, mas ao custo de o stage nunca aplicar mudança nenhuma — a KMS key adicionada depois jamais entraria.

A causa real não era o apply: era o **state local ser descartado** a cada run. A correção foi o bootstrap migrar o próprio state para o bucket que cria, com três caminhos (`create`, `adopt`, `remote`) decididos por inspeção do que existe na AWS.

### `jq` ausente na máquina local deu leituras falsas

Verificações escritas com `jq ... 2>/dev/null` estavam falhando em silêncio e devolvendo "limpo" — o binário não existe no ambiente, e o `2>/dev/null` engolia o `command not found`. Conclusões tiradas dessas checagens não valiam nada.

Custou refazer as verificações com `grep`, e depois baixar o `jq` para um diretório temporário só para conseguir testar o filtro de redução antes de mandá-lo para a esteira. A lição é sobre o `2>/dev/null`: ele apaga a diferença entre "rodou e não achou" e "não rodou".
