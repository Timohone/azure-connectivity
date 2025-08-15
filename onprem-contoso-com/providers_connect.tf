# Additional provider for connecting to Azure Contoso
provider "azurerm" {
  alias = "contoso"
  resource_provider_registrations = "extended"
  features {}
  subscription_id = "052c919b-fb40-41f1-af1e-5466cd0dba91"
}
