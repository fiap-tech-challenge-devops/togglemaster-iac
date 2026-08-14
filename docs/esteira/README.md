# A esteira — Terraform e GitHub Actions

Como o código deste repositório vira infraestrutura na AWS, e quem autoriza cada passo.

Os diagramas são Mermaid dentro do Markdown: o GitHub renderiza sozinho, e uma mudança neles aparece no diff como qualquer outra linha de código.

---

## 1. De um pull request até a AWS

O caminho que um commit percorre. Nenhuma etapa é opcional.

```mermaid
flowchart TD
    dev["Alteração em infra/ ou addons/"] --> pr["Pull request para main"]

    pr --> plan["Workflow iac-plan.yml"]

    subgraph checks["Checks obrigatórios do ruleset"]
        direction LR
        v["Validate<br/>fmt + validate"]
        s["Security<br/>Trivy + Checkov"]
        p["Plan<br/>por stage"]
    end

    plan --> checks
    checks --> ia["Resumo por IA<br/>informativo, nunca gate"]
    ia --> comentario["Comentário no PR:<br/>resumo + plano completo"]

    comentario --> gate{"Os 5 checks<br/>estão verdes?"}
    gate -- não --> bloq["Merge bloqueado<br/>pelo ruleset"]
    gate -- sim --> merge["Merge para main"]

    merge --> apply["Workflow iac-apply.yml"]
    apply --> infra["terraform apply — infra"]
    infra --> addons["terraform apply — addons"]
    addons --> aws["Recursos na AWS"]

    style bloq fill:#fee2e2,stroke:#dc2626
    style aws fill:#dcfce7,stroke:#16a34a
    style ia fill:#e0e7ff,stroke:#6366f1
```

**O gate é o pull request, e só ele.** O `apply` não tem aprovação própria: quem aprova o PR já decidiu aplicar, e foi a única pessoa que teve o plano na frente para ler. Exigir um segundo `approve` no environment aprovaria a mesma decisão duas vezes — e um apply parado nesse portão segurava o grupo de `concurrency`, enfileirando os merges seguintes.

O `destroy` é a exceção: roda por disparo manual, sem PR e sem plano, então mantém o gate de environment como única confirmação humana.

---

## 2. Os quatro repositórios

Cada seta é uma referência fixada em **tag**, nunca em `main`.

```mermaid
flowchart LR
    subgraph mods["terraform-aws-modules"]
        m["vpc · eks · rds · ecr<br/>elasticache · sqs · dynamodb<br/>iam-irsa · secrets-manager"]
    end

    subgraph rw["reusable-workflows"]
        w["terraform-plan<br/>terraform-apply<br/>terraform-destroy"]
        a["action:<br/>terraform-plan-summary"]
        w --> a
    end

    subgraph iac["togglemaster-iac (aqui)"]
        c["iac-plan · iac-apply<br/>iac-destroy · iac-bootstrap"]
        t["bootstrap/ · infra/ · addons/"]
    end

    subgraph gitops["togglemaster-gitops"]
        g["Charts dos 5 microsserviços"]
    end

    m -->|"source = ...?ref=vX.Y.Z"| t
    w -->|"uses: ...@vX.Y.Z"| c
    c --> t
    t -->|"provisiona"| cluster["EKS"]
    cluster -->|"Argo CD sincroniza"| g

    style mods fill:#f0f9ff,stroke:#0369a1
    style rw fill:#faf5ff,stroke:#7e22ce
    style iac fill:#fffbeb,stroke:#b45309
    style gitops fill:#f0fdf4,stroke:#16a34a
```

**Por que tag e não `main`:** um commit na biblioteca não pode alterar o plano deste repositório sem uma mudança explícita aqui. Se a referência fosse `main`, o mesmo commit produziria planos diferentes em dias diferentes.

Isso já mordeu: uma tag criada **antes** do commit que acrescentava os workflows fez o `apply` falhar sem criar nenhum job — o GitHub não conseguia resolver a referência. Ordem correta: commit, push, e só então a tag.

---

## 3. Os três stages e por que são três

