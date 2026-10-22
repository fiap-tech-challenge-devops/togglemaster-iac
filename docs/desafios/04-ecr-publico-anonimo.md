# Fase 4 — O pull anônimo que quebrava apply e destroy

O chart do Karpenter vem de um registro OCI público, e o pull era anônimo. A cota anônima do `public.ecr.aws` é **por IP** — e runners do GitHub Actions têm IPs compartilhados entre milhares de execuções.

O resultado é uma esteira que falha por algo que não está sob controle de ninguém no projeto.

## O erro

```
Error: Error locating chart

  with helm_release.karpenter,
  on karpenter.tf line 1, in resource "helm_release" "karpenter":

Unable to locate chart oci://public.ecr.aws/karpenter/karpenter: failed to
perform "FetchReference" on source: GET
"https://public.ecr.aws/v2/karpenter/karpenter/manifests/1.3.3":
response status code 429: toomanyrequests: Data limit exceeded
```

## O que tornou o diagnóstico errado na primeira vez

Aconteceu primeiro num **destroy**, em 16/10. A leitura inicial foi "falha transitória, basta repetir" — e repetir funcionou.

Reapareceu num **apply** em 22/10, seis dias depois. Isso derrubou a hipótese: não era rajada de uso do projeto.

A confirmação veio de fora da esteira. Da máquina de um integrante, o mesmo endpoint respondia normalmente:

```
anônimo, sem token   → HTTP 401
com token anônimo    → HTTP 200
```

Ou seja, o chart estava lá e acessível. **O 429 era do IP do runner, não do recurso.**

## Por que isso é pior do que parece

O mesmo erro **quebra o apply e o destroy**.

Parece absurdo precisar baixar um chart para destruir algo, mas o provider Helm precisa dele para montar o plano de remoção. Sem o chart, o stage `addons` falha inteiro — e o `addons` **bloqueia o `infra`**, que é onde está o que custa.

Em 16/10 o ambiente ficou **meio desmontado por horas**: `addons` destruído, `infra` de pé, com EKS, dois nós e três RDS correndo.

Essa é a parte que vale registrar para além da correção: **uma falha de rede numa dependência externa deixou o ambiente num estado caro e sem saída automática.**

## A correção

Autenticar. O job já assume uma role por OIDC, e o ECR Público emite token temporário para quem está autenticado na AWS:

```hcl
data "aws_ecrpublic_authorization_token" "token" {}

provider "helm" {
  registries = [{
    url      = "oci://public.ecr.aws"
    username = data.aws_ecrpublic_authorization_token.token.user_name
    password = data.aws_ecrpublic_authorization_token.token.password
  }]
  ...
}
```

O `user_name` é literalmente a string `AWS`, e o `password` é um token de ~12h. **Nada é criado, guardado ou rotacionado** — nem usuário, nem senha, nem secret no GitHub. O pull deixa a cota anônima compartilhada e passa a contar na cota da conta, que é muito maior.

Não abre exceção ao princípio de que nenhum segredo de longa duração da AWS vive nos repositórios: a AWS está autenticando a própria AWS.

O atributo `registries`, no plural, foi confirmado no binário do provider `hashicorp/helm v3.3.0` antes de ser escrito — a versão 2 usava blocos `registry` no singular, e a diferença falharia em tempo de plan.

## A alternativa descartada

**Espelhar o chart no ECR privado.** O stage `bootstrap` já cria repositórios ECR, e mais um removeria a dependência externa por completo.

Descartada por desproporção: resolve um problema maior do que o que existe, e cobra manutenção contínua — alguém precisa republicar o chart a cada versão nova do Karpenter, e esquecer significa aplicar uma versão desatualizada **sem nenhum aviso**.

Fica como plano B caso a cota autenticada também aperte.

## O que o episódio expôs

**A role que a esteira assume tem `AdministratorAccess`.** Isso tornou a correção trivial — a permissão `ecr-public:GetAuthorizationToken` já estava coberta.

Mas ela é um **pré-requisito manual**, criada fora do Terraform por ser circular: a esteira não pode criar a role que precisa assumir. E, por estar fora da IaC, **nunca passou pelo Trivy nem pelo Checkov**. Uma role de esteira com acesso administrativo é exatamente o tipo de achado que o gate apontaria.

A lição não é sobre esta role: **o que fica fora da IaC também fica fora da auditoria.** Vale para os três pré-requisitos manuais do projeto — o provedor OIDC, esta role, e as conexões OAuth que as integrações do Datadog vão exigir.

## Como validar

Rodar `IaC — Apply`. O job `addons` deve passar do `helm_release.karpenter` sem o 429.

Se voltar a falhar com `429`, a cota autenticada também apertou, e aí o plano B passa a valer.
