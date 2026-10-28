#!/usr/bin/env bash
#
# Gera tráfego contínuo em /evaluate para alimentar os monitores do Datadog.
#
# Uma chamada acende os quatro serviços: o evaluation recebe, consulta flag e
# targeting em paralelo, e os dois validam a chave no auth. Mais Redis e SQS.
#
#   ./gerar-trafego.sh [intervalo_em_segundos]
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
USUARIOS=(ana bruno carla diego elena)

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
