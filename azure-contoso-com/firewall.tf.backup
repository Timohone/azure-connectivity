# Contoso Hub Azure Firewall Configuration - KORRIGIERT
# =============================================================================

# Public IPs
resource "azurerm_public_ip" "firewall" {
  name                = "pip-nccont-hub-azfw-001"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_public_ip" "firewall_management" {
  name                = "pip-nccont-hub-azfw-mgmt-001"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

# Azure Firewall Policy
resource "azurerm_firewall_policy" "hub" {
  name                = "afwp-nccont-hub-001"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = "Premium"

  dns {
    servers       = [azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
    proxy_enabled = true
  }

  threat_intelligence_mode = "Alert"

  intrusion_detection {
    mode = "Alert"
  }

  depends_on = [
    azurerm_private_dns_resolver_inbound_endpoint.hub
  ]
}

# Azure Firewall
resource "azurerm_firewall" "hub" {
  name                = "afw-nccont-hub-001"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  zones               = ["1", "2", "3"]

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  management_ip_configuration {
    name                 = "management"
    subnet_id            = azurerm_subnet.firewall_management.id
    public_ip_address_id = azurerm_public_ip.firewall_management.id
  }
}

# CRITICAL DNS & CONNECTIVITY RULES - HÖCHSTE PRIORITÄT
resource "azurerm_firewall_policy_rule_collection_group" "critical_connectivity" {
  name               = "rcg-critical-connectivity"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 100

  # DNS-Regeln (HÖCHSTE PRIORITÄT)
  network_rule_collection {
    name     = "rc-dns-critical"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-dns-to-hub-resolver"
      protocols             = ["UDP", "TCP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = [azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
      destination_ports     = ["53"]
    }

    rule {
  name                  = "allow-dns-queries"
  protocols             = ["UDP", "TCP"]
  source_addresses      = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]  
  destination_addresses = ["10.0.35.0/24"]  
  destination_ports     = ["53"]
}

    rule {
      name                  = "allow-dns-from-hub-resolver"
      protocols             = ["UDP", "TCP"]
      source_addresses      = [azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
      destination_addresses = ["10.0.0.0/8"]
      destination_ports     = ["*"]
    }
  }

  # Hub-and-Spoke Connectivity (KRITISCH)
  network_rule_collection {
    name     = "rc-hub-spoke-critical"
    priority = 110
    action   = "Allow"

    # Hub zu allen Spokes
    rule {
      name                  = "allow-hub-to-spokes"
      protocols             = ["TCP", "UDP", "ICMP"]
      source_addresses      = ["10.0.0.0/16"]
      destination_addresses = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]
      destination_ports     = ["*"]
    }

    # Alle Spokes zu Hub
    rule {
      name                  = "allow-spokes-to-hub"
      protocols             = ["TCP", "UDP", "ICMP"]
      source_addresses      = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]
      destination_addresses = ["10.0.0.0/16"]
      destination_ports     = ["*"]
    }

    # Spoke-to-Spoke (durch Hub)
    rule {
      name                  = "allow-spoke-to-spoke"
      protocols             = ["TCP", "UDP", "ICMP"]
      source_addresses      = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]
      destination_addresses = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]
      destination_ports     = ["*"]
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }

  depends_on = [
    azurerm_firewall.hub,
    azurerm_private_dns_resolver_inbound_endpoint.hub
  ]
}

# Onprem Connectivity
resource "azurerm_firewall_policy_rule_collection_group" "onprem_connectivity" {
  name               = "rcg-onprem-connectivity"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 150

  network_rule_collection {
    name     = "rc-onprem-communication"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-to-onprem"
      protocols             = ["TCP", "UDP", "ICMP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["10.64.0.0/16"]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "allow-from-onprem"
      protocols             = ["TCP", "UDP", "ICMP"]
      source_addresses      = ["10.64.0.0/16"]
      destination_addresses = ["10.0.0.0/8"]
      destination_ports     = ["*"]
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }

  depends_on = [
    azurerm_firewall_policy_rule_collection_group.critical_connectivity
  ]
}

# Application Rules (Internet Access)
resource "azurerm_firewall_policy_rule_collection_group" "application_rules" {
  name               = "rcg-application-rules"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 200

  application_rule_collection {
    name     = "rc-internet-access"
    priority = 100
    action   = "Allow"

    rule {
      name = "allow-internet-essential"
      protocols {
        type = "Https"
        port = 443
      }
      protocols {
        type = "Http"
        port = 80
      }
      source_addresses  = ["10.0.0.0/8"]
      destination_fqdns = ["*microsoft.com", "*azure.com", "*ubuntu.com", "*security.ubuntu.com", "*canonical.com"]
    }

    rule {
      name = "allow-dns-external"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = ["10.0.0.0/8"]
      destination_fqdns = ["*.google.com", "*.cloudflare.com", "*.quad9.net"]
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }

  depends_on = [
    azurerm_firewall_policy_rule_collection_group.onprem_connectivity
  ]
}