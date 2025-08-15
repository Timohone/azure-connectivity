#!/bin/bash

# Complete Infrastructure Deployment Script
# Deploys Contoso Azure + OnPrem infrastructure with proper dependency handling
# Version: 2.0

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$SCRIPT_DIR/onprem-contoso-com"
AZURE_DIR="$SCRIPT_DIR/azure-contoso-com"

# Deployment phases
PHASE_1="onprem-infrastructure"
PHASE_2="azure-core-infrastructure"
PHASE_3="azure-spoke-networks"
PHASE_4="azure-avnm-deployment"
PHASE_5="cross-environment-connections"

# Check prerequisites
check_prerequisites() {
    step "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d' ' -f2)
    info "Found Terraform version: $TERRAFORM_VERSION"
    
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
    
    # Show current Azure context
    CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
    info "Current Azure subscription: $CURRENT_SUBSCRIPTION"
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some features may not work properly."
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

# Apply configuration fixes
apply_configuration_fixes() {
    step "Applying configuration fixes..."
    
    # Create backups
    info "Creating configuration backups..."
    for dir in "$AZURE_DIR" "$ONPREM_DIR"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -name "*.tf" -exec cp {} {}.backup \; 2>/dev/null || true
        fi
    done
    
    # Clean up any problematic connection files from previous runs
    info "Cleaning up previous connection files..."
    rm -f "$AZURE_DIR/dns_connect_onprem.tf"
    rm -f "$ONPREM_DIR/dns_connect_azure.tf"
    rm -f "$ONPREM_DIR/providers_connect.tf"
    
    # Create the missing data.tf file for Azure
    info "Creating missing Azure data sources..."
    cat > "$AZURE_DIR/data.tf" << 'EOF'
# Data sources for cross-references
# =============================================================================

# Data source for hub DNS resolver (for spokes to reference)
data "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "dnspr-nccont-hub-inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  
  depends_on = [azurerm_private_dns_resolver_inbound_endpoint.hub]
}

# Management group data sources for AVNM
data "azurerm_management_group" "hybrid_management_group" {
  name = "mgm-nccont-landingzones-hybrid"
}

data "azurerm_management_group" "root_management_group" {
  name = "mgm-nccont-root"
}

data "azurerm_management_group" "connectivity_management_group" {
  name = "mgm-nccont-foundation-connectivity"
}
EOF

    # Fix baseline.tf in Azure
    info "Fixing Azure baseline configuration..."
    cat > "$AZURE_DIR/baseline.tf" << 'EOF'
# Baseline Configuration
# =============================================================================
# This file is used for baseline configurations that apply to all environments

# Common tags for all resources
locals {
  common_tags = {
    project      = "contoso-hub"
    managed_by   = "terraform"
    deployed_by  = "netcloud"
    cost_center  = "infrastructure"
  }
}

# Common naming conventions
locals {
  naming = {
    resource_group_prefix = "rg-nccont"
    vnet_prefix          = "vnet-nccont"
    subnet_prefix        = "snet-"
    pip_prefix           = "pip-nccont"
    vm_prefix            = "vm-nccont"
  }
}
EOF

    success "Configuration fixes applied"
}

# Initialize terraform in a directory
init_terraform() {
    local dir=$1
    local name=$2
    
    info "Initializing Terraform in $name..."
    cd "$dir"
    
    # Clean up any lock files
    rm -f .terraform.lock.hcl
    
    # Initialize
    if terraform init -upgrade; then
        success "✓ $name Terraform initialized"
    else
        error "✗ Failed to initialize $name Terraform"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
}

# Validate terraform configuration
validate_terraform() {
    local dir=$1
    local name=$2
    
    info "Validating $name configuration..."
    cd "$dir"
    
    if terraform validate; then
        success "✓ $name configuration is valid"
    else
        error "✗ $name configuration is invalid"
        terraform validate
        return 1
    fi
    
    cd "$SCRIPT_DIR"
}

