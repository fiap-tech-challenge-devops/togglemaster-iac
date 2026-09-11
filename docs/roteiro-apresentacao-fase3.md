# Roteiro de apresentação (vídeo) — Fase 3: IaC · DevSecOps · GitOps · ArgoCD

> **Ordem da apresentação (definida por você):**
> **1)** IaC funcionando → **2)** Pipeline DevSecOps (com erro proposital) → **3)** GitOps → **4)** ArgoCD →
> **5)** os diagramas, no final, como recapitulação visual.
>
> Este roteiro é **de demonstração** — o ambiente é real (repositório `togglemaster-iac`). Cada bloco tem
> **🎙️ Fala** (o que dizer) e **🎬 Em tela / passos** (o que fazer). Leia enquanto grava.
>
> **Duração-alvo:** ~15–18 min. **Dica:** grave um take por bloco e junte depois.

---

## 🎬 Pré-requisitos (deixe pronto antes de gravar)

- [ ] `aws sts get-caller-identity` retorna a conta certa; `kubectl` no cluster:
      `aws eks update-kubeconfig --name eks-togglemaster --region us-east-1`.
- [ ] Ambiente **já aplicado** (infra + addons) — o `apply` do EKS leva ~15–20 min, então **não** faça ao vivo.
- [ ] Navegador logado no **GitHub** (repos `togglemaster-iac` e `togglemaster-gitops`) e no **Console AWS**.
- [ ] ArgoCD acessível por túnel (comando no Bloco 4). Senha do `admin` à mão.
- [ ] As **duas mudanças do erro proposital** já ensaiadas 1× (a que quebra e a que corrige) — ver Bloco 2, "ensaio".
- [ ] Os dois diagramas abertos para o final: `diagrama-terraform-fase3.jpg` e `diagrama-ci-cd-fase3.jpg`.
- [ ] Terminal com fonte grande; notificações silenciadas; tela ≥ 1080p.

---

## Bloco 0 — Abertura e contexto (0:00 – 1:00)

**🎙️ Fala:**
> "Olá, pessoal! me chamo Felipe e estou representando o grupo 2 no vídeo de apresentação do Tech Challenge da Fase 3. Antes de começar a apresentação,
> gostaria de apresentar os integrantes do **Grupo 2**: eu, Felipe Lima, Vitor Prado, Thiago Saraiva,
> Clayton Lima e Lucas Santos.
>
> Na Fase 3 a ordem foi: **'se não está no código, não existe'** — Ou seja, precisamos de uma infraestrutura
> imutável em Terraform, pipelines de segurança (DevSecOps) e deploy por GitOps com ArgoCD. Por conta da
> operação ter se tornado insustentável. Nesta demonstração vou mostrar, **funcionando**: primeiro a
> infraestrutura como código; depois o gate de segurança barrando um erro proposital; em seguida o GitOps; e
> por fim o ArgoCD sincronizando o cluster."

---

## Bloco 1 — IaC funcionando (1:00 – 5:00)

**Objetivo:** mostrar que a infra é 100% código, com estado remoto e esteira automatizada.

**🎬 Em tela:** o repositório `togglemaster-iac` no editor + GitHub Actions + Console AWS.

### 1.1 — A estrutura (rápido)
**🎙️ Fala:**
> "O repositório tem **três stages**. O primeiro é o **bootstrap**: ele cria o **bucket S3 do state**
> (criptografado com **KMS**), os **5 repositórios ECR** — um por microsserviço: auth, flag, targeting,
> evaluation e analytics — e a **role de CI** com o **OIDC** do GitHub. Esse stage roda **manualmente e uma
> única vez**, no começo do projeto: afinal, é o próprio bootstrap que **cria o bucket S3 onde o state fica
> guardado**. Como esse bucket ainda não existe na primeira execução, o bootstrap precisa rodar antes de
> tudo. Depois que o backend está criado, ele sai do fluxo do dia a dia.
>
> Os outros dois são o **infra** (VPC, EKS, 3 RDS, Redis, SQS, DynamoDB, Secrets e IRSA) e o **addons**
> (LB Controller, External Secrets, Karpenter, KEDA e o **ArgoCD**). Os módulos vêm de uma biblioteca
> versionada por tag, e o **state fica remoto** — bucket S3 versionado, com **lock nativo no próprio S3**.
> Nada de `tfstate` local."

