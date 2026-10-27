# Variáveis e segredos das esteiras

O que precisa estar dentro de cada secret do repositório, e por quê. O **mecanismo** — como uma linha vira `TF_VAR_` — está documentado no [`reusable-workflows`](https://github.com/fiap-tech-challenge-devops/reusable-workflows/tree/main/docs/terraform-plan); aqui está o **conteúdo**.

## Os secrets

| Secret | Formato | Consumido por |
|---|---|---|
| `AWS_OIDC_ROLE_ARN_VITAO` | ARN da role | todas as esteiras |
| `TF_VARS_INFRA` | `nome=valor`, uma por linha | stages `infra`, `datadog` e `pagerduty` |
| `TF_VARS_ADDONS` | idem | stage `addons` |
| `SLACK_WEBHOOK_URL` | URL do incoming webhook | workflow de self-healing |

**Um secret serve três stages** porque o Terraform **ignora em silêncio** um `TF_VAR_<nome>` de variável que o stage não declara. Mandar o conjunto inteiro para todos é seguro, e evita três secrets divergindo.

A contrapartida: uma variável **faltando** reprova o plano daquele stage com `Error: No value for required variable` — e, em stage com `required: false`, o job fica verde e o aviso sai como ⚠️ no comentário do PR. Vale ler o comentário, não só o ícone do check.

## `TF_VARS_INFRA`

| Variável | Obrigatória | Para quê |
|---|---|---|
| `datadog_api_key` | **sim** | `infra` grava no Secrets Manager; `datadog` e `pagerduty` autenticam o provider |
| `datadog_app_key` | **sim** | provider do Datadog nos stages `datadog` e `pagerduty` |
| `github_dispatch_token` | **sim** | PAT que o webhook do Datadog usa para o `repository_dispatch` |
| `pagerduty_token` | **sim** | provider do PagerDuty, e o `api_token` da integração no Datadog |
| `pagerduty_subdomain` | **sim** | a parte antes de `.pagerduty.com` |
| `pagerduty_user_email` | **sim** | o plantonista; precisa **já existir** na conta PagerDuty |
| `pagerduty_habilitado` | não | `true` acrescenta o handle aos oito monitores. Padrão `false` |
| `slack_workspace` | não | nome da conta Slack **como o Datadog a registrou** no OAuth. Vazio tira o handle dos monitores |
| `slack_channel` | não | padrão `#alertas-prod`. Precisa **já estar registrado** no painel do Datadog |
| `datadog_site` | não | padrão `datadoghq.com` |

O `slack_workspace` vazio é o estado desligado: sem ele o handle `@slack-` não entra na mensagem. Não repita o handle em `notification_targets`, ou o monitor notifica o canal duas vezes.

As duas descrevem um canal que **o Terraform não cria** — ele só monta o handle. Registrar o canal é passo de painel, e as duas variáveis precisam bater com o que está lá. Errar o nome não reprova o apply: o Datadog aceita handle inexistente e o alerta deixa de chegar em silêncio.

Obrigatória significa: **sem ela o plano daquele stage reprova**. As três do PagerDuty só afetam o stage `pagerduty`; as do Datadog afetam três stages.

## `TF_VARS_ADDONS`

Nenhuma variável é obrigatória — o stage aplica com os padrões. Duas valem a pena quando existirem:

| Variável | Para quê |
|---|---|
| `argocd_admin_password_bcrypt` | hash bcrypt do admin do Argo CD. Vazio, o chart gera uma senha e a deixa em `argocd-initial-admin-secret`. **Nunca a senha em texto** |
| `gitops_repo_password` | credencial do repositório GitOps, se ele deixar de ser público |

## Como atualizar

Pela UI do GitHub, ou:

```bash
gh secret set TF_VARS_INFRA --repo fiap-tech-challenge-devops/togglemaster-iac
```

O comando lê do stdin e **não ecoa o valor**. Ele substitui o secret inteiro, então cole o conjunto completo, não só a linha nova.

Depois de atualizar, rode a esteira do stage afetado. Mudar `datadog_api_key` tem passos extras no cluster — ver [troca de conta Datadog](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/observabilidade/README.md#trocar-de-conta-datadog).

## O que não vive aqui

Credenciais da AWS. Nenhuma esteira tem chave estática: a autenticação é por OIDC, e o único segredo é o ARN da role — que não é segredo de verdade, só não vale expor. Ver [0015](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0015-oidc-sem-chave-estatica.md).

## Pré-requisitos que não são secret

Coisas que precisam existir **antes** e que nenhuma esteira cria:

| O quê | Onde |
|---|---|
| Provedor OIDC do GitHub e a role `github-actions-iac` | IAM, à mão — ver `README.md` |
| Conta Datadog, com API key e Application key | painel do Datadog |
| Conta PagerDuty, com o usuário do plantão | painel do PagerDuty |
| App do Slack com incoming webhook | `api.slack.com/apps` |
| App do Datadog autorizado no workspace, e o canal registrado | painel do Datadog, `Integrations → Slack` |
| PAT com `Contents: read and write` | GitHub, fine-grained |

Os quatro últimos são OAuth ou cadastro, e não se automatizam. É a mesma lista de [0021](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0021-api-key-do-datadog-por-tf-vars.md), [0028](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0028-slack-para-chatops.md) e [0030](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0030-self-healing-em-github-action.md), reunida num lugar só.
