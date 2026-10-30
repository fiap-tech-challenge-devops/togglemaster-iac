#!/usr/bin/env bash
#
# Quebra a chave de serviço do evaluation-service, para demonstrar o incidente.
#
# Este script NÃO sabe que o self-healing existe. Ele termina no estrago; a
# detecção, a triagem e a remediação acontecem sozinhas depois, e é isso que a
# demonstração precisa mostrar.
#
#   ./quebrar-chave.sh            # mostra o estado, pede confirmação, quebra
#   ./quebrar-chave.sh --estado   # só mostra o estado, não toca em nada
#   ./quebrar-chave.sh -y         # sem confirmação
#
# O valor da chave nunca é impresso. Só os version IDs.

set -uo pipefail

SEGREDO="togglemaster/app/evaluation"
NAMESPACE="togglemaster"
FLAG_SONDA="sonda-self-healing-inexistente"
AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_REGION

SO_ESTADO=false
SEM_CONFIRMAR=false
for arg in "$@"; do
  case "$arg" in
    --estado) SO_ESTADO=true ;;
    -y|--sim) SEM_CONFIRMAR=true ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

# --- aparência -------------------------------------------------------------
if [ -t 1 ]; then
  N=$'\e[0m'; B=$'\e[1m'; VERM=$'\e[31m'; VERD=$'\e[32m'; AMAR=$'\e[33m'; CINZ=$'\e[90m'
else
  N=""; B=""; VERM=""; VERD=""; AMAR=""; CINZ=""
fi

titulo() {
  echo
  echo "${B}══════════════════════════════════════════════════════════════${N}"
  echo "${B} $1${N}"
  echo "${B}══════════════════════════════════════════════════════════════${N}"
}
passo() { echo; echo "${B}▶ $1${N}"; }
ok()    { echo "  ${VERD}✔${N} $1"; }
nao()   { echo "  ${VERM}✘${N} $1"; }
nota()  { echo "  ${CINZ}$1${N}"; }

morrer() { echo; echo "${VERM}${B}✘ $1${N}" >&2; exit 1; }

# --- consultas -------------------------------------------------------------
versao_de() {  # $1 = version stage -> version id, ou vazio
  aws secretsmanager get-secret-value --secret-id "$SEGREDO" \
    --version-stage "$1" --query VersionId --output text 2>/dev/null
}

# Sem jq: ele não vem no Git Bash, e uma demonstração ao vivo não é hora de
# descobrir dependência faltando. O segredo é gerado pelo Terraform com uma
# chave só e sem aninhamento — {"SERVICE_API_KEY":"tm_key_…"} — então o sed
# basta e não tem como se perder.
chave_de() {   # $1 = version stage -> valor. Nunca é impresso.
  aws secretsmanager get-secret-value --secret-id "$SEGREDO" \
    --version-stage "$1" --query SecretString --output text 2>/dev/null \
    | sed -E 's/.*"SERVICE_API_KEY"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
}

sonda() {      # $1 = chave -> código HTTP do flag-service
  curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    "http://$ALB/flags/$FLAG_SONDA" -H "Authorization: Bearer $1" 2>/dev/null || echo 000
}

# Uma chave é válida se o flag-service passa da autenticação. 404 é o esperado:
# a flag não existe de propósito, então chegar ao 404 prova que a chave passou.
autentica() { case "$1" in 404|200) return 0 ;; *) return 1 ;; esac; }

# Flag sorteada força MISS no Redis: com cache quente o /evaluate responderia
# 200 mesmo com a chave quebrada, e o sintoma não apareceria.
fluxo() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    "http://$ALB/evaluate?user_id=sonda-demo&flag_name=sorteio-$RANDOM" 2>/dev/null || echo 000
}

linha_versao() {  # $1 = rótulo, $2 = version id, $3 = código da sonda
  local marca
  if autentica "$3"; then marca="${VERD}autentica${N}"; else marca="${VERM}não autentica${N}  (HTTP $3)"; fi
  printf "  %-12s %s   %s\n" "$1" "${2:0:8}…" "$marca"
}

# --- pré-requisitos --------------------------------------------------------
titulo "Estado atual"

