terraform {
  required_version = ">= 1.5.0"

  backend "local" {}

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11.0"
    }
  }
}