Mostre rapidamente as pastas `bootstrap/`, `infra/`, `addons/` e o `infra/backend.tf`.

### 1.2 — A esteira (plan no PR, apply no merge)
**🎙️ Fala:**
> "O fluxo é GitOps também para a infra: toda mudança entra por **Pull Request**. O `iac-plan.yml` roda os
> checks obrigatórios — **Validate**, **Security** e **Plan** por stage — e o ruleset da `main` **bloqueia o
> merge** enquanto não estiverem todos verdes. Depois do merge, o `iac-apply.yml` aplica sozinho: primeiro
> `infra`, depois `addons`. Autenticação na AWS por **OIDC**, sem chave estática."

**🎬 Em tela:** GitHub → **Actions** → mostre uma run recente de **IaC — Apply** (verde), com os jobs
`infra` → `addons`. Abra o resumo do `addons` (tem inclusive as instruções de acesso ao ArgoCD).

### 1.3 — A prova na AWS
**🎬 Em tela — Console AWS**, mostre:
- **VPC** (`togglemaster` + subnets + NAT/IGW);
- **EKS** (`eks-togglemaster` → *Compute* → nós `Ready`);
- **RDS** (as 3 instâncias) e, se quiser, **S3** (bucket de state versionado).

**🎙️ Fala:**
> "Tudo isso foi criado por `terraform apply` na esteira — nada no console na mão. Se eu destruir e recriar,
> volta idêntico."

> **Opção (mostrar o ciclo PR→apply ao vivo, sem quebrar nada):** existe um interruptor de teste
> `infra/pr-test.tf` (`pr_test_toggle`) que **não cria recurso** — o plan mostra `0 to add, 0 to change`.
> Alterne `true/false`, abra um PR e mostre os checks verdes → merge → apply. Serve para exibir o fluxo sem
> risco. (Deixe para o Bloco 2 a versão que **falha** de propósito.)

---

## Bloco 2 — Pipeline DevSecOps no microsserviço: erro proposital → falha → correção → passa (5:00 – 9:00)

**Objetivo (entregável):** no código de um **microsserviço** — o `auth-service` — inserir um problema de
segurança, mostrar a **CI falhando no passo de segurança**, corrigir e mostrar **passando**.

**Como funciona a CI do `auth-service`** (`ci.yml` → reusable `go-ci`): o job **`Security Scan (Secrets, SAST
& SCA)`** é obrigatório e **bloqueia** em dois pontos — **Gitleaks** (segredos vazados, `--exit-code 1`) e
**Trivy `fs`** (dependências, falha em CVE **`CRITICAL`**). O **Gosec** (SAST) roda como `continue-on-error`,
então é informativo e não bloqueia. Depois, o job de imagem ainda roda **Trivy image** (container), também
barrando em `CRITICAL`.

Escolha **uma** forma de erro proposital:
- **Opção A — Segredo vazado (Gitleaks):** mais **garantida** — determinística, não depende de base de CVE.
- **Opção B — Dependência vulnerável (Trivy `fs`):** mais **fiel ao exemplo do enunciado**, mas precisa de uma CVE **CRÍTICA** (confirme no ensaio).

### ⚙️ Ensaio (faça 1× ANTES de gravar, sem câmera)
Rode o mesmo scanner que a CI usa e confirme que ele **passa a acusar** depois da alteração:
```bash
gitleaks dir . --redact --verbose --exit-code 1                 # Opção A — limpo agora → sai 0
trivy fs --scanners vuln --severity CRITICAL --exit-code 1 .    # Opção B — limpo agora → sai 0
```
Depois de introduzir o erro (passo 2), rode de novo: tem que **falhar** (`exit 1`). Ao desfazer, volta a
passar. Assim você grava sem surpresa.

