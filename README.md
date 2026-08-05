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

## Estrutura prevista

```
iac/
├── bootstrap/    # bucket S3 do state remoto — roda uma vez, state descartável
├── infra/        # rede, cluster, bancos, mensageria, registry, identidades
└── platform/     # bootstrap do Argo CD (o que precisa existir antes do GitOps assumir)
```

### Por que três stages

**`bootstrap`** resolve o ovo-e-galinha do state: o bucket S3 que guarda o `tfstate` não pode guardar o state que o cria. Roda uma vez, com state local, e o resultado é descartável — a partir daí os demais stages usam o backend remoto.

**`infra`** usa apenas o provider `aws` e cabe em um único apply. Isso inclui o plano AWS do Karpenter e do Load Balancer Controller (IAM, IRSA, SQS, EventBridge), que vêm dos módulos `eks-karpenter` e `eks-aws-lb-controller` da biblioteca.

**`platform`** é separado porque precisa dos providers `helm`/`kubernetes` apontando para um cluster que só existe depois do `infra`. O Terraform não permite que a configuração de um provider dependa de recursos do mesmo apply, e é por isso que o stage é seu próprio state.

O escopo do `platform` é intencionalmente mínimo: o Argo CD e a credencial dele para ler o repositório GitOps. Todo o resto (External Secrets, cert-manager, KEDA, Prometheus, o chart do Karpenter) é instalado pelo Argo CD a partir do `togglemaster-gitops`.

## Estado remoto

Backend S3, criado pelo stage `bootstrap`. Cada stage tem sua própria chave de state.

## Esteiras

| Pipeline | Gatilho | O que faz |
|---|---|---|
| `bootstrap` | manual | Cria o backend S3. Executada uma única vez na vida do projeto |
| `plan` | Pull Request para `main` | `validate` → `tfsec`/`checkov` → `plan` de cada stage |
| `apply` | merge em `main` | Aplica os stages na ordem `infra` → `platform` |
| `destroy` | manual, com confirmação | Remove recursos do cluster → destrói `platform` → destrói `infra` |

O `destroy` remove os recursos do Kubernetes **antes** de destruir a infraestrutura. Load balancers criados pelo AWS Load Balancer Controller e nós criados pelo Karpenter não estão no `tfstate`: se sobreviverem ao destroy, ficam órfãos e impedem a remoção da VPC.

## Pré-requisitos

- Terraform >= 1.5
- Credenciais AWS com permissão para criar IAM, VPC, EKS, RDS, ElastiCache, DynamoDB, SQS e ECR
- `aws` CLI e `kubectl` para operar o cluster depois do apply

## Custo

O ambiente completo (EKS + 3 RDS + ElastiCache + NAT Gateway) tem custo relevante por hora. A pipeline de `destroy` existe para que o ambiente possa ser derrubado entre sessões de trabalho.
