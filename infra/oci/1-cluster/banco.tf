# Postgres gerenciado (OCI Database with PostgreSQL), fora do cluster: backup
# automatico, patches e failover de volume ficam com a Oracle. Nao faz parte
# do Always Free -- o menor tamanho (1 OCPU AMD E5 + 16 GB) custa ~US$ 0,16/h:
# US$ 0,062 de compute + US$ 0,098 de taxa do servico. Pago com os creditos.

# Maiusculas, minusculas, digitos e especiais, para passar em qualquer
# politica de senha; so '-' e '_' como especiais, que nao precisam de escape
# na URL de conexao.
resource "random_password" "postgres" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "-_"
}

resource "oci_psql_db_system" "achou" {
  compartment_id = local.compartimento
  display_name   = "${var.nome}-postgres"
  db_version     = var.postgres_versao
  shape          = "PostgreSQL.VM.Standard.E5.Flex"

  instance_count              = 1
  instance_ocpu_count         = var.postgres_ocpus
  instance_memory_size_in_gbs = var.postgres_memoria_gb

  # O admin do servico nao e superusuario (recebe o oci_admin_role), mas pode
  # criar as extensoes liberadas -- a unaccent da busca vem liberada.
  credentials {
    username = "achou"
    password_details {
      password_type = "PLAIN_TEXT"
      password      = random_password.postgres.result
    }
  }

  network_details {
    subnet_id = oci_core_subnet.banco.id
  }

  storage_details {
    # Volume no mesmo AD do node: mais barato que o regional e suficiente
    # para uma demo. Regional replicaria entre ADs.
    is_regionally_durable = false
    availability_domain   = local.ad
    system_type           = "OCI_OPTIMIZED_STORAGE"
  }

  # Criar um DB system leva de 15 a 30 minutos.
  timeouts {
    create = "60m"
  }
}

# Endpoint e certificado da CA privada da Oracle. O servico so aceita TLS;
# o certificado vai para o cluster (etapa 2) e o Prisma valida o servidor.
data "oci_psql_db_system_connection_detail" "achou" {
  db_system_id = oci_psql_db_system.achou.id
}
