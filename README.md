# togglemaster-iac

Infraestrutura AWS do **ToggleMaster**, em Terraform. Este repositório provisiona a plataforma; ele não contém código de aplicação nem manifests de Kubernetes.

Faz parte de um conjunto de quatro repositórios:

| Repositório | Papel |
|---|---|
| [`terraform-aws-modules`](https://github.com/fiap-tech-challenge-devops/terraform-aws-modules) | Biblioteca de módulos Terraform reutilizáveis |
| **`togglemaster-iac`** | **Provisiona a infraestrutura deste sistema (este repo)** |
| [`togglemaster-gitops`](https://github.com/fiap-tech-challenge-devops/togglemaster-gitops) | Manifests Helm consumidos pelo Argo CD |
| [`reusable-workflows`](https://github.com/fiap-tech-challenge-devops/reusable-workflows) | Workflows de CI/CD chamados pelos microsserviços |

## O que é provisionado

- **Rede** — VPC, subnets públicas e privadas, Internet Gateway, NAT, route tables
- **Cluster** — EKS com managed node groups e add-ons gerenciados
- **Bancos** — 3 instâncias RDS PostgreSQL, 1 cluster ElastiCache Redis, 1 tabela DynamoDB (`ToggleMasterAnalytics`)
- **Mensageria** — fila SQS de eventos de avaliação
- **Registry** — 5 repositórios ECR, um por microsserviço
- **Segredos** — Secrets Manager, consumido no cluster pelo External Secrets Operator
- **Identidades** — roles IRSA dos microsserviços, do Karpenter e do AWS Load Balancer Controller

## Consumo da biblioteca de módulos

Os recursos vêm de [`terraform-aws-modules`](https://github.com/fiap-tech-challenge-devops/terraform-aws-modules), sempre **fixados em uma tag**:

```hcl
module "vpc" {
  source = "github.com/fiap-tech-challenge-devops/terraform-aws-modules//vpc?ref=v0.1.0"
  # ...
}
```

Fixar em tag e não em `main` é deliberado: a biblioteca é compartilhada, e um commit nela não pode alterar o plano deste repositório sem uma mudança explícita aqui.

## Estrutura

```
bootstrap/    # state remoto, repositórios ECR e a role de CI
infra/        # rede, cluster, bancos, mensageria, identidades
addons/       # componentes que rodam dentro do cluster, incluindo o Argo CD
```

## Pré-requisitos manuais

Duas coisas precisam existir **antes** de qualquer esteira rodar, e não são criadas por este repositório:

| Recurso | Por quê é manual |
|---|---|
| OIDC provider do GitHub na conta AWS | É por conta, não por projeto. Vários repositórios federam pelo mesmo provider |
| IAM role assumida pelas esteiras | Circular: a esteira precisaria assumir a role para poder criá-la |

A role precisa de uma trust policy federada ao OIDC do GitHub, restrita a este repositório:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:fiap-tech-challenge-devops*/togglemaster-iac*" }
    }
  }]
}
```

O ARN dela vai no secret `AWS_OIDC_ROLE_ARN_VITAO` do repositório.

> A condição `sub` é o que impede qualquer outro repositório do GitHub de assumir a role. Sem ela, o `aud` sozinho autorizaria o mundo inteiro.

### Por que os curingas depois da org e do repositório

Esta organização usa a claim `sub` customizada do GitHub, que injeta os IDs imutáveis de organização e repositório:

```
repo:fiap-tech-challenge-devops@283760261/togglemaster-iac@1314140933:ref:refs/heads/main
```

O padrão clássico `repo:<org>/<repo>:*` **não casa** com isso: o sufixo `@<id>` aparece antes da barra, onde o curinga final não alcança. O sintoma é `Not authorized to perform sts:AssumeRoleWithWebIdentity`, com a trust policy parecendo correta à primeira vista.

Os IDs não são fixados literalmente porque mudariam se um repositório fosse recriado.

Se precisar diagnosticar de novo, a claim que chegou de fato está no CloudTrail:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 1 --query 'Events[0].CloudTrailEvent' --output text
```

O campo `userIdentity.principalId` traz a `sub` exata que o GitHub enviou.

Em permissões, `AdministratorAccess` resolve para este escopo — o stage `infra` cria VPC, EKS, RDS, IAM e ECR, e o conjunto mínimo para isso já se aproxima de admin.

### Por que três stages

**`bootstrap`** guarda os recursos de ciclo de vida longo: o bucket S3 do state, os cinco repositórios ECR e a role de CI que publica neles.

Ele resolve o ovo-e-galinha do state — o bucket que guarda o `tfstate` não pode guardar o state que o cria. Na primeira execução roda com state local e depois migra o próprio state para o bucket; a partir daí converge como qualquer outro stage.

