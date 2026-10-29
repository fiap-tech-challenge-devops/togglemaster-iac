# Scripts da demonstração

Ferramentas para exercitar o ambiente provisionado e demonstrar observabilidade e resposta a incidente. **Não são ferramentas de operação** — existem para produzir sinal e para o roteiro do vídeo da Fase 4.

Moram aqui porque exercitam o que este repositório provisiona: os monitores do Datadog em [`datadog/`](../../datadog), o cluster e os bancos.

| Script | O quê |
|---|---|
| [`gerar-trafego.sh`](gerar-trafego.sh) | Tráfego contínuo em `/evaluate` para alimentar os monitores |
| [`quebrar-chave.sh`](quebrar-chave.sh) | Invalida a chave de serviço, para o incidente acontecer de verdade |

## `gerar-trafego.sh`

```bash
./gerar-trafego.sh          # 1 requisição por segundo
./gerar-trafego.sh 0.3      # mais denso
SEMEAR=false ./gerar-trafego.sh
ALB=<endereco> ./gerar-trafego.sh
```

O endereço do ALB é **descoberto pelo `kubectl`**, não cravado — ele muda a cada reconstrução do ambiente.

### Ele semeia antes de começar

Nada no GitOps cria flags, então um ambiente recém-construído tem o banco vazio. E **404 não é cacheado**: o evaluator sai antes do `SET` no Redis quando a flag não existe. Sem semear, não há **nenhum** cache HIT, e as "duas distribuições de latência" abaixo viram uma só.

Por isso o script cria as três flags quentes e uma regra de percentual para cada — 100%, 50% e 25% — antes da primeira requisição. É o único jeito de a premissa dele ser verdadeira.

| Detalhe | Por quê |
|---|---|
| A chave sai do **cluster**, não do Secrets Manager | é a que o serviço usa de fato, e evita trazer o `aws` para um script que só usa `kubectl` |
| `409` conta como sucesso | a flag já existe, que é o estado desejado. Idempotente sem GET antes do POST |
| Falhar **nunca** aborta o tráfego | durante o incidente a chave está quebrada e o POST devolve 401 — e é aí que o monitor mais precisa de tráfego, porque sem requisição não há denominador |

Isto torna o script **não somente-leitura**: ele escreve nos bancos de flags e de targeting. Aceitável aqui porque estes não são ferramentas de operação, mas vale saber.

`SEMEAR=false` pula a etapa.

**Uma chamada acende os quatro serviços HTTP.** O `evaluation` consulta `flag` e `targeting` em goroutines paralelas, e os dois validam a chave de serviço no `auth`. Soma-se o Redis e o envio ao SQS, que acorda o `analytics` pelo KEDA.

Metade do tráfego repete três flags "quentes" e metade sorteia. As repetidas tendem a bater cache no Redis; as sorteadas forçam MISS e o fan-out completo. São **duas distribuições de latência** em vez de uma, que é o que dá significado ao p95.

Flag inexistente serve igual: como a consulta é paralela, o `evaluation` chama os dois serviços antes de saber se a flag existe.

`Ctrl+C` imprime duração, contagem, taxa de erro e ritmo.

## `quebrar-chave.sh`

```bash
./quebrar-chave.sh --estado   # só mostra o estado, não toca em nada
./quebrar-chave.sh            # mostra, pede confirmação, quebra
./quebrar-chave.sh -y         # sem confirmação
```

Grava uma chave inválida em `togglemaster/app/evaluation`, força o sync do External Secrets e recicla os pods do `evaluation`. Depois disso o `/evaluate` responde **502** e o monitor dispara sozinho.

**Ele não sabe que o self-healing existe.** Não menciona Datadog, GitHub Actions nem a esteira — termina no estrago. O que vem depois é o sistema reagindo, e é isso que a demonstração precisa mostrar. Essa separação é o que diferencia demonstração de encenação.

### Os três passos, e por que são três

Só gravar o segredo **não quebra nada**:

| Passo | Sem ele |
|---|---|
| `put-secret-value` | o Secrets Manager continua com a chave boa |
| `force-sync` no ExternalSecret | a Secret do Kubernetes só atualiza no próximo refresh — **`refreshInterval: 1h`** |
| reciclar os pods | o processo segue com a chave antiga: `envFrom` congela a variável no start |

Os pods são reciclados **um por vez**. Derrubar os dois zera os targets saudáveis do ALB e troca o sintoma de "responde erro" (502) por "indisponível" (503) — que é outro incidente.

### A guarda, e por que ela existe

Quebrar move o `AWSCURRENT` de hoje para `AWSPREVIOUS`. Quebrar **duas vezes sem deixar curar** empurra uma chave ruim para o único degrau de rollback:

```
v1 boa (CURRENT)
  quebra → v2 ruim (CURRENT), PREVIOUS = v1 boa      self-healing funciona
  quebra de novo → v3 ruim (CURRENT), PREVIOUS = v2 RUIM   rollback impossível
```

O script sonda o `AWSCURRENT` antes de agir e **se recusa** se ele já não autentica. É o risco mais provável numa re-gravação, e o motivo mais forte para isto ser script e não comando digitado.

### O valor da chave nunca é impresso

Só os version IDs, abreviados. Chave em tela numa gravação é vazamento permanente.

## Por que o tráfego precisa existir

Os monitores avaliam **janelas móveis**. Sem requisição não há denominador para a taxa de erro nem amostra para o percentil, e os oito voltam a `NO DATA` em cinco minutos.

Por isso os monitores têm `notify_no_data = false`: num ambiente que fica destruído a maior parte do tempo, ausência de dado é o estado normal, não um incidente.
