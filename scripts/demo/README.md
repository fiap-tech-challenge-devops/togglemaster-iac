# Scripts da demonstração

Ferramentas para exercitar o ambiente provisionado e demonstrar observabilidade e resposta a incidente. **Não são ferramentas de operação** — existem para produzir sinal e para o roteiro do vídeo da Fase 4.

Moram aqui porque exercitam o que este repositório provisiona: os monitores do Datadog em [`datadog/`](../../datadog), o cluster e os bancos.

| Script | O quê |
|---|---|
| [`gerar-trafego.sh`](gerar-trafego.sh) | Tráfego contínuo em `/evaluate` para alimentar os monitores |

## `gerar-trafego.sh`

```bash
./gerar-trafego.sh        # 1 requisição por segundo
./gerar-trafego.sh 0.3    # mais denso
ALB=<endereco> ./gerar-trafego.sh
```

O endereço do ALB é **descoberto pelo `kubectl`**, não cravado — ele muda a cada reconstrução do ambiente.

**Uma chamada acende os quatro serviços HTTP.** O `evaluation` consulta `flag` e `targeting` em goroutines paralelas, e os dois validam a chave de serviço no `auth`. Soma-se o Redis e o envio ao SQS, que acorda o `analytics` pelo KEDA.

Metade do tráfego repete três flags "quentes" e metade sorteia. As repetidas tendem a bater cache no Redis; as sorteadas forçam MISS e o fan-out completo. São **duas distribuições de latência** em vez de uma, que é o que dá significado ao p95.

Flag inexistente serve igual: como a consulta é paralela, o `evaluation` chama os dois serviços antes de saber se a flag existe.

`Ctrl+C` imprime duração, contagem, taxa de erro e ritmo.

## Por que o tráfego precisa existir

Os monitores avaliam **janelas móveis**. Sem requisição não há denominador para a taxa de erro nem amostra para o percentil, e os oito voltam a `NO DATA` em cinco minutos.

Por isso os monitores têm `notify_no_data = false`: num ambiente que fica destruído a maior parte do tempo, ausência de dado é o estado normal, não um incidente.