O ECR vive aqui, e não no `infra`, por três motivos: a esteira de CI dos microsserviços passa a ser testável **sem subir a infraestrutura**, as imagens sobrevivem ao `destroy` do ambiente, e o `destroy` do `infra` deixa de falhar com `RepositoryNotEmptyException` quando há imagem publicada.

**`infra`** usa apenas o provider `aws` e cabe em um único apply. Isso inclui o plano AWS do Karpenter e do Load Balancer Controller (IAM, IRSA, SQS, EventBridge), que vêm dos módulos `eks-karpenter` e `eks-aws-lb-controller` da biblioteca.

**`addons`** é separado porque precisa dos providers `helm`/`kubernetes` apontando para um cluster que só existe depois do `infra`. O Terraform não permite que a configuração de um provider dependa de recursos do mesmo apply, e é por isso que o stage é seu próprio state.

### Quem é dono do quê

O que roda dentro do cluster tem dois donos possíveis, e cada recurso tem exatamente um:

| Dono | Componentes |
|---|---|
| **Terraform** (`addons/`) | metrics-server, AWS Load Balancer Controller, External Secrets + ClusterSecretStore, KEDA, Karpenter (chart + NodePool + EC2NodeClass), Argo CD |
| **Argo CD** (`togglemaster-gitops`) | Os cinco microsserviços |

A linha é o ciclo de vida. Os controllers nascem e morrem com o cluster e mudam a cada trimestre; as aplicações mudam a cada merge. Além disso, os valores que os charts de plataforma precisam (ARNs de roles IRSA, nome da fila do Karpenter) são outputs do `infra` — no Terraform são uma referência, no GitOps exigiriam string fixa escrita à mão ou um plugin de resolução.

O que quebra numa arquitetura assim não é Terraform ou GitOps: é os dois gerenciando o mesmo recurso e revertendo um ao outro a cada reconcile.

### CRs de CRDs criadas no mesmo apply

`ClusterSecretStore`, `NodePool` e `EC2NodeClass` são recursos customizados de CRDs que os charts acima acabaram de instalar. Com `kubernetes_manifest` o plan falha — o provider valida o manifesto contra o schema da API antes do apply, quando a CRD ainda não existe.

Por isso eles vivem em charts locais mínimos (`addons/charts/`), aplicados por `helm_release`: o Helm renderiza e aplica em tempo de apply, quando a CRD já está estabelecida.

## Estado remoto

Backend S3, criado pelo stage `bootstrap`. Cada stage tem sua própria chave de state.

## Esteiras

| Pipeline | Gatilho | O que faz |
|---|---|---|
| `bootstrap` | manual | Cria o backend S3. Executada uma única vez na vida do projeto |
| `plan` | Pull Request para `main` | `validate` → Trivy/Checkov → `plan` de cada stage, com resumo por IA |
| `apply` | merge em `main` | Aplica os stages na ordem `infra` → `addons` |
| `destroy` | manual, com confirmação | Remove recursos do cluster → destrói `addons` → destrói `infra` |

A esteira de `plan` vive em [`reusable-workflows`](https://github.com/fiap-tech-challenge-devops/reusable-workflows); o arquivo aqui é só o gatilho e os parâmetros. Os checks obrigatórios do ruleset carregam o prefixo do job chamador — `iac / Plan (infra)`, `iac / Security` e assim por diante.

> **[docs/esteira/](docs/esteira/)** tem os diagramas: o caminho de um PR até a AWS, como os quatro repositórios se referenciam, por que os stages são três, quem autoriza o quê via OIDC, e a ordem do destroy.

O `apply` não tem gate de aprovação: o gate é o pull request. O ruleset exige o `plan` verde, e quem aprova o PR já está decidindo aplicar, com o plano na frente para ler. O `destroy` mantém o gate, porque roda por disparo manual, sem PR e sem plano — ali o environment é a única confirmação humana.

O `destroy` remove os recursos do Kubernetes **antes** de destruir a infraestrutura. Load balancers criados pelo AWS Load Balancer Controller e nós criados pelo Karpenter não estão no `tfstate`: se sobreviverem ao destroy, ficam órfãos e impedem a remoção da VPC.

## Pré-requisitos

- Terraform >= 1.5
- Credenciais AWS com permissão para criar IAM, VPC, EKS, RDS, ElastiCache, DynamoDB, SQS e ECR
- `aws` CLI e `kubectl` para operar o cluster depois do apply

## Custo

O ambiente completo (EKS + 3 RDS + ElastiCache + NAT Gateway) tem custo relevante por hora. A pipeline de `destroy` existe para que o ambiente possa ser derrubado entre sessões de trabalho.
