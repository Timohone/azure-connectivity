terraform {
  backend "local" {
    # use_azuread_auth = true
  }
  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">=1.7.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=4.20.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">=2.2.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">=3.1.0"
    }
  }
  required_version = ">=1.4.2, < 2.0.0"
}
