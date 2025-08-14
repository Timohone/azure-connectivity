#!/bin/bash

# Infrastructure Deployment Script
# This script deploys the complete Contoso infrastructure in the correct order
# to avoid circular dependencies and ensure proper DNS resolution

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    log "Found Terraform version: $TERRAFORM_VERSION"
    
    # Check if Azure CLI is installed and logged in
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if directories exist
    if [[ ! -d "$ONPREM_DIR" ]]; then
        error "OnPrem directory not found: $ONPREM_DIR"
        exit 1
    fi
    
    if [[ ! -d "$AZURE_DIR" ]]; then
        error "Azure directory not found: $AZURE_DIR"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Apply fixes to configuration files
apply_fixes() {
    log "Applying configuration fixes..."
    
    # Run the state fix script first if it exists
    if [[ -f "$SCRIPT_DIR/fix_terraform_state.sh" ]]; then
        log "Running state fix script first..."
        bash "$SCRIPT_DIR/fix_terraform_state.sh"
    fi
    
    # Backup original files
    log "Creating backups of original files..."
    cp "$ONPREM_DIR/dns.tf" "$ONPREM_DIR/dns.tf.backup" 2>/dev/null || true
    cp "$ONPREM_DIR/providers.tf" "$ONPREM_DIR/providers.tf.backup" 2>/dev/null || true
    cp "$AZURE_DIR/dns.tf" "$AZURE_DIR/dns.tf.backup" 2>/dev/null || true
    
    # Clean up any problematic connection files
    rm -f "$ONPREM_DIR/dns_connect_azure.tf"
    rm -f "$ONPREM_DIR/providers_connect.tf"
    rm -f "$AZURE_DIR/dns_connect_onprem.tf"
    rm -f "$AZURE_DIR/data.tf"
    
    # Apply the fixed DNS configuration for onprem
    log "Applying fixed onprem DNS configuration..."
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

    # Apply the fixed providers configuration for onprem
    log "Applying fixed onprem providers configuration..."
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

    success "Configuration fixes applied"
}

# Deploy OnPrem infrastructure
deploy_onprem() {
    log "Starting OnPrem infrastructure deployment..."
    
    cd "$ONPREM_DIR"
    
    # Initialize Terraform
    log "Initializing Terraform for OnPrem..."
    terraform init
    
    # Plan deployment
    log "Planning OnPrem deployment..."
    terraform plan -out=onprem.tfplan
    
    # Apply deployment
    log "Applying OnPrem deployment..."
    terraform apply onprem.tfplan
    
    # Get outputs
    log "Getting OnPrem outputs..."
    terraform output > onprem_outputs.txt
    
    success "OnPrem infrastructure deployed successfully"
    cd "$SCRIPT_DIR"
}

# Deploy Azure infrastructure
deploy_azure() {
    log "Starting Azure infrastructure deployment..."
    
    cd "$AZURE_DIR"
    
    # Initialize Terraform
    log "Initializing Terraform for Azure..."
    terraform init
    
    # Plan deployment
    log "Planning Azure deployment..."
    terraform plan -out=azure.tfplan
    
    # Apply deployment
    log "Applying Azure deployment..."
    terraform apply azure.tfplan
    
    # Get outputs
    log "Getting Azure outputs..."
    terraform output > azure_outputs.txt
    
    success "Azure infrastructure deployed successfully"
    cd "$SCRIPT_DIR"
}

