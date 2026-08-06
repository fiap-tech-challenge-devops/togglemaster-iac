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
bootstrap/    # bucket S3 do state remoto — roda uma vez, state descartável
infra/        # rede, cluster, bancos, mensageria, registry, identidades
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
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:fiap-tech-challenge-devops/togglemaster-iac:*" }
    }
  }]
}
```

O ARN dela vai no secret `AWS_OIDC_ROLE_ARN_VITAO` do repositório.

> A condição `sub` é o que impede qualquer outro repositório do GitHub de assumir a role. Sem ela, o `aud` sozinho autorizaria o mundo inteiro.

Em permissões, `AdministratorAccess` resolve para este escopo — o stage `infra` cria VPC, EKS, RDS, IAM e ECR, e o conjunto mínimo para isso já se aproxima de admin.

### Por que três stages

**`bootstrap`** resolve o ovo-e-galinha do state: o bucket S3 que guarda o `tfstate` não pode guardar o state que o cria. Roda uma vez, com state local, e o resultado é descartável — a partir daí os demais stages usam o backend remoto. É o único recurso deste stage; a identidade das esteiras é pré-requisito manual, pelo motivo acima.

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
| `plan` | Pull Request para `main` | `validate` → Trivy/Checkov → `plan` de cada stage |
| `apply` | merge em `main` | Aplica os stages na ordem `infra` → `addons` |
| `destroy` | manual, com confirmação | Remove recursos do cluster → destrói `addons` → destrói `infra` |

O `destroy` remove os recursos do Kubernetes **antes** de destruir a infraestrutura. Load balancers criados pelo AWS Load Balancer Controller e nós criados pelo Karpenter não estão no `tfstate`: se sobreviverem ao destroy, ficam órfãos e impedem a remoção da VPC.

## Pré-requisitos

- Terraform >= 1.5
- Credenciais AWS com permissão para criar IAM, VPC, EKS, RDS, ElastiCache, DynamoDB, SQS e ECR
- `aws` CLI e `kubectl` para operar o cluster depois do apply

## Custo

O ambiente completo (EKS + 3 RDS + ElastiCache + NAT Gateway) tem custo relevante por hora. A pipeline de `destroy` existe para que o ambiente possa ser derrubado entre sessões de trabalho.
