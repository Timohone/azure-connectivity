# App1 Production Spoke - VEREINFACHT OHNE EIGENEN DNS RESOLVER
# =============================================================================

resource "azurerm_resource_group" "rg_app1_prod" {
  name     = "rg-nccont-app1-prod"
  location = "West Europe"
  provider = azurerm.app1_prod
}

resource "azurerm_virtual_network" "vnet_app1_prod" {
  name                = "vnet-nccont-app1-prod"
  address_space       = ["10.1.3.0/24"]
  location            = azurerm_resource_group.rg_app1_prod.location
  resource_group_name = azurerm_resource_group.rg_app1_prod.name
  provider            = azurerm.app1_prod
}

resource "azurerm_subnet" "snet_app1_prod" {
  name                 = "snet-app1-prod-default"
  resource_group_name  = azurerm_resource_group.rg_app1_prod.name
  virtual_network_name = azurerm_virtual_network.vnet_app1_prod.name
  address_prefixes     = ["10.1.3.0/25"]
  provider             = azurerm.app1_prod

  depends_on = [azurerm_virtual_network.vnet_app1_prod]
}

# =============================================================================
# PRIVATE DNS ZONES - SUBDOMAINS VON HUB ZONES
# =============================================================================

# Subdomain von Hub azure.contoso.com
resource "azurerm_private_dns_zone" "app1_prod_azure" {
  name                = "app1.azure.contoso.com"
  resource_group_name = azurerm_resource_group.rg_app1_prod.name
  provider            = azurerm.app1_prod
}

# =============================================================================
# DNS ZONE LINKS - MIT AUTO REGISTRATION
# =============================================================================

resource "azurerm_private_dns_zone_virtual_network_link" "app1_prod_azure" {
  name                  = "link-app1-azure-vnet"
  resource_group_name   = azurerm_resource_group.rg_app1_prod.name
  private_dns_zone_name = azurerm_private_dns_zone.app1_prod_azure.name
  virtual_network_id    = azurerm_virtual_network.vnet_app1_prod.id
  registration_enabled  = true
  provider              = azurerm.app1_prod
}

# =============================================================================
# VNET DNS KONFIGURATION - VERWENDET HUB DNS RESOLVER
# =============================================================================

resource "azurerm_virtual_network_dns_servers" "vnet_app1_prod" {
  virtual_network_id = azurerm_virtual_network.vnet_app1_prod.id
  dns_servers        = [data.azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
  provider           = azurerm.app1_prod
  
  depends_on = [azurerm_virtual_network.vnet_app1_prod]
}

# =============================================================================
# VIRTUAL MACHINES
# =============================================================================

resource "azurerm_network_interface" "nic_app1_prod" {
  name                = "nic-app1-prod-vm001"
  location            = azurerm_resource_group.rg_app1_prod.location
  resource_group_name = azurerm_resource_group.rg_app1_prod.name
  provider            = azurerm.app1_prod

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet_app1_prod.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "nic2_app1_prod" {
  name                = "nic-app1-prod-vm002"
  location            = azurerm_resource_group.rg_app1_prod.location
  resource_group_name = azurerm_resource_group.rg_app1_prod.name
  provider            = azurerm.app1_prod

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet_app1_prod.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm_app1_prod" {
  name                = "vm-app1-prod-001"
  resource_group_name = azurerm_resource_group.rg_app1_prod.name
  location            = azurerm_resource_group.rg_app1_prod.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  admin_password      = "P@ssw0rd123!"
  provider            = azurerm.app1_prod

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic_app1_prod.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    usecase     = "app1"
    environment = "production"
  }

  lifecycle {
    ignore_changes = [boot_diagnostics]
  }
}

resource "azurerm_linux_virtual_machine" "vm2_app1_prod" {
  name                = "vm-app1-prod-002"
  resource_group_name = azurerm_resource_group.rg_app1_prod.name
  location            = azurerm_resource_group.rg_app1_prod.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  admin_password      = "P@ssw0rd123!"
  provider            = azurerm.app1_prod

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic2_app1_prod.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    usecase     = "app1"
    environment = "production"
  }

  lifecycle {
    ignore_changes = [boot_diagnostics]
  }
}