terraform {
  required_version = ">= 1.12.0"

  required_providers {
    opnsense = {
      source  = "biptec/opnsense"
      version = "~> 0.29.2"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.0"
    }
  }
}

provider "opnsense" {}
