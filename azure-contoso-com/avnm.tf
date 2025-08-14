# Contoso AVNM Configuration - KORRIGIERT FÜR DNS & CONNECTIVITY
# =============================================================================

data "azurerm_management_group" "hybrid_management_group" {
  name = "mgm-nccont-landingzones-hybrid"
}

data "azurerm_management_group" "root_management_group" {
  name = "mgm-nccont-root"
}

data "azurerm_management_group" "connectivity_management_group" {
  name = "mgm-nccont-foundation-connectivity"
}

module "avnm" {
  source  = "app.terraform.io/Netcloud/ncf-avnm-module/azurerm"
  version = "1.1.0"

  # Basic configuration
  avnm_name           = "avnm-nccont"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location

  # Scope
  management_group_ids = [data.azurerm_management_group.hybrid_management_group.id, data.azurerm_management_group.connectivity_management_group.id]
  scope_accesses       = ["Connectivity", "SecurityAdmin", "Routing"]

  # =============================================================================
  # NETWORK GROUPS - KORRIGIERT
  # =============================================================================

  network_groups = {
    # Spoke Prod
    "spoke-prod" = {
      description        = "Spoke prod"
      connectivity_type  = "HubAndSpoke"
      group_connectivity = "DirectlyConnected"

      subscription_tags = {
        usecase1    = "spoke1"
        environment = "production"
      }
    }

    # Spoke Non-Prod
    "spoke-nonprod" = {
      description        = "Spoke nonprod"
      connectivity_type  = "HubAndSpoke"
      group_connectivity = "DirectlyConnected"

      subscription_tags = {
        usecase2    = "spoke"
        environment = "nonproduction"
      }
    }

    # Mesh Group 1 Prod (für spezielle Anwendungen)
    "meshgroup1-prod" = {
      description        = "Mesh Group 1 prod"
      connectivity_type  = "Mesh"
      group_connectivity = "DirectlyConnected"

      subscription_tags = {
        usecase     = "meshgroup1"
        environment = "production"
      }
    }
  }

  # =============================================================================
  # HUB AND SPOKE CONFIGURATION - KRITISCH FÜR CONNECTIVITY
  # =============================================================================

  hub_and_spoke_config = {
    name              = "hub-spoke"
    description       = "hub and spoke connectivity - CRITICAL FOR DNS"
    hub_resource_id   = azurerm_virtual_network.hub.id
    hub_resource_type = "Microsoft.Network/virtualNetworks"

    applies_to_groups = [
      {
        group_name         = "spoke-prod"
        group_connectivity = "DirectlyConnected"
        use_hub_gateway    = true
      },
      {
        group_name         = "spoke-nonprod"
        group_connectivity = "DirectlyConnected"
        use_hub_gateway    = true
      },
    ]
  }

  # =============================================================================
  # ROUTING CONFIGURATION - SIMPLIFIED FOR DNS DEBUGGING
  # =============================================================================

  routing_configurations = {
  "spoke-routing" = {
    description = "Spoke routing configuration for DNS resolution"

    rule_collections = {
      # Production routing - DNS FOCUSED
      "spoke-prod-routing" = {
        description                   = "Production routing with DNS priority"
        applies_to_groups             = ["spoke-prod"]
        disable_bgp_route_propagation = false

        rules = {
          # Internet via Firewall
          "internet-via-firewall" = {
            description         = "Internet traffic via firewall"
            destination_address = "0.0.0.0/0"
            next_hop_type       = "VirtualAppliance"
            next_hop_address    = azurerm_firewall.hub.ip_configuration[0].private_ip_address
          }

          # Other spoke networks via firewall
          "spoke-networks-via-firewall" = {
            description         = "Other spoke networks via firewall"
            destination_address = "10.1.128.0/17"  # NonProd range
            next_hop_type       = "VirtualAppliance"
            next_hop_address    = azurerm_firewall.hub.ip_configuration[0].private_ip_address
          }
        }
      }

      # Non-production routing - DNS FOCUSED
      "spoke-nonprod-routing" = {
        description                   = "Non-production routing with DNS priority"
        applies_to_groups             = ["spoke-nonprod"]
        disable_bgp_route_propagation = false

        rules = {
          # Internet via Firewall
          "internet-via-firewall" = {
            description         = "Internet traffic via firewall"
            destination_address = "0.0.0.0/0"
            next_hop_type       = "VirtualAppliance"
            next_hop_address    = azurerm_firewall.hub.ip_configuration[0].private_ip_address
          }

          # Other spoke networks via firewall
          "spoke-networks-via-firewall" = {
            description         = "Other spoke networks via firewall"
            destination_address = "10.1.0.0/17"    # Prod range
            next_hop_type       = "VirtualAppliance"
            next_hop_address    = azurerm_firewall.hub.ip_configuration[0].private_ip_address
          }
        }
      }
    }
  }
}
  # =============================================================================
  # SECURITY CONFIGURATION - SIMPLIFIED
  # =============================================================================

