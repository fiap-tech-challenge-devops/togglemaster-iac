variable "datadog_api_key" {
  description = "API key da conta Datadog, entregue por tf-vars."
  type        = string
  sensitive   = true
}

# Gerenciar configuração exige API key E Application key; só o envio de
# telemetria funciona com a primeira sozinha.
variable "datadog_app_key" {
  description = "Application key da conta Datadog, entregue por tf-vars. Exigida pelo provider para gerenciar monitor, webhook e integrações."
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Site da conta Datadog. Ex.: datadoghq.com, us5.datadoghq.com, datadoghq.eu."
  type        = string
  default     = "datadoghq.com"
}

variable "environment" {
  description = "Valor da tag env nos recursos do Datadog. Precisa bater com deployment.environment.name que os serviços enviam."
  type        = string
  default     = "prod"
}

variable "service_namespace" {
  description = "Valor de service.namespace que os serviços enviam, usado para escopar queries."
  type        = string
  default     = "togglemaster"
}

# Escada de dois patamares. O 5% do enunciado é exemplo, não regra — ele cita
# "taxa de HTTP 5xx do auth-service acima de 5%" como ilustração —, então ele
# virou o aviso e o crítico subiu. O que separa os dois não é gravidade
# percebida: é quem responde. O aviso vai para gente; o crítico pagina e
# autoriza a remediação automática, que reverte um segredo e recicla pods.
#
# A faixa entre os dois é onde vive a degradação parcial — réplica ruim, banco
# lento, pod com config velha. Nenhuma delas se conserta revertendo segredo,
# então é correto que essa faixa pare no Slack.
variable "error_rate_threshold" {
  description = "Percentual de erro do patamar crítico: pagina e autoriza a remediação automática."
  type        = number
  default     = 10
}

variable "error_rate_warning" {
  description = "Percentual de erro do patamar de aviso: só notifica o Slack."
  type        = number
  default     = 5
}

# Vazio enquanto Slack e PagerDuty não estão conectados. Ganha os handles
# (@slack-canal, @pagerduty-servico) quando as integrações existirem.
variable "notification_targets" {
  description = "Handles de notificação acrescentados à mensagem do monitor."
  type        = string
  default     = ""
}

# O canal é registrado à mão no painel do Datadog; aqui só se monta o handle
# que vai na mensagem do monitor. O handle precisa ser código porque a mensagem
# é gerenciada pelo Terraform — escrito à mão na UI, o próximo apply apaga.
#
# O nome é o que o Datadog registrou para o workspace ao conectar por OAuth,
# não o que aparece no Slack. Vazio tira o handle dos monitores.
variable "slack_workspace" {
  description = "Nome da conta Slack no Datadog. Vazio tira o handle dos monitores."
  type        = string
  default     = ""
}

variable "slack_channel" {
  description = "Canal que recebe os alertas, com #. Precisa já estar registrado no painel do Datadog."
  type        = string
  default     = "#alertas-prod"
}

# O handle é derivado de service_namespace e environment, os mesmos do stage
# pagerduty — não há key atravessando fronteira, só o nome. Ver ADR 0033.
variable "pagerduty_habilitado" {
  description = "Acrescenta o handle do PagerDuty à mensagem dos monitores."
  type        = bool
  default     = false
}

variable "github_org" {
  description = "Organização que hospeda o workflow de self-healing."
  type        = string
  default     = "fiap-tech-challenge-devops"
}

variable "github_repo" {
  description = "Repositório que hospeda o workflow de self-healing."
  type        = string
  default     = "togglemaster-iac"
}

# PAT de escopo repository_dispatch. Credencial de longa duração fora da IaC,
# na lista de pré-requisitos manuais — ver ADRs 0021 e 0030.
variable "github_dispatch_token" {
  description = "Token usado pelo webhook do Datadog para disparar o repository_dispatch."
  type        = string
  sensitive   = true
}