# Connect DNS between environments
connect_dns() {
    log "Connecting DNS between Azure and OnPrem..."
    
    # Add connection files for Azure to OnPrem
    log "Creating Azure to OnPrem DNS connection..."
    cat > "$AZURE_DIR/dns_connect_onprem.tf" << 'EOF'
# DNS Connection to OnPrem - DEPLOY AFTER BOTH ENVIRONMENTS EXIST
# =============================================================================

# Data Source for OnPrem DNS Resolver
data "azurerm_private_dns_resolver_inbound_endpoint" "onprem" {
  name                    = "dnspr-onprem-hub-inbound"
  private_dns_resolver_id = data.azurerm_private_dns_resolver.onprem.id
}

data "azurerm_private_dns_resolver" "onprem" {
  name                = "dnspr-onprem-hub"
  resource_group_name = "rg-onprem-hub-p-weu"
  provider = azurerm.onprem
}

# Forwarding Rule for onprem.contoso.com (to OnPrem)
resource "azurerm_private_dns_resolver_forwarding_rule" "onprem_contoso" {
  name                      = "rule-onprem-contoso"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "onprem.contoso.com."
  enabled                   = true

  target_dns_servers {
    ip_address = data.azurerm_private_dns_resolver_inbound_endpoint.onprem.ip_configurations[0].private_ip_address
    port       = 53
  }

  depends_on = [
    azurerm_private_dns_resolver_dns_forwarding_ruleset.hub
  ]
}
EOF

    # Add connection files for OnPrem to Azure
    log "Creating OnPrem to Azure DNS connection..."
    cat > "$ONPREM_DIR/providers_connect.tf" << 'EOF'
# Additional provider for connecting to Azure Contoso
provider "azurerm" {
  alias = "contoso"
  resource_provider_registrations = "extended"
  features {}
  subscription_id = "052c919b-fb40-41f1-af1e-5466cd0dba91"
}
EOF

    cat > "$ONPREM_DIR/dns_connect_azure.tf" << 'EOF'
# DNS Connection to Azure Contoso - DEPLOY AFTER BOTH ENVIRONMENTS EXIST
# =============================================================================

# Data Source for Contoso DNS Resolver
data "azurerm_private_dns_resolver" "contoso" {
  name                = "dnspr-nccont-hub"
  resource_group_name = "rg-nccont-hub-p-weu"

  provider = azurerm.contoso
}

data "azurerm_private_dns_resolver_inbound_endpoint" "contoso" {
  name                    = "dnspr-nccont-hub-inbound"
  private_dns_resolver_id = data.azurerm_private_dns_resolver.contoso.id
}

# DNS Forwarding Rules for Azure domains
resource "azurerm_private_dns_resolver_forwarding_rule" "azure_contoso" {
  name                      = "rule-azure-contoso"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "azure.contoso.com."
  enabled                   = true

  target_dns_servers {
    ip_address = data.azurerm_private_dns_resolver_inbound_endpoint.contoso.ip_configurations[0].private_ip_address
    port       = 53
  }

  depends_on = [
    azurerm_private_dns_resolver_dns_forwarding_ruleset.hub
  ]
}
EOF

    # Apply DNS connections for Azure
    log "Applying Azure DNS connections..."
    cd "$AZURE_DIR"
    terraform init -upgrade
    terraform plan -out=azure_connect.tfplan
    terraform apply azure_connect.tfplan
    
    # Apply DNS connections for OnPrem
    log "Applying OnPrem DNS connections..."
    cd "$ONPREM_DIR"
    terraform init -upgrade
    terraform plan -out=onprem_connect.tfplan
    terraform apply onprem_connect.tfplan
    
    success "DNS connections established"
    cd "$SCRIPT_DIR"
}

# Get deployment status
get_status() {
    log "Getting deployment status..."
    
    echo ""
    echo "=== OnPrem Infrastructure Status ==="
    cd "$ONPREM_DIR"
    terraform show -json | jq -r '.values.root_module.resources[] | select(.address | contains("azurerm_")) | .address' | head -10
    
    echo ""
    echo "=== Azure Infrastructure Status ==="
    cd "$AZURE_DIR"
    terraform show -json | jq -r '.values.root_module.resources[] | select(.address | contains("azurerm_")) | .address' | head -10
    
    echo ""
    echo "=== Key Outputs ==="
    echo "OnPrem VPN Gateway IP:"
    cd "$ONPREM_DIR"
    terraform output -raw onprem_gateway_public_ip 2>/dev/null || echo "Not available"
    
    echo "Azure VPN Gateway IP:"
    cd "$AZURE_DIR"
    terraform output -raw firewall_private_ip 2>/dev/null || echo "Not available"
    
    echo "OnPrem DNS Resolver IP:"
    cd "$ONPREM_DIR"
    terraform output -raw onprem_dns_resolver_ip 2>/dev/null || echo "Not available"
    
    echo "Azure DNS Resolver IP:"
    cd "$AZURE_DIR"
    terraform output -raw dns_resolver_inbound_ip 2>/dev/null || echo "Not available"
    
    cd "$SCRIPT_DIR"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -f "$ONPREM_DIR"/*.tfplan
    rm -f "$AZURE_DIR"/*.tfplan
    rm -f "$ONPREM_DIR"/onprem_outputs.txt
    rm -f "$AZURE_DIR"/azure_outputs.txt
}

# Restore backups
restore_backups() {
    log "Restoring backup files..."
    mv "$ONPREM_DIR/dns.tf.backup" "$ONPREM_DIR/dns.tf" 2>/dev/null || true
    mv "$ONPREM_DIR/providers.tf.backup" "$ONPREM_DIR/providers.tf" 2>/dev/null || true
    mv "$AZURE_DIR/dns.tf.backup" "$AZURE_DIR/dns.tf" 2>/dev/null || true
}

# Error handling
trap 'error "Deployment failed. Check the logs above for details."; cleanup; exit 1' ERR

# Main deployment function
main() {
    log "Starting infrastructure deployment..."
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            apply_fixes
            deploy_onprem
            deploy_azure
            connect_dns
            get_status
            success "Complete infrastructure deployment finished successfully!"
            ;;
        "destroy")
            warning "Destroying infrastructure..."
            cd "$AZURE_DIR"
            terraform destroy -auto-approve || true
            cd "$ONPREM_DIR"
            terraform destroy -auto-approve || true
            success "Infrastructure destroyed"
            ;;
        "status")
            get_status
            ;;
        "restore")
            restore_backups
            success "Backup files restored"
            ;;
        *)
            echo "Usage: $0 [deploy|destroy|status|restore]"
            echo "  deploy  - Deploy complete infrastructure (default)"
            echo "  destroy - Destroy all infrastructure"
            echo "  status  - Show current deployment status"
            echo "  restore - Restore backup configuration files"
            exit 1
            ;;
    esac
    
    cleanup
}

# Run main function
main "$@"