  security_admin_configs = {
    "spoke-security" = {
      description                                   = "Simplified spoke security for DNS debugging"
      apply_on_network_intent_policy_based_services = ["None"]

      rule_collections = {
        # Minimal security - DNS PRIORITY
        "essential-connectivity" = {
          network_groups = ["spoke-prod", "spoke-nonprod"]
          description    = "Essential connectivity for DNS and management"

          rules = {
            # ALLOW DNS - HIGHEST PRIORITY
            "allow-dns-traffic" = {
              action                  = "AlwaysAllow"
              direction               = "Inbound"
              priority                = 50
              protocol                = "Any"
              source_port_ranges      = ["0-65535"]
              destination_port_ranges = ["53"]
              sources = [
                { type = "IPPrefix", address = "10.0.0.0/8" },
              ]
              destinations = [
                { type = "IPPrefix", address = "10.0.35.0/24" }  # DNS subnet
              ]
              description = "Allow DNS traffic to hub resolver"
            }

            # ALLOW Management
            "allow-management-access" = {
              action                  = "Allow"
              direction               = "Inbound"
              priority                = 100
              protocol                = "Tcp"
              source_port_ranges      = ["0-65535"]
              destination_port_ranges = ["22", "3389", "443"]
              sources = [
                { type = "IPPrefix", address = "10.0.37.0/24" },  # Management subnet
              ]
              destinations = [
                { type = "ServiceTag", address = "VirtualNetwork" }
              ]
              description = "Allow management access"
            }

            # ALLOW Inter-spoke communication
            "allow-inter-spoke" = {
              action                  = "Allow"
              direction               = "Inbound"
              priority                = 200
              protocol                = "Any"
              source_port_ranges      = ["0-65535"]
              destination_port_ranges = ["0-65535"]
              sources = [
                { type = "IPPrefix", address = "10.1.0.0/16" },
                { type = "IPPrefix", address = "10.2.0.0/16" },
                { type = "IPPrefix", address = "10.3.0.0/16" }
              ]
              destinations = [
                { type = "ServiceTag", address = "VirtualNetwork" }
              ]
              description = "Allow inter-spoke communication"
            }
          }
        }
      }
    }
  }

  # =============================================================================
  # POLICY CONFIGURATION
  # =============================================================================

  create_policies                = true
  policy_management_group_id     = data.azurerm_management_group.root_management_group.id
  create_policy_initiative       = true
  policy_initiative_name         = "avnm-usecase-based"
  policy_initiative_display_name = "AVNM Network Groups - Use Case Based"

  # Policy assignment
  assign_policies = true
  policy_assignment = {
    name                = "avnm-usecase"
    display_name        = "AVNM Use Case Based Assignment"
    management_group_id = data.azurerm_management_group.root_management_group.id
    effect              = "addToNetworkGroup"
    not_scopes          = []
  }

  # Deployment - CRITICAL FOR CONNECTIVITY
  deployment_config = {
    deploy_connectivity = true
    deploy_routing      = true
    deploy_security     = true
  }

  # CORRECTED DEPENDENCIES
  depends_on = [
    azurerm_firewall.hub,
    azurerm_private_dns_resolver_inbound_endpoint.hub,
    azurerm_virtual_network.hub,
    azurerm_virtual_network.vnet_app1_prod,
    azurerm_virtual_network.vnet_app1_nonprod,
    azurerm_virtual_network.vnet_hrportal_prod,
    azurerm_virtual_network.vnet_hrportal_nonprod,
    azurerm_virtual_network.vnet_ncae
  ]
}