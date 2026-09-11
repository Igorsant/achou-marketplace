# Compartimento proprio: tudo do projeto num lugar so, e o orcamento mira
# exatamente estes recursos.
resource "oci_identity_compartment" "achou" {
  compartment_id = var.tenancy_ocid
  name           = var.nome
  description    = "Achou! Marketplace - apresentacao"
  enable_delete  = true
}

locals {
  compartimento = oci_identity_compartment.achou.id

  cidr_vcn     = "10.0.0.0/16"
  cidr_api     = "10.0.0.0/28"
  cidr_workers = "10.0.1.0/24"
  cidr_lb      = "10.0.2.0/24"
  cidr_banco   = "10.0.3.0/24"

  # Protocolos na API da OCI: numeros IANA em string.
  tcp  = "6"
  icmp = "1"
  todo = "all"
}

resource "oci_core_vcn" "achou" {
  compartment_id = local.compartimento
  display_name   = "${var.nome}-vcn"
  cidr_blocks    = [local.cidr_vcn]
  dns_label      = var.nome
}

# Tudo sai pelo Internet Gateway. O desenho de referencia da Oracle poe os
# workers em subnet privada com NAT e Service Gateway, mas a disponibilidade
# desses gateways em conta free tier e incerta; subnet publica funciona em
# qualquer conta, e as security lists abaixo fecham o que importa.
resource "oci_core_internet_gateway" "achou" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.achou.id
  display_name   = "${var.nome}-igw"
}

resource "oci_core_route_table" "publica" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.achou.id
  display_name   = "${var.nome}-rotas"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.achou.id
  }
}

# ------------------------------------------------------------ security lists
# Regras do exemplo "Flannel CNI, endpoint publico" da documentacao do OKE,
# adaptadas para workers publicos. Faltar uma delas e o sintoma classico e o
# node nunca ficar Ready.

resource "oci_core_security_list" "api" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.achou.id
  display_name   = "${var.nome}-sl-api"

  dynamic "ingress_security_rules" {
    for_each = var.ips_admin
    content {
      description = "kubectl e Terraform -> API do Kubernetes"
      protocol    = local.tcp
      source      = ingress_security_rules.value
      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }
  ingress_security_rules {
    description = "workers -> API do Kubernetes"
    protocol    = local.tcp
    source      = local.cidr_workers
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  ingress_security_rules {
    description = "workers -> control plane"
    protocol    = local.tcp
    source      = local.cidr_workers
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  ingress_security_rules {
    description = "path MTU discovery"
    protocol    = local.icmp
    source      = local.cidr_workers
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    description = "control plane -> workers"
    protocol    = local.tcp
    destination = local.cidr_workers
  }
  egress_security_rules {
    description = "path MTU discovery"
    protocol    = local.icmp
    destination = local.cidr_workers
    icmp_options {
      type = 3
      code = 4
    }
  }
  egress_security_rules {
    # No desenho da Oracle isto vai pelo Service Gateway; aqui, pela internet.
    description = "control plane -> servicos da OCI (OKE)"
    protocol    = local.tcp
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "workers" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.achou.id
  display_name   = "${var.nome}-sl-workers"

  ingress_security_rules {
    description = "pod <-> pod entre nodes (VXLAN do Flannel)"
    protocol    = local.todo
    source      = local.cidr_workers
  }
  ingress_security_rules {
    description = "control plane -> workers"
    protocol    = local.tcp
    source      = local.cidr_api
  }
  ingress_security_rules {
    description = "path MTU discovery"
    protocol    = local.icmp
    source      = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }
  ingress_security_rules {
    description = "load balancer -> NodePorts (inclui health check)"
    protocol    = local.tcp
    source      = local.cidr_lb
    tcp_options {
      min = 30000
      max = 32767
    }
  }
  ingress_security_rules {
    description = "load balancer -> kube-proxy"
    protocol    = local.tcp
    source      = local.cidr_lb
    tcp_options {
      min = 10256
      max = 10256
    }
  }
  ingress_security_rules {
    # O NLB preserva o IP do cliente (e o que faz o rate limit valer por
    # usuario), entao o pacote chega no node com o IP de quem acessou.
    # Por isso a porta do Traefik precisa aceitar a internet.
    description = "clientes -> NodePort HTTP do Traefik (via NLB)"
    protocol    = local.tcp
    source      = "0.0.0.0/0"
    tcp_options {
      min = 30080
      max = 30080
    }
  }
  dynamic "ingress_security_rules" {
    for_each = var.chave_ssh_publica == "" ? [] : var.ips_admin
    content {
      description = "SSH nos nodes"
      protocol    = local.tcp
      source      = ingress_security_rules.value
      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  egress_security_rules {
    description = "saida para a internet: imagens, OCIR, OKE"
    protocol    = local.todo
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "lb" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.achou.id
  display_name   = "${var.nome}-sl-lb"

  ingress_security_rules {
    description = "HTTP publico"
    protocol    = local.tcp
    source      = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  egress_security_rules {
    description = "load balancer -> NodePorts"
    protocol    = local.tcp
    destination = local.cidr_workers
    tcp_options {
      min = 30000
      max = 32767
    }
  }
  egress_security_rules {
    description = "load balancer -> kube-proxy"
    protocol    = local.tcp
    destination = local.cidr_workers
    tcp_options {
      min = 10256
      max = 10256
    }
  }
}

# O Postgres so conversa com os workers. Com o Flannel, o trafego que sai de
# um pod para a VCN leva o IP do node, entao a origem e a subnet dos workers.
resource "oci_core_security_list" "banco" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.achou.id
  display_name   = "${var.nome}-sl-banco"

  ingress_security_rules {
    description = "workers (pods) -> Postgres"
    protocol    = local.tcp
    source      = local.cidr_workers
    tcp_options {
      min = 5432
      max = 5432
    }
  }
}

# ------------------------------------------------------------ subnets

resource "oci_core_subnet" "api" {
  compartment_id    = local.compartimento
  vcn_id            = oci_core_vcn.achou.id
  display_name      = "${var.nome}-api"
  cidr_block        = local.cidr_api
  dns_label         = "api"
  route_table_id    = oci_core_route_table.publica.id
  security_list_ids = [oci_core_security_list.api.id]
}

resource "oci_core_subnet" "workers" {
  compartment_id    = local.compartimento
  vcn_id            = oci_core_vcn.achou.id
  display_name      = "${var.nome}-workers"
  cidr_block        = local.cidr_workers
  dns_label         = "workers"
  route_table_id    = oci_core_route_table.publica.id
  security_list_ids = [oci_core_security_list.workers.id]
}

resource "oci_core_subnet" "lb" {
  compartment_id    = local.compartimento
  vcn_id            = oci_core_vcn.achou.id
  display_name      = "${var.nome}-lb"
  cidr_block        = local.cidr_lb
  dns_label         = "lb"
  route_table_id    = oci_core_route_table.publica.id
  security_list_ids = [oci_core_security_list.lb.id]
}

# Privada: sem IP publico e sem rota para a internet. O banco so e
# alcancavel de dentro da VCN.
resource "oci_core_subnet" "banco" {
  compartment_id             = local.compartimento
  vcn_id                     = oci_core_vcn.achou.id
  display_name               = "${var.nome}-banco"
  cidr_block                 = local.cidr_banco
  dns_label                  = "banco"
  prohibit_public_ip_on_vnic = true
  security_list_ids          = [oci_core_security_list.banco.id]
}