for bin in aws kubectl curl; do
  command -v "$bin" >/dev/null 2>&1 || morrer "Falta o $bin no PATH."
done

aws sts get-caller-identity >/dev/null 2>&1 \
  || morrer "Sem credencial AWS válida. Tente: export AWS_PROFILE=<perfil>"

# O endereço do ALB muda a cada reconstrução do ambiente, então é descoberto.
ALB="${ALB:-$(kubectl -n "$NAMESPACE" get ingress evaluation-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)}"
[ -n "$ALB" ] || morrer "Não encontrei o ALB. O cluster está de pé e o kubeconfig atualizado?
  aws eks update-kubeconfig --name eks-togglemaster --region $AWS_REGION"

id_atual=$(versao_de AWSCURRENT)
id_anterior=$(versao_de AWSPREVIOUS)
[ -n "$id_atual" ] || morrer "Não consegui ler o AWSCURRENT de $SEGREDO."

cod_atual=$(sonda "$(chave_de AWSCURRENT)")
if [ -n "$id_anterior" ]; then
  cod_anterior=$(sonda "$(chave_de AWSPREVIOUS)")
else
  cod_anterior=""
fi

echo
nota "segredo: $SEGREDO"
nota "ALB:     $ALB"
echo
linha_versao "AWSCURRENT" "$id_atual" "$cod_atual"
if [ -n "$id_anterior" ]; then
  linha_versao "AWSPREVIOUS" "$id_anterior" "$cod_anterior"
else
  printf "  %-12s %s\n" "AWSPREVIOUS" "${AMAR}não existe${N}"
fi

if $SO_ESTADO; then
  echo
  nota "Modo --estado: nada foi alterado."
  exit 0
fi

# --- guarda ----------------------------------------------------------------
# Quebrar move o AWSCURRENT de hoje para AWSPREVIOUS. Se o AWSPREVIOUS de hoje
# já não autentica, quebrar agora empurra uma chave ruim para o único degrau de
# rollback que existe, e o self-healing não teria para onde voltar.
passo "Guarda: o rollback está disponível?"

if ! autentica "$cod_atual"; then
  nao "O AWSCURRENT já não autentica (HTTP $cod_atual)."
  echo
  nota "O ambiente já está quebrado. Quebrar de novo torna o AWSPREVIOUS"
  nota "inválido também, e aí nem o self-healing nem este script consertam."
  echo
  nota "Deixe a esteira curar primeiro, ou confira em:"
  nota "  https://github.com/fiap-tech-challenge-devops/togglemaster-iac/actions"
  morrer "Nada foi alterado."
fi
ok "AWSCURRENT autentica — é esta chave que vai para o AWSPREVIOUS."
nota "Depois da quebra, é por ela que o self-healing volta."

# --- confirmação -----------------------------------------------------------
if ! $SEM_CONFIRMAR; then
  echo
  echo "  ${AMAR}Isto derruba o /evaluate de verdade, em produção.${N}"
  printf "  Confirma? [s/N] "
  read -r resposta
  case "$resposta" in [sS]) ;; *) echo; nota "Cancelado. Nada foi alterado."; exit 0 ;; esac
fi

# --- o estrago -------------------------------------------------------------
titulo "Quebrando"

passo "1/3  Gravando uma chave inválida no Secrets Manager"
# Formato realista de propósito: o auth-service hasheia o que chegar, então o
# que se demonstra é uma chave ERRADA, não uma chave malformada.
nova="tm_key_invalida-demo-$(date +%s)"
aws secretsmanager put-secret-value --secret-id "$SEGREDO" \
  --secret-string "{\"SERVICE_API_KEY\":\"$nova\"}" \
  --query VersionId --output text >/dev/null \
  || morrer "Falhou o put-secret-value."
ok "Nova versão gravada como AWSCURRENT."
nota "O AWS moveu o AWSCURRENT antigo para AWSPREVIOUS sozinho."

