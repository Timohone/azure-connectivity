provider "azurerm" {
  resource_provider_registrations = "extended"
  features {}
  subscription_id = "b6fd9976-a434-4a5c-858e-0761724b5dd9"
}


provider "azurerm" {
  alias = "contoso"
  resource_provider_registrations = "extended"
  features {}
  subscription_id = "052c919b-fb40-41f1-af1e-5466cd0dba91"
}


provider "azuread" {
}

provider "azuredevops" {
}
