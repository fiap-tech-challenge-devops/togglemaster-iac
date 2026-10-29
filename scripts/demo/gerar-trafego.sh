#!/usr/bin/env bash
#
# Gera tráfego contínuo em /evaluate para alimentar os monitores do Datadog.
#
# Uma chamada acende os quatro serviços: o evaluation recebe, consulta flag e
# targeting em paralelo, e os dois validam a chave no auth. Mais Redis e SQS.
#
# Antes de começar, semeia as flags quentes — sem elas não existe cache HIT.
#
#   ./gerar-trafego.sh [intervalo_em_segundos]
#   SEMEAR=false ./gerar-trafego.sh
#
# Ctrl+C encerra e imprime o resumo.

set -u

INTERVALO="${1:-1}"

# O endereço do ALB muda a cada reconstrução do ambiente, então é descoberto e
# não cravado. ALB=... no ambiente sobrepõe.
ALB="${ALB:-$(kubectl -n togglemaster get ingress evaluation-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)}"

if [ -z "$ALB" ]; then
  echo "Não encontrei o ALB. O cluster está de pé e o kubeconfig atualizado?" >&2
  echo "  aws eks update-kubeconfig --name eks-togglemaster --region us-east-1" >&2
  echo "Ou informe direto:  ALB=<endereco> $0" >&2
  exit 1
fi

# Metade do tráfego repete estas chaves, para o Redis responder HIT. A outra
# metade sorteia, forçando MISS e o fan-out completo para flag e targeting.
QUENTES=(nova-home checkout-v2 busca-semantica)
PERCENTUAIS=(100 50 25)
USUARIOS=(ana bruno carla diego elena)

# O HIT do Redis só existe se a flag existir: uma resposta 404 não é cacheada,
# o evaluator sai antes do SET. Sem semear, não há HIT nenhum e as "duas
# distribuições de latência" que dão sentido ao p95 viram uma só.
#
# Nunca aborta. Durante o incidente a chave está quebrada e o POST devolve 401
# — e é justo aí que o monitor mais precisa de tráfego, porque sem requisição
# não há denominador para a taxa de erro.
semear() {
  local chave flag pct i codigo

  # A chave sai do cluster, não do Secrets Manager: é a que o serviço está de
  # fato usando, e evita trazer o aws CLI para um script que só usa kubectl.
  chave=$(kubectl -n togglemaster get secret evaluation-service-app-secret \
    -o jsonpath='{.data.SERVICE_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null)

  if [ -z "$chave" ]; then
    echo "Não li a chave de serviço no cluster. Seguindo sem semear."
    echo
    return
  fi

  echo "Semeando as flags quentes:"
  for i in "${!QUENTES[@]}"; do
    flag="${QUENTES[$i]}"; pct="${PERCENTUAIS[$i]}"

    # 409 é sucesso aqui: a flag já existe, que é o estado desejado.
    #
    # Corpo em ASCII puro de propósito: com acento, o Git Bash entrega bytes
    # que o Flask recusa antes do handler, e a resposta é um 400 em HTML do
    # Werkzeug, não o 400 em JSON da aplicação. Medido em 29/10.
    codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
      -X POST "http://$ALB/flags" -H "Authorization: Bearer $chave" \
      -H 'Content-Type: application/json' \
      --data "{\"name\":\"$flag\",\"description\":\"Flag da demonstracao\",\"is_enabled\":true}" \
      2>/dev/null || echo 000)

    case "$codigo" in
      201) printf "  %-18s flag criada" "$flag" ;;
      409) printf "  %-18s flag já existia" "$flag" ;;
      401) printf "  %-18s %s" "$flag" "sem autorização — a chave está quebrada?"; echo; continue ;;
      *)   printf "  %-18s falhou (HTTP %s)" "$flag" "$codigo"; echo; continue ;;
    esac

    # Sem regra, o targeting devolve 404 e a aresta dele fica vermelha no mapa
    # mesmo para as flags quentes. Com regra, o percentual é de fato avaliado.
    codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
      -X POST "http://$ALB/rules" -H "Authorization: Bearer $chave" \
      -H 'Content-Type: application/json' \
      --data "{\"flag_name\":\"$flag\",\"rules\":{\"type\":\"PERCENTAGE\",\"value\":$pct},\"is_enabled\":true}" \
      2>/dev/null || echo 000)

    case "$codigo" in
      201) echo ", regra de ${pct}% criada" ;;
      409) echo ", regra já existia" ;;
      *)   echo ", regra falhou (HTTP $codigo)" ;;
    esac
  done
  echo
}

[ "${SEMEAR:-true}" = "true" ] && semear

ok=0; erro=0; inicio=$(date +%s)

resumo() {
  local fim dur total
  fim=$(date +%s); dur=$(( fim - inicio )); total=$(( ok + erro ))
  echo
  echo "────────────────────────────────────"
  printf "duração:     %dm %ds\n" $(( dur / 60 )) $(( dur % 60 ))
  printf "requisições: %d  (%d ok, %d erro)\n" "$total" "$ok" "$erro"
  [ "$total" -gt 0 ] && printf "taxa de erro: %.1f%%\n" "$( echo "$erro $total" | awk '{print ($1/$2)*100}' )"
  [ "$dur" -gt 0 ] && printf "ritmo:       %.2f req/s\n" "$( echo "$total $dur" | awk '{print $1/$2}' )"
  echo "────────────────────────────────────"
  exit 0
}
trap resumo INT TERM

echo "Gerando tráfego em http://$ALB/evaluate  (intervalo ${INTERVALO}s)"
echo "Ctrl+C para parar."
echo

while true; do
  if [ $(( RANDOM % 2 )) -eq 0 ]; then
    flag="${QUENTES[$(( RANDOM % ${#QUENTES[@]} ))]}"          # tende a HIT
  else
    flag="flag-$(( RANDOM % 500 ))"                             # força MISS
  fi
  user="${USUARIOS[$(( RANDOM % ${#USUARIOS[@]} ))]}-$(( RANDOM % 50 ))"

  resposta=$(curl -s -o /dev/null --max-time 15 \
    -w '%{http_code} %{time_total}' \
    "http://$ALB/evaluate?user_id=${user}&flag_name=${flag}")

  codigo="${resposta%% *}"; tempo="${resposta##* }"

  if [ "$codigo" = "200" ]; then
    ok=$(( ok + 1 ))
    printf "%s  %s  %6.3fs  %s\n" "$(date +%T)" "$codigo" "$tempo" "$flag"
  else
    erro=$(( erro + 1 ))
    printf "%s  %s  %6.3fs  %s   <-- ERRO\n" "$(date +%T)" "$codigo" "$tempo" "$flag"
  fi

  sleep "$INTERVALO"
done
