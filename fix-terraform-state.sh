#!/bin/bash

# Terraform State Fix Script
# This script fixes provider configuration issues in the Terraform state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$SCRIPT_DIR/onprem-contoso-com"
AZURE_DIR="$SCRIPT_DIR/azure-contoso-com"

fix_onprem_state() {
    log "Fixing OnPrem Terraform state..."
    
    cd "$ONPREM_DIR"
    
    # Check if state file exists
    if [[ ! -f "terraform.tfstate" ]]; then
        log "No state file found in OnPrem directory, skipping state fix"
        return 0
    fi
    
    # Create backup of state file
    log "Creating backup of terraform.tfstate..."
    cp terraform.tfstate terraform.tfstate.backup
    
    # Check what's in the state
    log "Checking current state..."
    terraform state list 2>/dev/null || true
    
    # Remove problematic data sources from state if they exist
    local problematic_resources=(
        "data.azurerm_private_dns_resolver.contoso"
        "data.azurerm_private_dns_resolver_inbound_endpoint.contoso"
    )
    
    for resource in "${problematic_resources[@]}"; do
        if terraform state show "$resource" &>/dev/null; then
            log "Removing $resource from state..."
            terraform state rm "$resource" || true
        fi
    done
    
    success "OnPrem state fixed"
    cd "$SCRIPT_DIR"
}

fix_azure_state() {
    log "Fixing Azure Terraform state..."
    
    cd "$AZURE_DIR"
    
    # Check if state file exists
    if [[ ! -f "terraform.tfstate" ]]; then
        log "No state file found in Azure directory, skipping state fix"
        return 0
    fi
    
    # Create backup of state file
    log "Creating backup of terraform.tfstate..."
    cp terraform.tfstate terraform.tfstate.backup
    
    # Check what's in the state
    log "Checking current state..."
    terraform state list 2>/dev/null || true
    
    # Remove problematic data sources from state if they exist
    local problematic_resources=(
        "data.azurerm_private_dns_resolver.onprem"
        "data.azurerm_private_dns_resolver_inbound_endpoint.onprem"
    )
    
    for resource in "${problematic_resources[@]}"; do
        if terraform state show "$resource" &>/dev/null; then
            log "Removing $resource from state..."
            terraform state rm "$resource" || true
        fi
    done
    
    success "Azure state fixed"
    cd "$SCRIPT_DIR"
}

clean_connection_files() {
    log "Cleaning up connection files that might cause issues..."
    
    # Remove connection files if they exist
    rm -f "$ONPREM_DIR/dns_connect_azure.tf"
    rm -f "$ONPREM_DIR/providers_connect.tf"
    rm -f "$AZURE_DIR/dns_connect_onprem.tf"
    
    success "Connection files cleaned up"
}

restore_working_configs() {
    log "Restoring working configurations..."
    
    # Restore OnPrem DNS configuration without cross-references
    cat > "$ONPREM_DIR/dns.tf" << 'EOF'
# Onprem Hub DNS Configuration - FIXED FOR DEPLOYMENT ORDER
# =============================================================================

# DNS Resolver for Onprem Hub
resource "azurerm_private_dns_resolver" "hub" {
  name                = "dnspr-onprem-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  virtual_network_id  = azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "dnspr-onprem-hub-inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id = azurerm_subnet.dns_inbound.id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  name                    = "dnspr-onprem-hub-outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location
  subnet_id               = azurerm_subnet.dns_outbound.id
}

# DNS Forwarding Ruleset (will be updated after Azure deployment)
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  name                                       = "dnspr-onprem-hub-ruleset"
  resource_group_name                        = azurerm_resource_group.hub.name
  location                                   = azurerm_resource_group.hub.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub.id]
}

# VNet Link for Hub
resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  name                      = "link-onprem-hub-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.hub.id
}

# Set DNS servers for Hub VNet
resource "azurerm_virtual_network_dns_servers" "hub" {
  virtual_network_id = azurerm_virtual_network.hub.id
  dns_servers        = [azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
}

# Private DNS Zone for onprem
resource "azurerm_private_dns_zone" "onprem_contoso" {
  name                = "onprem.contoso.com"
  resource_group_name = azurerm_resource_group.hub.name
}

# Private DNS Zone Link
resource "azurerm_private_dns_zone_virtual_network_link" "onprem_contoso_hub" {
  name                  = "link-onprem-contoso-hub"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.onprem_contoso.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = true
}
EOF

    # Restore OnPrem providers configuration
    cat > "$ONPREM_DIR/providers.tf" << 'EOF'
provider "azurerm" {
  resource_provider_registrations = "extended"
  features {}
  subscription_id = "b6fd9976-a434-4a5c-858e-0761724b5dd9"
}

provider "azuread" {
}

provider "azuredevops" {
}
EOF

    # Fix Azure DNS configuration to remove onprem references
    cat > "$AZURE_DIR/dns.tf" << 'EOF'
# Contoso Hub DNS Configuration - FIXED FOR DEPLOYMENT ORDER
# =============================================================================

# DNS PRIVATE RESOLVER - ONLY FOR HUB
resource "azurerm_private_dns_resolver" "hub" {
  name                = "dnspr-nccont-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  virtual_network_id  = azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "dnspr-nccont-hub-inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id = azurerm_subnet.dns_inbound.id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  name                    = "dnspr-nccont-hub-outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location
  subnet_id               = azurerm_subnet.dns_outbound.id
}

# DNS FORWARDING RULESET (will be updated after onprem deployment)
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  name                                       = "dnspr-nccont-hub-ruleset"
  resource_group_name                        = azurerm_resource_group.hub.name
  location                                   = azurerm_resource_group.hub.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub.id]
}