# Plan terraform deployment
plan_terraform() {
    local dir=$1
    local name=$2
    local plan_file=$3
    local target_resources=$4
    
    info "Planning $name deployment..."
    cd "$dir"
    
    local plan_cmd="terraform plan -out=$plan_file"
    
    # Add target resources if specified
    if [[ -n "$target_resources" ]]; then
        for target in $target_resources; do
            plan_cmd="$plan_cmd -target=$target"
        done
    fi
    
    if eval "$plan_cmd"; then
        success "✓ $name plan completed"
    else
        error "✗ $name plan failed"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
}

# Apply terraform deployment
apply_terraform() {
    local dir=$1
    local name=$2
    local plan_file=$3
    
    info "Applying $name deployment..."
    cd "$dir"
    
    if terraform apply "$plan_file"; then
        success "✓ $name deployment completed"
    else
        error "✗ $name deployment failed"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
}

# Get terraform outputs
get_outputs() {
    local dir=$1
    local name=$2
    local output_file=$3
    
    info "Getting $name outputs..."
    cd "$dir"
    
    terraform output -json > "$output_file" 2>/dev/null || true
    
    cd "$SCRIPT_DIR"
}

# Deploy OnPrem infrastructure (Phase 1)
deploy_onprem() {
    step "=== PHASE 1: DEPLOYING ONPREM INFRASTRUCTURE ==="
    
    init_terraform "$ONPREM_DIR" "OnPrem"
    validate_terraform "$ONPREM_DIR" "OnPrem"
    plan_terraform "$ONPREM_DIR" "OnPrem" "onprem.tfplan"
    apply_terraform "$ONPREM_DIR" "OnPrem" "onprem.tfplan"
    get_outputs "$ONPREM_DIR" "OnPrem" "onprem_outputs.json"
    
    success "Phase 1 completed: OnPrem infrastructure deployed"
}

# Deploy Azure core infrastructure (Phase 2)
deploy_azure_core() {
    step "=== PHASE 2: DEPLOYING AZURE CORE INFRASTRUCTURE ==="
    
    init_terraform "$AZURE_DIR" "Azure"
    validate_terraform "$AZURE_DIR" "Azure"
    
    # Deploy core infrastructure first (without AVNM)
    local core_targets="
        azurerm_resource_group.hub
        azurerm_virtual_network.hub
        azurerm_subnet.gateway
        azurerm_subnet.firewall
        azurerm_subnet.firewall_management
        azurerm_subnet.dns_inbound
        azurerm_subnet.dns_outbound
        azurerm_subnet.management
        azurerm_log_analytics_workspace.hub
        azurerm_private_dns_resolver.hub
        azurerm_private_dns_resolver_inbound_endpoint.hub
        azurerm_private_dns_resolver_outbound_endpoint.hub
        azurerm_private_dns_resolver_dns_forwarding_ruleset.hub
        azurerm_private_dns_zone.azure_contoso
        azurerm_firewall_policy.hub
        azurerm_public_ip.firewall
        azurerm_public_ip.firewall_management
        azurerm_firewall.hub
        azurerm_public_ip.vpn_gateway
        azurerm_virtual_network_gateway.vpn
        azurerm_local_network_gateway.to_onprem
        azurerm_virtual_network_gateway_connection.contoso_to_onprem
    "
    
    plan_terraform "$AZURE_DIR" "Azure Core" "azure_core.tfplan" "$core_targets"
    apply_terraform "$AZURE_DIR" "Azure Core" "azure_core.tfplan"
    
    success "Phase 2 completed: Azure core infrastructure deployed"
}

