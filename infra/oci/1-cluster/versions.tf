terraform {
  required_version = ">= 1.9"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

# Autentica com a chave de API em ~/.oci/config (ver docs/deploy.md).
provider "oci" {
  region              = var.regiao
  config_file_profile = var.perfil_oci
}