### 🎬 Passo a passo (com câmera)
1. **🎙️ Fala:** "Vou simular um dev introduzindo um problema de segurança no `auth-service`. A CI tem que barrar antes de a imagem ir para o cluster."
2. **Crie a branch e o erro proposital** — use **uma** das opções:

   **Opção A · Segredo vazado** — crie o arquivo `demo_leak.go`:
   ```go
   package main

   const demoPrivateKey = `-----BEGIN PRIVATE KEY-----
   MIIBVAIBADANBgkqhkiG9w0BAQEFAKE00000000000000000000000000000000000
   -----END PRIVATE KEY-----`
   ```
   ```bash
   git checkout -b demo/devsecops
   git add demo_leak.go
   gitleaks dir . --exit-code 1        # ensaio: tem que acusar a private key
   git commit -m "demo: credencial hardcoded no código (proposital)"
   git push -u origin demo/devsecops
   ```

   **Opção B · Dependência vulnerável** — adicione um pacote com CVE **CRÍTICA** (com import em branco no `main.go`, para o `go mod tidy` não removê-lo):
   ```bash
   git checkout -b demo/devsecops
   # em main.go, no bloco de imports:  _ "<pacote-vulneravel>"
   go get <pacote-vulneravel>@<versao> && go mod tidy
   trivy fs --scanners vuln --severity CRITICAL --exit-code 1 .   # ensaio: tem que achar CRITICAL
   git commit -am "demo: dependência vulnerável (proposital)"
   git push -u origin demo/devsecops
   ```
   > Se o dry-run só mostrar **HIGH** (não CRITICAL), esta CI — que barra em `CRITICAL` — não pega; troque a dependência ou use a **Opção A**.
3. **Abra o Pull Request** para a `main`.
4. **Mostre a CI FALHANDO:** nos **Checks** do PR, o job **`ci / Security Scan (Secrets, SAST & SCA)`** fica **vermelho ❌**. Abra o log e aponte o passo que falhou:
   - Opção A → **Run Gitleaks** (achado de *private key*);
   - Opção B → **Run Trivy vulnerability scanner in fs mode** (CVE `CRITICAL` na dependência).

   **🎙️ Fala:** "A CI parou no passo de segurança: o problema foi detectado, o job falhou e a imagem nem é publicada. O erro não chega no cluster."
5. **Corrija:**
   - Opção A → `git rm demo_leak.go`
   - Opção B → remova o import e a dependência: `go get <pacote-vulneravel>@none && go mod tidy`
   ```bash
   git commit -am "fix: remove o problema de segurança" && git push
   ```
   > (Alternativa, nos dois casos: `git revert --no-edit HEAD`.)
6. **Mostre a CI PASSANDO:** o PR reexecuta → **`ci / Security Scan (Secrets, SAST & SCA)` verde ✅** → segue para o build da imagem.
7. **🎙️ Fala:** "Corrigido, o gate libera e a esteira segue: build, scan da imagem com Trivy e push para o ECR. Segurança antes de qualquer deploy."

> **Dica de gravação:** deixe as **duas mudanças prontas** (a que quebra e a que corrige) e faça o **ensaio** antes; na hora, só `push` e abrir o PR. Evita esperar e errar no vídeo.

### 🎁 Bônus (opcional) — o gate de segurança também protege a IaC
Se sobrar tempo, mostre que o mesmo princípio vale no repositório `togglemaster-iac`: um Security Group
liberando **SSH para `0.0.0.0/0`** num PR faz o check **`iac / Security`** (Trivy + Checkov) falhar com
`AWS-0107 (HIGH)` — *"Security group rule allows unrestricted ingress from any IP address"* — e o ruleset
bloqueia o merge. Você já validou este caso (arquivo `infra/demo-inseguro.tf`). É **defense-in-depth**:
segurança na aplicação **e** na infraestrutura.