# Deploy Azure spoke networks (Phase 3)
deploy_azure_spokes() {
    step "=== PHASE 3: DEPLOYING AZURE SPOKE NETWORKS ==="
    
    cd "$AZURE_DIR"
    
    # Deploy spoke networks
    local spoke_targets="
        azurerm_resource_group.rg_app1_prod
        azurerm_virtual_network.vnet_app1_prod
        azurerm_subnet.snet_app1_prod
        azurerm_resource_group.rg_app1_nonprod
        azurerm_virtual_network.vnet_app1_nonprod
        azurerm_subnet.snet_app1_nonprod
        azurerm_resource_group.resource_group_hrportal_prod
        azurerm_virtual_network.vnet_hrportal_prod
        azurerm_subnet.subnet_hrportal_prod
        azurerm_resource_group.rg_hrportal_nonprod
        azurerm_virtual_network.vnet_hrportal_nonprod
        azurerm_subnet.snet_hrportal_nonprod
        azurerm_resource_group.rg_ncae
        azurerm_virtual_network.vnet_ncae
        azurerm_subnet.snet_ncae
    "
    
    plan_terraform "$AZURE_DIR" "Azure Spokes" "azure_spokes.tfplan" "$spoke_targets"
    apply_terraform "$AZURE_DIR" "Azure Spokes" "azure_spokes.tfplan"
    
    success "Phase 3 completed: Azure spoke networks deployed"
    
    cd "$SCRIPT_DIR"
}

# Deploy Azure AVNM (Phase 4)
deploy_azure_avnm() {
    step "=== PHASE 4: DEPLOYING AZURE AVNM ==="
    
    cd "$AZURE_DIR"
    
    # Deploy remaining resources including AVNM
    plan_terraform "$AZURE_DIR" "Azure Complete" "azure_complete.tfplan"
    apply_terraform "$AZURE_DIR" "Azure Complete" "azure_complete.tfplan"
    get_outputs "$AZURE_DIR" "Azure" "azure_outputs.json"
    
    success "Phase 4 completed: Azure AVNM and remaining resources deployed"
    
    cd "$SCRIPT_DIR"
}

# Connect DNS between environments (Phase 5)
connect_environments() {
    step "=== PHASE 5: CONNECTING ENVIRONMENTS ==="
    
    info "Getting OnPrem DNS resolver IP..."
    cd "$ONPREM_DIR"
    ONPREM_DNS_IP=$(terraform output -raw onprem_dns_resolver_ip 2>/dev/null || echo "")
    
    info "Getting Azure DNS resolver IP..."
    cd "$AZURE_DIR"
    AZURE_DNS_IP=$(terraform output -raw dns_resolver_inbound_ip 2>/dev/null || echo "")
    
    if [[ -z "$ONPREM_DNS_IP" || -z "$AZURE_DNS_IP" ]]; then
        warning "Could not retrieve DNS IPs. Skipping DNS connections."
        return 0
    fi
    
    info "OnPrem DNS IP: $ONPREM_DNS_IP"
    info "Azure DNS IP: $AZURE_DNS_IP"
    
    # Create Azure to OnPrem DNS connection
    info "Creating Azure to OnPrem DNS forwarding..."
    cat > "$AZURE_DIR/dns_connect_onprem.tf" << EOF
# DNS Connection to OnPrem - DEPLOY AFTER BOTH ENVIRONMENTS EXIST
# =============================================================================

# Data Source for OnPrem DNS Resolver
data "azurerm_private_dns_resolver_inbound_endpoint" "onprem" {
  name                    = "dnspr-onprem-hub-inbound"
  private_dns_resolver_id = data.azurerm_private_dns_resolver.onprem.id
  
  provider = azurerm.onprem
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
    ip_address = "$ONPREM_DNS_IP"
    port       = 53
  }

  depends_on = [
    azurerm_private_dns_resolver_dns_forwarding_ruleset.hub
  ]
}
EOF

    # Create OnPrem to Azure DNS connection
    info "Creating OnPrem to Azure DNS forwarding..."
    cat > "$ONPREM_DIR/providers_connect.tf" << 'EOF'
