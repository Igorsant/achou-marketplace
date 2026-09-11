variable "tenancy_ocid" {
  description = "OCID da tenancy (Perfil > Tenancy, ou a linha tenancy= do ~/.oci/config)."
  type        = string
}

variable "usuario_ocid" {
  description = "OCID do seu usuario (linha user= do ~/.oci/config). Usado para gerar o token do registro de imagens."
  type        = string
}

variable "regiao" {
  description = "Home region da conta (ex.: sa-saopaulo-1). Recursos Always Free so existem na home region."
  type        = string
}

variable "perfil_oci" {
  description = "Perfil do ~/.oci/config usado pelo provider."
  type        = string
  default     = "DEFAULT"
}

variable "nome" {
  description = "Prefixo dos recursos e nome do compartimento."
  type        = string
  default     = "achou"
}

variable "ips_admin" {
  description = "CIDRs com acesso a API do Kubernetes (porta 6443). Troque 0.0.0.0/0 pelo seu IP (/32)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "versao_kubernetes" {
  description = "Versao do Kubernetes (ex.: v1.34.1). Vazio = a mais recente oferecida pelo OKE."
  type        = string
  default     = ""
}

variable "indice_ad" {
  description = "Availability domain dos nodes (0, 1 ou 2). Se o apply falhar com 'Out of host capacity', tente outro."
  type        = number
  default     = 0
}

# ------------------------------------------------------------ nodes (Always Free)
# 1.500 OCPU-hora e 9.000 GB-hora de Ampere A1 por mes = 2 OCPUs e 12 GB
# ligados o mes inteiro. Os nodes ficam dentro disso de proposito: o credito
# vai para o Postgres gerenciado. Para gastar credito com nodes maiores,
# relaxe as validacoes abaixo conscientemente.

variable "nodes" {
  description = "Quantidade de nodes. 2 mostra o cluster distribuindo pods; 1 sobra mais CPU para a aplicacao."
  type        = number
  default     = 2
  validation {
    condition     = var.nodes >= 1 && var.nodes <= 2
    error_message = "Use 1 ou 2 nodes: o Always Free da 2 OCPUs no total."
  }
}

variable "ocpus_por_node" {
  description = "OCPUs de cada node A1 (1 OCPU = 1 vCPU no Ampere)."
  type        = number
  default     = 1
  validation {
    condition     = var.nodes * var.ocpus_por_node <= 2
    error_message = "nodes x ocpus_por_node passa de 2: fora do Always Free."
  }
}

variable "memoria_por_node_gb" {
  description = "Memoria de cada node, em GB."
  type        = number
  default     = 6
  validation {
    condition     = var.nodes * var.memoria_por_node_gb <= 12
    error_message = "nodes x memoria_por_node_gb passa de 12 GB: fora do Always Free."
  }
}

variable "boot_volume_gb" {
  description = "Disco de boot de cada node. Minimo 47 GB."
  type        = number
  default     = 50
  validation {
    # 200 GB de block volume no Always Free. O Postgres gerenciado usa o
    # proprio storage e nao entra nesta conta.
    condition     = var.boot_volume_gb >= 47 && var.nodes * var.boot_volume_gb <= 200
    error_message = "Boot volumes passam de 200 GB: fora do Always Free."
  }
}

# ------------------------------------------------------------ Postgres gerenciado

variable "postgres_versao" {
  description = "Versao principal do Postgres (o servico oferece 14 a 17). 17 = a mesma do docker-compose."
  type        = string
  default     = "17"
}

variable "postgres_ocpus" {
  description = "OCPUs do Postgres. 1 e o minimo do shape E5.Flex."
  type        = number
  default     = 1
}

variable "postgres_memoria_gb" {
  description = "Memoria do Postgres. 16 GB e o minimo do shape E5.Flex."
  type        = number
  default     = 16
}

variable "chave_ssh_publica" {
  description = "Chave SSH publica para acessar os nodes (opcional; vazio = sem SSH)."
  type        = string
  default     = ""
}

variable "email_alerta_custo" {
  description = "E-mail que recebe alerta de gasto. Vazio = sem orcamento."
  type        = string
  default     = ""
}

variable "orcamento_mensal_usd" {
  description = "Orcamento mensal do compartimento. O alerta dispara em 50% e 100% do gasto real."
  type        = number
  default     = 50
}