---

## Bloco 3 — GitOps: o CI/CD do `auth-service` atualiza a tag no repositório GitOps (9:00 – 11:30)

**Objetivo (entregável):** mostrar a **tag da imagem** sendo atualizada no repositório de GitOps
(`togglemaster-gitops`) pela esteira do microsserviço — aqui, o **`auth-service`**.

**Como funciona no `auth-service`:**
- **CI** (`ci.yml`): a cada PR/push chama o reusable `go-ci` — build, test, scan e **push da imagem** para o
  ECR `togglemaster/auth-service:<sha>`.
- **CD** (`cd.yml`): dispara **quando a CI termina com sucesso num push na `main`** e chama o reusable `cd`,
  que faz o **bump da tag** (`<sha>`) no `togglemaster-gitops`, usando o `GITOPS_TOKEN`.
- Para exercitar o ciclo sem mudar comportamento, existe o `demo.go` (`const demoToggle`): **incrementar e
  abrir PR** dispara `commit → CI → imagem no ECR → CD → bump no GitOps`.

**🎙️ Fala:**
> "O deploy das aplicações não é `kubectl` na mão. O CI do `auth-service` builda e publica a imagem no ECR; e
> o CD **não faz deploy** — ele só **atualiza a tag da imagem** no `togglemaster-gitops`, que é a fonte da
> verdade do que roda no cluster."

### 🎬 Passo a passo (no repo `auth-service`)
1. Edite o `demo.go` e **incremente** o valor (ex.: `const demoToggle = "3"`):
   ```bash
   git checkout -b demo/bump-auth
   # incremente demoToggle em demo.go
   git commit -am "demo: bump auth-service (exercitar CI/CD → GitOps)"
   git push -u origin demo/bump-auth
   ```
2. **Abra o PR para a `main`** e mostre a **CI verde** (build · test · scan · docker) nos checks do PR.
   (O CD ainda **não** roda aqui — ele só dispara no push da `main`.)
3. **Faça o merge.** O push na `main` roda a CI de novo → ao terminar com sucesso, o **CD dispara**.
4. **🎬 Em tela:** GitHub → **Actions** → **Auth Service CI** (push/main) verde → **Auth Service CD** rodando.
5. Abra o **`togglemaster-gitops`** → **Commits** → mostre o commit automático de *bump* e o **diff**: a
   `image` do `auth-service` apontando para a **nova tag = SHA** do commit.

**🎙️ Fala:**
> "Repare: o deploy virou um `git commit` no repositório de GitOps — auditável e reversível, rollback é
> reverter o commit. E foi o CD do serviço que fez isso sozinho, sem ninguém tocar no cluster."

---

## Bloco 4 — ArgoCD detecta e sincroniza (11:30 – 14:00)

**Objetivo (entregável):** mostrar o **ArgoCD** detectando o commit no GitOps e **sincronizando** a nova
versão no cluster, automaticamente.

**Como está montado:** o ArgoCD é instalado pelo stage `addons` (`addons/argocd.tf`), com um **App raiz
(App-of-Apps)** apontando para o `togglemaster-gitops` e **sync automático** (`prune` + `selfHeal`). O
intervalo de reconciliação foi reduzido para **30s**, então a mudança aparece rápido.

### Acessar a UI (deixe aberto antes de gravar)
```bash
aws eks update-kubeconfig --name eks-togglemaster --region us-east-1
kubectl port-forward svc/argocd-server -n argocd 8080:443
# abra https://localhost:8080  (aceite o certificado)  ·  usuário: admin
# senha (se não estiver no cofre do time):
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo
```

