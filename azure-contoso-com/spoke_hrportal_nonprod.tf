# HRPortal Non-Production Spoke - VEREINFACHT OHNE EIGENEN DNS RESOLVER
# =============================================================================

resource "azurerm_resource_group" "rg_hrportal_nonprod" {
  name     = "rg-nccont-hrportal-nonprod"
  location = "West Europe"
  provider = azurerm.hrportal_nonprod
}

resource "azurerm_virtual_network" "vnet_hrportal_nonprod" {
  name                = "vnet-nccont-hrportal-nonprod"
  address_space       = ["10.1.129.0/24"]
  location            = azurerm_resource_group.rg_hrportal_nonprod.location
  resource_group_name = azurerm_resource_group.rg_hrportal_nonprod.name
  provider            = azurerm.hrportal_nonprod
}

resource "azurerm_subnet" "snet_hrportal_nonprod" {
  name                 = "snet-hrportal-nonprod-default"
  resource_group_name  = azurerm_resource_group.rg_hrportal_nonprod.name
  virtual_network_name = azurerm_virtual_network.vnet_hrportal_nonprod.name
  address_prefixes     = ["10.1.129.0/25"]
  provider             = azurerm.hrportal_nonprod

  depends_on = [azurerm_virtual_network.vnet_hrportal_nonprod]
}

# =============================================================================
# PRIVATE DNS ZONES - SUBDOMAINS VON HUB ZONES
# =============================================================================

# Subdomain von Hub azure.contoso.com
resource "azurerm_private_dns_zone" "hrportal_nonprod_azure" {
  name                = "hrportal.azure.contoso.com"
  resource_group_name = azurerm_resource_group.rg_hrportal_nonprod.name
  provider            = azurerm.hrportal_nonprod
}

# =============================================================================
# DNS ZONE LINKS - MIT AUTO REGISTRATION
# =============================================================================

resource "azurerm_private_dns_zone_virtual_network_link" "hrportal_nonprod_azure" {
  name                  = "link-hrportal-azure-vnet"
  resource_group_name   = azurerm_resource_group.rg_hrportal_nonprod.name
  private_dns_zone_name = azurerm_private_dns_zone.hrportal_nonprod_azure.name
  virtual_network_id    = azurerm_virtual_network.vnet_hrportal_nonprod.id
  registration_enabled  = true
  provider              = azurerm.hrportal_nonprod
}

# =============================================================================
# VNET DNS KONFIGURATION - VERWENDET HUB DNS RESOLVER
# =============================================================================

resource "azurerm_virtual_network_dns_servers" "vnet_hrportal_nonprod" {
  virtual_network_id = azurerm_virtual_network.vnet_hrportal_nonprod.id
  dns_servers        = [data.azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
  provider           = azurerm.hrportal_nonprod
  
  depends_on = [azurerm_virtual_network.vnet_hrportal_nonprod]
}

# =============================================================================
# VIRTUAL MACHINES
# =============================================================================

resource "azurerm_network_interface" "nic_hrportal_nonprod" {
  name                = "nic-hrportal-nonprod-vm001"
  location            = azurerm_resource_group.rg_hrportal_nonprod.location
  resource_group_name = azurerm_resource_group.rg_hrportal_nonprod.name
  provider            = azurerm.hrportal_nonprod

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet_hrportal_nonprod.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm_hrportal_nonprod" {
  name                = "vm-hrportal-nonprod-001"
  resource_group_name = azurerm_resource_group.rg_hrportal_nonprod.name
  location            = azurerm_resource_group.rg_hrportal_nonprod.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  admin_password      = "P@ssw0rd123!"
  provider            = azurerm.hrportal_nonprod

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic_hrportal_nonprod.id]

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
    usecase     = "hrportal"
    environment = "nonproduction"
  }

  lifecycle {
    ignore_changes = [boot_diagnostics]
  }
}