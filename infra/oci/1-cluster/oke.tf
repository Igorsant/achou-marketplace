data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_containerengine_cluster_option" "oke" {
  cluster_option_id = "all"
}

locals {
  # "v1.33.1" < "v1.34.0" em ordem de texto: vale enquanto as versoes
  # oferecidas tiverem o mesmo numero de digitos, o que e o caso do OKE.
  versao_k8s = var.versao_kubernetes != "" ? var.versao_kubernetes : reverse(sort(data.oci_containerengine_cluster_option.oke.kubernetes_versions))[0]
  ad         = data.oci_identity_availability_domains.ads.availability_domains[var.indice_ad].name
}

# BASIC_CLUSTER: control plane gratuito. O ENHANCED custa US$ 0,10/hora e
# traz add-ons gerenciados e SLA que uma apresentacao nao precisa.
resource "oci_containerengine_cluster" "achou" {
  compartment_id     = local.compartimento
  name               = "${var.nome}-oke"
  kubernetes_version = local.versao_k8s
  vcn_id             = oci_core_vcn.achou.id
  type               = "BASIC_CLUSTER"

  endpoint_config {
    subnet_id            = oci_core_subnet.api.id
    is_public_ip_enabled = true
  }

  # Flannel (overlay) em vez de CNI nativa da VCN: pod nao consome IP da
  # subnet, e o A1 de 1 OCPU aceita poucas VNICs.
  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.lb.id]

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }
}

data "oci_containerengine_node_pool_option" "oke" {
  node_pool_option_id = oci_containerengine_cluster.achou.id
  compartment_id      = local.compartimento
}

locals {
  # Imagem Oracle Linux ARM (aarch64) preparada para esta versao do OKE,
  # sem variante GPU. A lista ja vem da mais nova para a mais antiga.
  imagens_arm = [
    for s in data.oci_containerengine_node_pool_option.oke.sources : s.image_id
    if strcontains(s.source_name, "aarch64")
    && strcontains(s.source_name, "OKE-${trimprefix(local.versao_k8s, "v")}")
    && !strcontains(s.source_name, "GPU")
  ]
}

resource "oci_containerengine_node_pool" "a1" {
  compartment_id     = local.compartimento
  cluster_id         = oci_containerengine_cluster.achou.id
  name               = "${var.nome}-a1"
  kubernetes_version = local.versao_k8s

  # Ampere A1: a unica forma com CPU de verdade no Always Free.
  node_shape = "VM.Standard.A1.Flex"
  node_shape_config {
    ocpus         = var.ocpus_por_node
    memory_in_gbs = var.memoria_por_node_gb
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.imagens_arm[0]
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  node_config_details {
    size = var.nodes

    placement_configs {
      availability_domain = local.ad
      subnet_id           = oci_core_subnet.workers.id
    }

    node_pool_pod_network_option_details {
      cni_type = "FLANNEL_OVERLAY"
    }
  }

  ssh_public_key = var.chave_ssh_publica != "" ? var.chave_ssh_publica : null

  lifecycle {
    precondition {
      condition     = length(local.imagens_arm) > 0
      error_message = "Nenhuma imagem aarch64 do OKE para ${local.versao_k8s}. Fixe versao_kubernetes numa versao listada no console."
    }
  }
}

# Dados para o kubeconfig da etapa 2 (endpoint e certificado da CA).
data "oci_containerengine_cluster_kube_config" "achou" {
  cluster_id = oci_containerengine_cluster.achou.id
  # O padrao da API e LEGACY_KUBERNETES, endpoint que clusters com API na
  # VCN (todos os novos) nao tem. O publico e o que as security lists liberam.
  endpoint      = "PUBLIC_ENDPOINT"
  token_version = "2.0.0"
}