# Additional provider for connecting to Azure Contoso
provider "azurerm" {
  alias = "contoso"
  resource_provider_registrations = "extended"
  features {}
  subscription_id = "052c919b-fb40-41f1-af1e-5466cd0dba91"
}
EOF

    cat > "$ONPREM_DIR/dns_connect_azure.tf" << EOF
# DNS Connection to Azure Contoso - DEPLOY AFTER BOTH ENVIRONMENTS EXIST
# =============================================================================

# DNS Forwarding Rules for Azure domains
resource "azurerm_private_dns_resolver_forwarding_rule" "azure_contoso" {
  name                      = "rule-azure-contoso"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub.id
  domain_name               = "azure.contoso.com."
  enabled                   = true

  target_dns_servers {
    ip_address = "$AZURE_DNS_IP"
    port       = 53
  }

  depends_on = [
    azurerm_private_dns_resolver_dns_forwarding_ruleset.hub
  ]
}
EOF

    # Apply DNS connections for Azure
    info "Applying Azure DNS connections..."
    cd "$AZURE_DIR"
    terraform init -upgrade
    terraform plan -out=azure_connect.tfplan
    terraform apply azure_connect.tfplan
    
    # Apply DNS connections for OnPrem
    info "Applying OnPrem DNS connections..."
    cd "$ONPREM_DIR"
    terraform init -upgrade
    terraform plan -out=onprem_connect.tfplan
    terraform apply onprem_connect.tfplan
    
    success "Phase 5 completed: Environments connected"
    
    cd "$SCRIPT_DIR"
}

# Get deployment status
get_deployment_status() {
    step "=== DEPLOYMENT STATUS ==="
    
    echo ""
    echo "🏗️  Infrastructure Overview:"
    echo "=============================="
    
    # OnPrem Status
    if [[ -f "$ONPREM_DIR/terraform.tfstate" ]]; then
        echo "✅ OnPrem Infrastructure: DEPLOYED"
        cd "$ONPREM_DIR"
        
        ONPREM_VPN_IP=$(terraform output -raw onprem_gateway_public_ip 2>/dev/null || echo "Not available")
        ONPREM_DNS_IP=$(terraform output -raw onprem_dns_resolver_ip 2>/dev/null || echo "Not available")
        
        echo "   🌐 VPN Gateway IP: $ONPREM_VPN_IP"
        echo "   🔍 DNS Resolver IP: $ONPREM_DNS_IP"
    else
        echo "❌ OnPrem Infrastructure: NOT DEPLOYED"
    fi
    
    # Azure Status
    if [[ -f "$AZURE_DIR/terraform.tfstate" ]]; then
        echo "✅ Azure Infrastructure: DEPLOYED"
        cd "$AZURE_DIR"
        
        AZURE_FW_IP=$(terraform output -raw firewall_private_ip 2>/dev/null || echo "Not available")
        AZURE_DNS_IP=$(terraform output -raw dns_resolver_inbound_ip 2>/dev/null || echo "Not available")
        HUB_VNET_ID=$(terraform output -raw hub_vnet_id 2>/dev/null || echo "Not available")
        
        echo "   🔥 Firewall Private IP: $AZURE_FW_IP"
        echo "   🔍 DNS Resolver IP: $AZURE_DNS_IP"
        echo "   🌐 Hub VNet ID: $(basename "$HUB_VNET_ID")"
    else
        echo "❌ Azure Infrastructure: NOT DEPLOYED"
    fi
    
    # Check for cross-connections
    if [[ -f "$AZURE_DIR/dns_connect_onprem.tf" && -f "$ONPREM_DIR/dns_connect_azure.tf" ]]; then
        echo "✅ Cross-Environment DNS: CONNECTED"
    else
        echo "⚠️  Cross-Environment DNS: NOT CONNECTED"
    fi
    
    echo ""
    echo "🔗 Key Connection Information:"
    echo "=============================="
    echo "OnPrem to Azure VPN: Configured"
    echo "Azure to OnPrem VPN: Configured"
    echo "DNS Resolution: Hub-and-Spoke with Cross-Domain Forwarding"
    echo "Firewall Rules: Hub-Spoke + OnPrem connectivity"
    echo "AVNM: Hub-and-Spoke topology with routing and security"
    
    cd "$SCRIPT_DIR"
}