```mermaid
flowchart TD
    b["bootstrap<br/><br/>bucket S3 do state · KMS<br/>5 repositórios ECR<br/>role de CI"]
    i["infra<br/><br/>VPC · EKS · 3 RDS · Redis<br/>SQS · DynamoDB · Secrets<br/>IRSA · plano AWS do Karpenter"]
    ad["addons<br/><br/>metrics-server · KEDA<br/>External Secrets · LB Controller<br/>Karpenter · Argo CD"]

    b -->|"state remoto existe"| i
    i -->|"cluster existe<br/>parâmetros no SSM"| ad

    b -.->|"disparo manual, raro"| bt["iac-bootstrap.yml"]
    i -.-> ap["iac-apply.yml"]
    ad -.-> ap

    style b fill:#fef3c7,stroke:#d97706
    style i fill:#dbeafe,stroke:#2563eb
    style ad fill:#dcfce7,stroke:#16a34a
```

| stage | por que é separado |
|---|---|
| **bootstrap** | Ovo e galinha: o bucket que guarda o `tfstate` não pode guardar o state que o cria. Roda com state local na primeira execução e depois migra o próprio state para o bucket. O ECR vive aqui para a CI dos microsserviços ser testável sem subir a infraestrutura, e para as imagens sobreviverem ao `destroy`. |
| **infra** | Usa só o provider `aws` e cabe num apply só. |
| **addons** | Precisa dos providers `helm` e `kubernetes` apontando para um cluster que só existe depois do `infra`. O Terraform não permite que a configuração de um provider dependa de recursos do mesmo apply — daí o state próprio. |

---

## 4. Quem autoriza o quê

Nenhum segredo de longa duração da AWS existe neste repositório.

```mermaid
flowchart LR
    job["Job do Actions<br/>permissions:<br/>id-token: write"]

    job -->|"1. pede token"| gh["GitHub OIDC Provider"]
    gh -->|"2. JWT assinado"| job
    job -->|"3. AssumeRoleWithWebIdentity"| sts["AWS STS"]
    sts -->|"4. verifica assinatura<br/>com a chave pública"| gh
    sts -->|"5. lê trust policy"| role["IAM Role<br/>github-actions-iac"]
    sts -->|"6. credenciais temporárias"| job
    job -->|"7. terraform apply"| aws["Recursos AWS"]

    key["Secret OPENAI_API_KEY<br/>só o resumo por IA usa"] -.-> job

    style gh fill:#f6f8fa,stroke:#57606a
    style role fill:#fff8f0,stroke:#ff9900
    style key fill:#f3e8ff,stroke:#9333ea
```

A trust policy da role restringe por `sub`. Esta organização usa a claim `sub` customizada do GitHub, que injeta IDs imutáveis:

```
repo:fiap-tech-challenge-devops@283760261/togglemaster-iac@1314140933:ref:refs/heads/main
```

O padrão clássico `repo:<org>/<repo>:*` **não casa** com isso — o sufixo `@<id>` aparece antes da barra, onde o curinga final não alcança. O sintoma é `Not authorized to perform sts:AssumeRoleWithWebIdentity` com a trust policy parecendo correta.

Detalhe geral do OIDC, sem os nomes deste projeto: [board no Miro](https://miro.com/app/board/uXjVHxnRqDY=/).

---

## 5. O caminho de volta — destroy

A ordem é o inverso, e o primeiro passo não é Terraform.

```mermaid
flowchart TD
    d["Disparo manual<br/>confirm: DESTROY"] --> guard{"texto confere?"}
    guard -- não --> abort["Aborta"]
    guard -- sim --> env["Gate do environment<br/>production"]

    env --> limpa["Limpar o cluster<br/>Argo CD · Ingresses<br/>Services LB · NodePools"]
    limpa --> espera["Aguarda 90s<br/>controllers liberarem na AWS"]
    espera --> da["terraform destroy — addons"]
    da --> di["terraform destroy — infra"]
    di --> fim["bootstrap sobrevive:<br/>state e ECR permanecem"]

    style abort fill:#fee2e2,stroke:#dc2626
    style limpa fill:#fef3c7,stroke:#d97706
    style fim fill:#dcfce7,stroke:#16a34a
```

**Por que limpar o cluster antes.** Load balancers criados pelo AWS Load Balancer Controller e nós criados pelo Karpenter **não estão no `tfstate`** — quem os cria são controllers rodando dentro do cluster. Se sobreviverem, ficam órfãos e seguram a VPC: o `terraform destroy` trava em `DependencyViolation` ao remover as subnets.

O Argo CD sai primeiro porque, se ficar de pé, ele recria tudo o que for apagado em seguida.
