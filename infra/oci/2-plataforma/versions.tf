# Etapa separada da 1-cluster de proposito: os providers helm e kubernetes
# precisam falar com um cluster que ja exista na hora do plan. Na mesma
# etapa, o primeiro apply nao teria cluster para consultar.
terraform {
  required_version = ">= 1.9"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "${path.module}/../1-cluster/terraform.tfstate"
  }
}

locals {
  cluster = data.terraform_remote_state.cluster.outputs

  # O OKE autentica o kubectl com um token gerado pela CLI da OCI a cada uso;
  # nao existe senha nem certificado de cliente fixo.
  token_oke = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args = [
      "ce", "cluster", "generate-token",
      "--cluster-id", local.cluster.cluster_id,
      "--region", local.cluster.regiao,
      "--profile", var.perfil_oci,
    ]
  }
}

provider "kubernetes" {
  host                   = local.cluster.kubernetes_host
  cluster_ca_certificate = local.cluster.kubernetes_ca

  exec {
    api_version = local.token_oke.api_version
    command     = local.token_oke.command
    args        = local.token_oke.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster.kubernetes_host
    cluster_ca_certificate = local.cluster.kubernetes_ca
    exec                   = local.token_oke
  }
}
