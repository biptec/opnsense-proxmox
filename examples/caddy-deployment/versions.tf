terraform {
  required_version = ">= 1.12.0"

  required_providers {
    opnsense = {
      source  = "biptec/opnsense"
      version = ">= 0.27.0"
    }
  }
}