# VNet Links for Hub AND all Spokes (for Forwarding Rules)
resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  name                      = "link-hub-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.hub.id
}

# Links to all Spoke VNets for Forwarding Rules
resource "azurerm_private_dns_resolver_virtual_network_link" "app1_prod" {
  name                      = "link-app1-prod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_app1_prod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "app1_nonprod" {
  name                      = "link-app1-nonprod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_app1_nonprod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hrportal_prod" {
  name                      = "link-hrportal-prod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_hrportal_prod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hrportal_nonprod" {
  name                      = "link-hrportal-nonprod-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_hrportal_nonprod.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "ncae" {
  name                      = "link-ncae-ruleset"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  virtual_network_id        = azurerm_virtual_network.vnet_ncae.id
}

# HUB DNS ZONES - ONLY AZURE.CONTOSO.COM
resource "azurerm_private_dns_zone" "azure_contoso" {
  name                = "azure.contoso.com"
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "azure_contoso_hub" {
  name                  = "link-azure-contoso-hub"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.azure_contoso.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = true
}

# PRIVATE LINK ZONES - ONLY IN HUB
locals {
  private_link_zones = [
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.database.windows.net",
    "privatelink.vaultcore.azure.net"
  ]
}

resource "azurerm_private_dns_zone" "private_endpoints" {
  for_each = toset(local.private_link_zones)

  name                = each.value
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "private_endpoints_hub" {
  for_each = azurerm_private_dns_zone.private_endpoints

  name                  = "link-${replace(each.key, ".", "-")}-hub"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
}

# HUB VNET DNS CONFIGURATION
resource "azurerm_virtual_network_dns_servers" "hub" {
  virtual_network_id = azurerm_virtual_network.hub.id
  dns_servers        = [azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address]
  
  depends_on = [azurerm_private_dns_resolver_inbound_endpoint.hub]
}

# OUTPUT FOR SPOKE VNETs
output "hub_dns_resolver_ip" {
  description = "IP of Hub DNS Resolver for Spokes"
  value       = azurerm_private_dns_resolver_inbound_endpoint.hub.ip_configurations[0].private_ip_address
}
EOF

    # Remove the problematic data.tf file from Azure directory
    rm -f "$AZURE_DIR/data.tf"

    success "Working configurations restored"
}

reinitialize_terraform() {
    log "Reinitializing Terraform in both directories..."
    
    # Reinitialize OnPrem
    log "Reinitializing OnPrem Terraform..."
    cd "$ONPREM_DIR"
    terraform init -reconfigure
    
    # Reinitialize Azure
    log "Reinitializing Azure Terraform..."
    cd "$AZURE_DIR"
    terraform init -reconfigure
    
    success "Terraform reinitialized"
    cd "$SCRIPT_DIR"
}

validate_fix() {
    log "Validating the fix..."
    
    # Test OnPrem plan
    cd "$ONPREM_DIR"
    if terraform plan -out=test.tfplan &>/dev/null; then
        success "✓ OnPrem configuration is valid"
        rm -f test.tfplan
    else
        error "✗ OnPrem configuration has issues"
    fi
    
    # Test Azure plan
    cd "$AZURE_DIR"
    if terraform plan -out=test.tfplan &>/dev/null; then
        success "✓ Azure configuration is valid"
        rm -f test.tfplan
    else
        error "✗ Azure configuration has issues"
    fi
    
    cd "$SCRIPT_DIR"
}

# Main function
main() {
    log "Starting Terraform state fix..."
    
    # Check prerequisites
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed"
        exit 1
    fi
    
    # Apply fixes in order
    clean_connection_files
    fix_onprem_state
    fix_azure_state
    restore_working_configs
    reinitialize_terraform
    validate_fix
    
    success "Terraform state fix completed!"
    
    echo ""
    echo "🎯 Next Steps:"
    echo "1. Run the deployment script: ./deploy_infrastructure.sh deploy"
    echo "2. Or deploy manually:"
    echo "   - First: cd onprem-contoso-com && terraform apply"
    echo "   - Then:  cd azure-contoso-com && terraform apply"
    echo "   - Finally: Add DNS connections between environments"
    echo ""
}

# Run main function
main "$@"