#!/usr/bin/env bash
#
# Gera tráfego contínuo em /evaluate para alimentar os monitores do Datadog.
#
# Uma chamada acende os quatro serviços: o evaluation recebe, consulta flag e
# targeting em paralelo, e os dois validam a chave no auth. Mais Redis e SQS.
#
# O gerador só pede flags que ele mesmo criou, então o mapa do APM fica limpo
# enquanto o ambiente está saudável. Vermelho ali passa a significar incidente.
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

# Dois lotes, ambos semeados. A diferença é só a frequência com que cada flag
# é sorteada, e é ela que produz as duas distribuições de latência:
#
#   quentes — 3 flags levando metade do tráfego, tocadas a cada ~6s, bem
#             abaixo do TTL de 30s do Redis: HIT, resposta sem fan-out
#   frias   — 40 flags dividindo a outra metade, cada uma tocada a cada ~80s,
#             bem acima do TTL: MISS, fan-out completo para flag e targeting
QUENTES=(nova-home checkout-v2 busca-semantica)
PERCENTUAIS=(100 50 25)
FRIAS=()
for n in $(seq -w 1 40); do FRIAS+=("catalogo-$n"); done

USUARIOS=(ana bruno carla diego elena)

# TTL do cache no evaluation-service, em segundos. Ver CACHE_TTL em evaluator.go.
TTL=30

# --- aparência -------------------------------------------------------------
if [ -t 1 ]; then
  N=$'\e[0m'; B=$'\e[1m'; VERD=$'\e[32m'; AMAR=$'\e[33m'; CINZ=$'\e[90m'
else
  N=""; B=""; VERD=""; AMAR=""; CINZ=""
fi
titulo() {
  echo
  echo "${B}══════════════════════════════════════════════════════════════${N}"
  echo "${B} $1${N}"
  echo "${B}══════════════════════════════════════════════════════════════${N}"
}
passo()   { echo; echo "${B}▶ $1${N}"; }
nota()    { echo "  ${CINZ}$1${N}"; }
subnota() { echo "            ${CINZ}$1${N}"; }

# Sem semear não existe cache HIT: 404 não é cacheado, o evaluator sai antes do
# SET. E flag inexistente é erro no span de cliente, o que deixaria o mapa
# vermelho antes de qualquer incidente.
#
# Nunca aborta. Durante o incidente a chave está quebrada e o POST devolve 401
# — e é justo aí que o monitor mais precisa de tráfego, porque sem requisição
# não há denominador para a taxa de erro.
semear() {
  local chave existentes flag codigo criadas=0 i

  # A chave sai do cluster, não do Secrets Manager: é a que o serviço está de
  # fato usando, e evita trazer o aws CLI para um script que só usa kubectl.
  chave=$(kubectl -n togglemaster get secret evaluation-service-app-secret \
    -o jsonpath='{.data.SERVICE_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null)

  if [ -z "$chave" ]; then
    echo "Não li a chave de serviço no cluster. Seguindo sem semear."
    echo
    return
  fi

  # Uma chamada lista tudo que já existe. Evita o POST que falha: INSERT
  # duplicado devolve 409, mas falha no banco antes disso, e a instrumentação
  # marca aquele span como erro — sujaria o mapa a cada arranque.
  existentes=$(curl -s --max-time 30 "http://$ALB/flags" \
    -H "Authorization: Bearer $chave" 2>/dev/null \
    | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')

  cria() {  # $1 = nome, $2 = percentual da regra
    case $'\n'"$existentes"$'\n' in
      *$'\n'"$1"$'\n'*) return 0 ;;
    esac

    # Corpo em ASCII puro: com acento o Flask recusa antes do handler e
    # devolve um 400 em HTML do Werkzeug. Medido em 29/10.
    codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
      -X POST "http://$ALB/flags" -H "Authorization: Bearer $chave" \
      -H 'Content-Type: application/json' \
      --data "{\"name\":\"$1\",\"description\":\"Flag da demonstracao\",\"is_enabled\":true}" \
      2>/dev/null || echo 000)
    [ "$codigo" = "201" ] || { echo "  $1: flag falhou (HTTP $codigo)"; return 1; }

    # Sem regra o targeting devolve 404, que é erro no span de cliente. Com
    # regra, o percentual é de fato avaliado e a aresta fica limpa.
    codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
      -X POST "http://$ALB/rules" -H "Authorization: Bearer $chave" \
      -H 'Content-Type: application/json' \
      --data "{\"flag_name\":\"$1\",\"rules\":{\"type\":\"PERCENTAGE\",\"value\":$2},\"is_enabled\":true}" \
      2>/dev/null || echo 000)
    [ "$codigo" = "201" ] || { echo "  $1: regra falhou (HTTP $codigo)"; return 1; }

    criadas=$(( criadas + 1 ))
  }

  for i in "${!QUENTES[@]}"; do
    cria "${QUENTES[$i]}" "${PERCENTUAIS[$i]}" || { echo; return; }
  done
  for flag in "${FRIAS[@]}"; do
    cria "$flag" 50 || { echo; return; }
  done

  if [ "$criadas" -eq 0 ]; then
    echo "  ${VERD}✔${N} as $(( ${#QUENTES[@]} + ${#FRIAS[@]} )) flags já existiam — nada criado"
  else
    echo "  ${VERD}✔${N} $criadas criadas agora, cada uma com regra de percentual"
  fi
}

