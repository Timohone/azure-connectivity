# Fabrikam Hub Infrastructure
# =============================================================================

# Network Interface for Hub VM
resource "azurerm_network_interface" "hub_vm" {
  name                = "nic-ncfab-hub-vm001"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.management.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Hub Virtual Machine
resource "azurerm_linux_virtual_machine" "hub_vm" {
  name                = "vm-ncfab-hub-001"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  
  disable_password_authentication = false
  admin_password                 = "P@ssw0rd123!" 

  network_interface_ids = [
    azurerm_network_interface.hub_vm.id,
  ]

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
    usecase      = "hub"
    environment  = "production"
    organization = "fabricam"
  }

  lifecycle {
    ignore_changes = [ boot_diagnostics ]
  }
}