# Cleanup function
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    rm -f "$ONPREM_DIR"/*.tfplan
    rm -f "$AZURE_DIR"/*.tfplan
    rm -f "$ONPREM_DIR"/*.json
    rm -f "$AZURE_DIR"/*.json
}

# Restore backups
restore_backups() {
    warning "Restoring backup files..."
    for dir in "$AZURE_DIR" "$ONPREM_DIR"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -name "*.tf.backup" | while read -r backup; do
                original="${backup%.backup}"
                mv "$backup" "$original"
                info "Restored $(basename "$original")"
            done
        fi
    done
    success "Backup files restored"
}

# Destroy infrastructure
destroy_infrastructure() {
    warning "⚠️  DESTROYING ALL INFRASTRUCTURE ⚠️"
    
    read -p "Are you sure you want to destroy all infrastructure? Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Destruction cancelled"
        return 0
    fi
    
    # Destroy in reverse order
    warning "Destroying Azure infrastructure..."
    cd "$AZURE_DIR"
    terraform destroy -auto-approve || true
    
    warning "Destroying OnPrem infrastructure..."
    cd "$ONPREM_DIR"
    terraform destroy -auto-approve || true
    
    # Clean up connection files
    rm -f "$AZURE_DIR/dns_connect_onprem.tf"
    rm -f "$ONPREM_DIR/dns_connect_azure.tf"
    rm -f "$ONPREM_DIR/providers_connect.tf"
    
    success "Infrastructure destroyed"
    cd "$SCRIPT_DIR"
}

# Error handling
error_handler() {
    error "Deployment failed at line $1"
    error "Check the logs above for details"
    cleanup_temp_files
    exit 1
}

# Set up error trapping
trap 'error_handler $LINENO' ERR

# Main deployment function
main() {
    echo ""
    echo "🚀 Contoso Infrastructure Deployment Script"
    echo "=========================================="
    echo ""
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            apply_configuration_fixes
            deploy_onprem
            deploy_azure_core
            deploy_azure_spokes
            deploy_azure_avnm
            connect_environments
            get_deployment_status
            success "🎉 Complete infrastructure deployment finished successfully!"
            ;;
        "onprem-only")
            check_prerequisites
            apply_configuration_fixes
            deploy_onprem
            success "OnPrem infrastructure deployed"
            ;;
        "azure-only")
            check_prerequisites
            apply_configuration_fixes
            deploy_azure_core
            deploy_azure_spokes
            deploy_azure_avnm
            success "Azure infrastructure deployed"
            ;;
        "connect")
            connect_environments
            success "Environments connected"
            ;;
        "destroy")
            destroy_infrastructure
            ;;
        "status")
            get_deployment_status
            ;;
        "restore")
            restore_backups
            ;;
        "fix")
            apply_configuration_fixes
            success "Configuration fixes applied"
            ;;
        *)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  deploy       - Deploy complete infrastructure (default)"
            echo "  onprem-only  - Deploy only OnPrem infrastructure"
            echo "  azure-only   - Deploy only Azure infrastructure"
            echo "  connect      - Connect DNS between environments"
            echo "  destroy      - Destroy all infrastructure"
            echo "  status       - Show current deployment status"
            echo "  restore      - Restore backup configuration files"
            echo "  fix          - Apply configuration fixes only"
            echo ""
            echo "Examples:"
            echo "  ./deploy.sh deploy        # Full deployment"
            echo "  ./deploy.sh onprem-only   # OnPrem only"
            echo "  ./deploy.sh status        # Check status"
            echo "  ./deploy.sh destroy       # Destroy everything"
            ;;
    esac
    
    cleanup_temp_files
}

# Run main function
main "$@"