titulo "Tráfego contínuo em /evaluate"
echo
nota "ALB:       $ALB"
nota "intervalo: ${INTERVALO}s"

if [ "${SEMEAR:-true}" = "true" ]; then
  passo "Flags"
  semear
else
  passo "Flags"
  nota "SEMEAR=false — pulando o semeio"
fi

# A cadência de cada lote é o que produz HIT ou MISS, e ela depende do
# intervalo. Calculada para o aviso abaixo fazer sentido em qualquer ritmo.
cad_q=$(awk -v i="$INTERVALO" -v n="${#QUENTES[@]}" 'BEGIN{printf "%.0f", i*2*n}')
cad_f=$(awk -v i="$INTERVALO" -v n="${#FRIAS[@]}"   'BEGIN{printf "%.0f", i*2*n}')

passo "Os dois lotes, e o que cada um exercita"
printf "  %-10s %s\n" "quentes" "$(printf '%s, ' "${QUENTES[@]}" | sed 's/, $//')"
subnota "metade do tráfego, cada uma a cada ~${cad_q}s"
subnota "abaixo do TTL de ${TTL}s: ${B}cache HIT${N}${CINZ}, resposta sem fan-out"
printf "  %-10s %s\n" "frias" "${FRIAS[0]}..${FRIAS[-1]}  (${#FRIAS[@]})"
subnota "outra metade, cada uma a cada ~${cad_f}s"
subnota "acima do TTL: ${B}MISS${N}${CINZ}, fan-out para flag, targeting e auth"

if [ "$cad_f" -lt "$TTL" ]; then
  echo
  echo "  ${AMAR}As frias estão sendo tocadas a cada ${cad_f}s, abaixo do TTL de ${TTL}s.${N}"
  nota "Elas vão bater cache e o fan-out some. Use um intervalo maior."
fi

echo
nota "O gerador só pede flags que ele mesmo criou. Com o ambiente são, tudo"
nota "responde 200 e o mapa do APM fica limpo — vermelho ali é incidente."

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

passo "Gerando"
nota "Ctrl+C encerra e imprime o resumo."
echo

while true; do
  if [ $(( RANDOM % 2 )) -eq 0 ]; then
    flag="${QUENTES[$(( RANDOM % ${#QUENTES[@]} ))]}"      # tende a HIT
  else
    flag="${FRIAS[$(( RANDOM % ${#FRIAS[@]} ))]}"          # tende a MISS
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