### 🎬 Passo a passo (com câmera)
1. **🎙️ Fala:** "Quem aplica no cluster é o ArgoCD. Ele observa o `togglemaster-gitops` e reconcilia o estado desejado com o real, sozinho."
2. Mostre o **App raiz** e os **5 apps** (auth · flag · targeting · evaluation · analytics) em **Synced / Healthy**.
3. **Gatilho:** o commit de *bump* do Bloco 3. Em segundos o app do **`auth-service`** fica **OutOfSync** (ou clique **Refresh**).
4. Mostre o **sync automático** entrando: o ArgoCD aplica o novo manifesto e o app volta para **Synced /
   Healthy**. Abra a árvore de recursos e mostre o novo **ReplicaSet/Pod** subindo.
5. **Prova no cluster (terminal):**
   ```bash
   kubectl -n togglemaster get pods -w
   kubectl -n togglemaster get deploy auth-service \
     -o jsonpath='{.spec.template.spec.containers[0].image}'; echo   # imagem com a tag nova
   ```
6. **🎙️ Fala:** "Ninguém rodou `kubectl apply`. O ArgoCD viu o commit e sincronizou — GitOps de ponta a ponta."

---

## Bloco 5 — Os diagramas (recapitulação visual) (14:00 – 16:30)

**🎙️ Fala:**
> "Para fechar, os dois diagramas que amarram o que acabei de mostrar."

**🎬 Em tela — Diagrama 1: `diagrama-terraform-fase3.jpg`** (percorra os 3 painéis):
> "**Estrutura:** os módulos reutilizáveis + o `iac/` (bootstrap/infra/addons) + o backend remoto (S3 +
> DynamoDB). **Esteiras:** Bootstrap (1×), Plan (no PR, com trivy/checkov), Apply (infra→addons) e Destroy.
> **Fluxos:** o Bootstrap manual, o Plan/Apply pelo PR→merge, e o Destroy sob demanda — foi exatamente o que
> vimos nos Blocos 1 e 2."

**🎬 Em tela — Diagrama 2: `diagrama-ci-cd-fase3.jpg`** (percorra os 4 painéis):
> "**Estrutura CI:** os 5 serviços chamando workflows reutilizáveis. **GitOps:** o `togglemaster-gitops` como
> estado desejado. **Esteiras CI/CD:** build → lint → security scan (com gate) → docker; e o CD fazendo o
> bump da tag. **Fluxo:** push → CI → validação → CD → bump no GitOps → **ArgoCD** → **EKS** — os Blocos 3 e 4."

> Bônus: o repositório tem os mesmos fluxos em Mermaid em `docs/esteira/README.md` (renderiza no GitHub) —
> útil se quiser mostrar direto do repo em vez das imagens.

---

## Bloco 6 — Fechamento (16:30 – 17:00)

**🎙️ Fala:**
> "Recapitulando: **Terraform** com estado remoto e esteira por PR resolve a infra manual; o **gate de
> segurança** barra o que é crítico antes de aplicar; e **GitOps + ArgoCD** tornam o deploy um `git commit`
> que o cluster reconcilia sozinho. Tudo versionado, auditável e reproduzível. Obrigado!"

---

## ✅ Checklist final
- [ ] **IaC:** run de Apply verde (infra→addons) + recursos no Console AWS (VPC/EKS/RDS).
- [ ] **DevSecOps:** PR com `Security` ❌ (SSH 0.0.0.0/0) → correção → `Security` ✅ + merge liberado (ensaio feito antes!).
- [ ] **GitOps:** commit de bump da tag no `togglemaster-gitops` (CI ou manual).
- [ ] **ArgoCD:** OutOfSync → auto-sync → Synced/Healthy + pod novo com a tag nova.
- [ ] **Diagramas:** os dois JPGs no final, amarrando a demo.

> **Observações**
> - Os dois JPGs estão hoje em `togglemaster-platform/docs/` — copie-os para `docs/` deste repo se quiser tudo junto.
> - O "erro proposital" aqui é na **esteira de IaC** (Trivy/Checkov), que é o que está pronto e é 100%
>   reproduzível. Se as esteiras de CI dos microsserviços já estiverem prontas, dá para repetir o mesmo
>   roteiro lá com uma **dependência vulnerável** (Trivy `fs`) ou um **segredo vazado** (gitleaks).
