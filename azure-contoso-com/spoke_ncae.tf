# NCAE Spoke - VEREINFACHT OHNE EIGENEN DNS RESOLVER
# =============================================================================

resource "azurerm_resource_group" "rg_ncae" {
  name     = "rg-nccont-ncae"
  location = "West Europe"
  provider = azurerm.ncae
}

resource "azurerm_virtual_network" "vnet_ncae" {
  name                = "vnet-nccont-ncae"
  address_space       = ["10.1.0.0/24"]
  location            = azurerm_resource_group.rg_ncae.location
  resource_group_name = azurerm_resource_group.rg_ncae.name
  provider            = azurerm.ncae
}

resource "azurerm_subnet" "snet_ncae" {
  name                 = "snet-ncae-default"
  resource_group_name  = azurerm_resource_group.rg_ncae.name
  virtual_network_name = azurerm_virtual_network.vnet_ncae.name
  address_prefixes     = ["10.1.0.0/25"]
  provider             = azurerm.ncae

  depends_on = [azurerm_virtual_network.vnet_ncae]
}

# =============================================================================
# PRIVATE DNS ZONES - SUBDOMAINS VON HUB ZONES
# =============================================================================

# Subdomain von Hub azure.contoso.com
resource "azurerm_private_dns_zone" "ncae_azure" {
  name                = "ncae.azure.contoso.com"
  resource_group_name = azurerm_resource_group.rg_ncae.name
  provider            = azurerm.ncae
}

# =============================================================================
# DNS ZONE LINKS - MIT AUTO REGISTRATION
# =============================================================================

resource "azurerm_private_dns_zone_virtual_network_link" "ncae_azure" {
  name                  = "link-ncae-azure-vnet"
  resource_group_name   = azurerm_resource_group.rg_ncae.name
  private_dns_zone_name = azurerm_private_dns_zone.ncae_azure.name
  virtual_network_id    = azurerm_virtual_network.vnet_ncae.id
  registration_enabled  = true
  provider              = azurerm.ncae
}

# =============================================================================
# VNET DNS KONFIGURATION - VERWENDET HUB DNS RESOLVER
# =============================================================================

resource "azurerm_virtual_network_dns_servers" "vnet_ncae" {
  virtual_network_id = azurerm_virtual_network.vnet_ncae.id
  dns_servers        = [data.azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
  provider           = azurerm.ncae
  
  depends_on = [azurerm_virtual_network.vnet_ncae]
}

# =============================================================================
# VIRTUAL MACHINES
# =============================================================================

resource "azurerm_network_interface" "nic_ncae" {
  name                = "nic-ncae-vm001"
  location            = azurerm_resource_group.rg_ncae.location
  resource_group_name = azurerm_resource_group.rg_ncae.name
  provider            = azurerm.ncae

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet_ncae.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm_ncae" {
  name                = "vm-ncae-001"
  resource_group_name = azurerm_resource_group.rg_ncae.name
  location            = azurerm_resource_group.rg_ncae.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  admin_password      = "P@ssw0rd123!"
  provider            = azurerm.ncae

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic_ncae.id]

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
    usecase     = "ncae"
    environment = "production"
  }

  lifecycle {
    ignore_changes = [boot_diagnostics]
  }
}