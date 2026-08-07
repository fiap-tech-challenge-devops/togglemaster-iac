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

Primeira execução completa: **99 passaram, 34 falharam** — mas em apenas **9 regras distintas**, muito repetidas.

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

**`CKV2_AWS_64` — KMS key sem policy definida** (1 achado)

Sem policy explícita, o KMS aplica a padrão, que delega toda a decisão ao IAM da conta. Declarar a policy torna o controle visível e versionado.

A primeira declaração da policy **é obrigatória**: sem delegar ao root da conta, a chave fica órfã — nem o administrador consegue alterá-la depois, e a única saída é abrir chamado na AWS.

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

### O bootstrap não convergia

A primeira versão verificava se o bucket já existia e, em caso positivo, pulava o apply. Isso evitava o `BucketAlreadyOwnedByYou` da segunda execução, mas ao custo de o stage nunca aplicar mudança nenhuma — a KMS key adicionada depois jamais entraria.

A causa real não era o apply: era o **state local ser descartado** a cada run. A correção foi o bootstrap migrar o próprio state para o bucket que cria, com três caminhos (`create`, `adopt`, `remote`) decididos por inspeção do que existe na AWS.