passo "2/3  Forçando o External Secrets a sincronizar"
nota "Sem isto a Secret do Kubernetes só atualizaria no próximo refreshInterval — 1h."
for es in evaluation-service-app auth-service; do
  if kubectl annotate externalsecret "$es" -n "$NAMESPACE" \
       force-sync="$(date +%s)" --overwrite >/dev/null 2>&1; then
    ok "$es sincronizado"
  else
    nao "$es não respondeu (segue assim mesmo)"
  fi
done
if kubectl wait --for=condition=Ready externalsecret/evaluation-service-app \
     -n "$NAMESPACE" --timeout=90s >/dev/null 2>&1; then
  ok "Secret do Kubernetes atualizada"
else
  nao "Timeout esperando o ESO"
fi

passo "3/3  Reciclando os pods do evaluation-service"
nota "envFrom congela a variável no start: sem reciclar, o processo seguiria"
nota "usando a chave antiga, que ainda funciona."
# Um pod por vez. Derrubar os dois zera os targets saudáveis do ALB e troca o
# sintoma de "responde erro" (502) por "indisponível" (503) — que é outro
# incidente, e não o que esta demonstração explica.
for pod in $(kubectl -n "$NAMESPACE" get pods -l app=evaluation-service -o name 2>/dev/null); do
  kubectl delete "$pod" -n "$NAMESPACE" >/dev/null 2>&1
  kubectl rollout status deploy/evaluation-service -n "$NAMESPACE" --timeout=120s >/dev/null 2>&1
  ok "${pod#pod/} reciclado"
done

# --- depois ----------------------------------------------------------------
titulo "Depois"

id_atual_2=$(versao_de AWSCURRENT)
id_anterior_2=$(versao_de AWSPREVIOUS)
cod_atual_2=$(sonda "$(chave_de AWSCURRENT)")
cod_anterior_2=$(sonda "$(chave_de AWSPREVIOUS)")

echo
linha_versao "AWSCURRENT" "$id_atual_2" "$cod_atual_2"
linha_versao "AWSPREVIOUS" "$id_anterior_2" "$cod_anterior_2"
echo
nota "O AWSPREVIOUS é a chave que estava valendo há um minuto. É o caminho de volta."

passo "Confirmando o sintoma"
cod_fluxo=$(fluxo)
if [ "$cod_fluxo" = "502" ]; then
  echo "  ${VERM}${B}GET /evaluate → 502${N}"
  nota "O evaluation chamou o flag, o flag repassou ao auth, o auth não achou o"
  nota "hash da chave nova no banco. 401 lá dentro vira 502 aqui fora."
elif [ "$cod_fluxo" = "200" ]; then
  nao "GET /evaluate → 200. O estrago não pegou."
  nota "Pods novos já de pé? Tente de novo em alguns segundos."
else
  nao "GET /evaluate → $cod_fluxo (esperado 502)."
  nota "Outro código significa outra causa. Vale olhar antes de gravar."
fi

# --- o que esperar ---------------------------------------------------------
titulo "A partir daqui é sozinho"

cat <<EOF

  ${B}agora${N}         os 502 começam a aparecer no gerar-trafego.sh
                ${CINZ}(se ele não estiver rodando, não há denominador e nada dispara)${N}

  ${B}2 a 6 min${N}     o monitor do Datadog dispara
                ${CINZ}janela de 5 min + evaluation_delay de 60s${N}
                ${CINZ}aviso (5%) e crítico (10%) caem quase juntos: numa quebra${N}
                ${CINZ}total a razão cruza os dois com ~15s de diferença${N}

  ${B}no disparo${N}    três destinos ao mesmo tempo:
                  • PagerDuty abre incidente
                  • Slack recebe o aviso em #alertas-prod
                  • o webhook dispara a esteira de self-healing

  ${B}+ espera${N}      a esteira tria e então ${B}confirma${N}, re-sondando a credencial
                ${CINZ}não remedia o que se resolveu sozinho — 90s por padrão,${N}
                ${CINZ}na variável de repositório SELF_HEALING_ESPERA${N}

  ${B}~50 s${N}         remedia e verifica

  ${B}no fim${N}        o Slack recebe o relatório do que foi feito

EOF
nota "Esteira: https://github.com/fiap-tech-challenge-devops/togglemaster-iac/actions/workflows/self-healing.yml"
echo
