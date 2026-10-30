# Variáveis e segredos das esteiras

O que precisa estar dentro de cada secret do repositório, e por quê. O **mecanismo** — como uma linha vira `TF_VAR_` — está documentado no [`reusable-workflows`](https://github.com/fiap-tech-challenge-devops/reusable-workflows/tree/main/docs/terraform-plan); aqui está o **conteúdo**.

## Os secrets

| Secret | Formato | Consumido por |
|---|---|---|
| `AWS_OIDC_ROLE_ARN_VITAO` | ARN da role | todas as esteiras |
| `TF_VARS_INFRA` | `nome=valor`, uma por linha | stages `infra`, `datadog` e `pagerduty` |
| `TF_VARS_ADDONS` | idem | stage `addons` |
| `SLACK_WEBHOOK_URL` | URL do incoming webhook | workflow de self-healing |
| `PAGERDUTY_TOKEN` | chave REST da API | workflow de self-healing |
| `PAGERDUTY_FROM_EMAIL` | e-mail de um usuário da conta | workflow de self-healing |

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
| `error_rate_threshold` | não | patamar **crítico** de taxa de erro. Padrão `10`. É ele que pagina e autoriza a remediação |
| `error_rate_warning` | não | patamar de **aviso**. Padrão `5`. Só notifica o Slack |

O `slack_workspace` vazio é o estado desligado: sem ele o handle `@slack-` não entra na mensagem. Não repita o handle em `notification_targets`, ou o monitor notifica o canal duas vezes.

As duas descrevem um canal que **o Terraform não cria** — ele só monta o handle. Registrar o canal é passo de painel, e as duas variáveis precisam bater com o que está lá. Errar o nome não reprova o apply: o Datadog aceita handle inexistente e o alerta deixa de chegar em silêncio.

Os dois patamares de erro têm que respeitar `error_rate_warning < error_rate_threshold`, ou o Datadog recusa o monitor. O que separa um do outro é **quem responde**: o aviso vai para gente, o crítico pagina e libera a remediação automática — ver [0034](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0034-escada-de-severidade-e-espera-antes-de-remediar.md).

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

## Os três do self-healing

Os três são **opcionais**, e cada passo se desliga sozinho quando o seu falta. Isso é de propósito: o workflow precisa triar e remediar num repositório recém-clonado, sem integração nenhuma configurada.

| Falta | O que para de acontecer |
|---|---|
| `SLACK_WEBHOOK_URL` | o relatório no canal. A triagem e a remediação seguem |
| `PAGERDUTY_TOKEN` ou `PAGERDUTY_FROM_EMAIL` | a nota e o fechamento do incidente. O resto segue |

O `PAGERDUTY_FROM_EMAIL` existe porque a API do PagerDuty **exige o header `From`** com o e-mail de um usuário real da conta para criar nota e para resolver incidente — sem ele, `400`. É o mesmo endereço do `pagerduty_user_email` em `TF_VARS_INFRA`.

**São o mesmo token em dois lugares.** O `pagerduty_token` do `TF_VARS_INFRA` serve o provider do Terraform; este secret serve o workflow. A duplicação é deliberada: ler o `TF_VARS_INFRA` aqui obrigaria o workflow a interpretar o formato `nome=valor` — e aquele parser [não apara espaço nem `\r`](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0033-pagerduty-em-stage-proprio.md). O preço é lembrar dos dois ao rotacionar.

## Variáveis de repositório, que não são secret

Em `Settings → Secrets and variables → Actions → Variables`. Valor visível, porque não há nada a esconder — o motivo de não ser literal no workflow é poder mudar sem commit.

| Variável | Para quê |
|---|---|
| `SELF_HEALING_ESPERA` | segundos que o self-healing passa **confirmando** a falha antes de remediar. Vazia, o padrão é `90` |

A espera existe porque a remediação reverte um segredo e recicla pods: contra uma oscilação passageira ela é mais destrutiva que a falha, e contra uma rotação feita de propósito ela desfaz o trabalho de alguém. O workflow re-sonda a credencial durante a janela e **desiste** se ela voltar a autenticar.

Para a gravação da demonstração, um valor alto — `600`, por exemplo — dá tempo de mostrar a taxa de erro subindo e abrir um trace antes de a automação agir. **Devolva para `90` depois**, ou o próximo incidente real fica dez minutos sem remediação. Em disparo manual pelo `workflow_dispatch` há o campo `espera`, que sobrepõe sem mexer na variável; `0` desliga a espera.

## O que não vive aqui

Credenciais da AWS. Nenhuma esteira tem chave estática: a autenticação é por OIDC, e o único segredo é o ARN da role — que não é segredo de verdade, só não vale expor. Ver [0015](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0015-oidc-sem-chave-estatica.md).

## Pré-requisitos que não são secret

Coisas que precisam existir **antes** e que nenhuma esteira cria:

| O quê | Onde |
|---|---|
| Provedor OIDC do GitHub e a role `github-actions-iac` | IAM, à mão — ver `README.md` |
| Conta Datadog, com API key e Application key | painel do Datadog |
| Conta PagerDuty, com o usuário do plantão | painel do PagerDuty |
| Chave REST da API do PagerDuty | painel do PagerDuty, `Integrations → API Access Keys` |
| App do Slack com incoming webhook | `api.slack.com/apps` |
| App do Datadog autorizado no workspace, e o canal registrado | painel do Datadog, `Integrations → Slack` |
| PAT com `Contents: read and write` | GitHub, fine-grained |

Os cinco últimos são OAuth, cadastro ou credencial de longa duração, e não se automatizam. É a mesma lista de [0021](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0021-api-key-do-datadog-por-tf-vars.md), [0028](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0028-slack-para-chatops.md), [0030](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0030-self-healing-em-github-action.md) e [0035](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0035-a-action-fecha-o-incidente.md), reunida num lugar só.

A chave da API do PagerDuty **não** sai do Terraform: o `pagerduty_token` existe para o provider, mas uma chave criada por ele seria destruída no destroy noturno junto com o stage, e o workflow de self-healing precisa funcionar com o ambiente fora. Mesmo raciocínio da [0027](https://github.com/fiap-tech-challenge-devops/.github/blob/main/docs/decisoes/0027-ciclo-de-vida-do-stage-datadog.md).
