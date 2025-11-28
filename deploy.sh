#!/bin/bash
# deploy.sh - Single command deployment script with clean slate capability

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Error handler
handle_error() {
    local exit_code=$1
    echo ""
    log_error "================================================"
    log_error "Deployment failed with exit code: $exit_code"
    log_error "================================================"
    echo ""
    log_warn "An error occurred during deployment."
    echo ""
    
    # Return to root
    cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")" || true
    
    read -p "$(echo -e ${YELLOW}Do you want to clean up and start fresh? [yes/NO]: ${NC})" -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleaning up failed deployment..."
        cleanup_infrastructure
        log_info "Cleanup completed. Fix the error and run: ./deploy.sh"
    else
        log_info "Cleanup skipped. Fix the error and rerun: ./deploy.sh"
    fi
    
    exit "$exit_code"
}

trap 'handle_error $?' ERR

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v terraform &> /dev/null || missing_tools+=("terraform")
    command -v ansible &> /dev/null || missing_tools+=("ansible")
    command -v aws &> /dev/null || missing_tools+=("aws-cli")
    command -v git &> /dev/null || missing_tools+=("git")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log_info "All prerequisites met ✓"
}

load_environment() {
    log_step "Loading environment variables from .env..."
    
    if [ ! -f ".env" ]; then
        log_error ".env file not found"
        log_info "Copy .env.example to .env and configure it"
        exit 1
    fi
    
    # Source .env file safely - create temp file for sourcing
    local tmp_env=$(mktemp)
    grep -v '^#' .env | grep -v '^$' | grep '=' | sed 's/\r$//' > "$tmp_env"
    set -a
    # shellcheck disable=SC1090
    source "$tmp_env"
    set +a
    rm -f "$tmp_env"
    
    # Verify critical variables
    local missing_vars=()
    
    [ -z "${DOMAIN:-}" ] && missing_vars+=("DOMAIN")
    [ -z "${CF_API_EMAIL:-}" ] && missing_vars+=("CF_API_EMAIL")
    [ -z "${CF_DNS_API_TOKEN:-}" ] && missing_vars+=("CF_DNS_API_TOKEN")
    [ -z "${JWT_SECRET:-}" ] && missing_vars+=("JWT_SECRET")
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing or empty variables in .env: ${missing_vars[*]}"
        exit 1
    fi
    
    # Export for Terraform
    export TF_VAR_domain="$DOMAIN"
    export TF_VAR_cloudflare_email="$CF_API_EMAIL"
    export TF_VAR_cloudflare_api_token="$CF_DNS_API_TOKEN"
    export TF_VAR_jwt_secret="$JWT_SECRET"
    
    log_info "Environment variables loaded ✓"
    log_info "  Domain: $DOMAIN"
    log_info "  Cloudflare Email: $CF_API_EMAIL"
}

check_config_files() {
    log_step "Checking configuration files..."
    
    if [ ! -f "infra/terraform/terraform.tfvars" ]; then
        log_error "terraform.tfvars not found"
        log_info "Copy terraform.tfvars.example to terraform.tfvars and configure it"
        exit 1
    fi
    
    log_info "Configuration files validated ✓"
}

setup_remote_state() {
    log_step "Setting up remote state backend..."
    
    cd infra/terraform
    
    BUCKET_NAME=$(grep 'bucket.*=' backend.tf | grep -v '#' | sed 's/.*"\(.*\)".*/\1/' | head -1)
    TABLE_NAME=$(grep 'dynamodb_table.*=' backend.tf | grep -v '#' | sed 's/.*"\(.*\)".*/\1/' | head -1)
    REGION=$(grep 'region.*=' backend.tf | grep -v '#' | sed 's/.*"\(.*\)".*/\1/' | head -1)
    
    if [ -z "$BUCKET_NAME" ] || [ -z "$TABLE_NAME" ]; then
        log_error "Could not parse backend configuration from backend.tf"
        cd ../..
        exit 1
    fi
    
    log_info "Backend: bucket=$BUCKET_NAME, table=$TABLE_NAME, region=$REGION"
    
    # Create S3 bucket if needed
    if ! aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        log_warn "Creating S3 bucket..."
        
        if [ "$REGION" == "us-east-1" ]; then
            aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" &> /dev/null || true
        else
            aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" \
                --create-bucket-configuration LocationConstraint="${REGION}" &> /dev/null || true
        fi
        
        aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" \
            --versioning-configuration Status=Enabled &> /dev/null || true
        
        log_info "S3 bucket created ✓"
    else
        log_info "S3 bucket exists ✓"
    fi
    
    # Create DynamoDB table if needed
    if ! aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" &> /dev/null; then
        log_warn "Creating DynamoDB table..."
        aws dynamodb create-table \
            --table-name "${TABLE_NAME}" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "${REGION}" &> /dev/null || true
        
        aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}" &> /dev/null || true
        log_info "DynamoDB table created ✓"
    else
        log_info "DynamoDB table exists ✓"
    fi
    
    cd ../..
}

check_existing_infrastructure() {
    log_step "Checking for existing infrastructure..."
    
    cd infra/terraform
    
    terraform init -input=false &> /dev/null || true
    
    if terraform state list 2>/dev/null | grep -q "aws_instance.app_server"; then
        log_warn "================================================"
        log_warn "⚠️  EXISTING INFRASTRUCTURE DETECTED"
        log_warn "================================================"
        echo ""
        log_info "Current resources:"
        terraform state list 2>/dev/null | sed 's/^/  - /' || echo "  (Unable to list)"
        echo ""
        
        cd ../..
        return 0
    else
        log_info "No existing infrastructure found ✓"
        cd ../..
        return 1
    fi
}

cleanup_infrastructure() {
    log_step "Destroying existing infrastructure..."
    
    cd infra/terraform
    
    log_info "Running terraform destroy..."
    if terraform destroy -auto-approve 2>&1; then
        log_info "Infrastructure destroyed ✓"
    else
        log_warn "Destroy failed. Removing from state..."
        
        terraform state rm aws_security_group.app_server 2>/dev/null || true
        terraform state rm aws_key_pair.deployer 2>/dev/null || true
        terraform state rm aws_instance.app_server 2>/dev/null || true
        terraform state rm aws_eip.app_server 2>/dev/null || true
        
        log_warn "Removed from state. Manual AWS cleanup may be needed."
    fi
    
    rm -f terraform.tfstate.backup tfplan .terraform.lock.hcl
    rm -rf .terraform/modules
    rm -f ../ansible/inventory/hosts
    
    cd ../..
    
    log_info "Cleanup completed ✓"
}

prompt_clean_slate() {
    echo ""
    log_warn "This will:"
    echo "  1. Destroy ALL existing infrastructure"
    echo "  2. Delete EC2 instances, security groups, elastic IPs"
    echo "  3. Remove all deployed containers"
    echo "  4. Start fresh deployment"
    echo ""
    log_error "⚠️  THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Proceed with clean slate? [yes/NO]: ${NC})" -r
    echo ""
    
    [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]
}

check_and_clear_lock() {
    log_info "Checking for state locks..."

    # Try to run plan with short timeout to detect locks
    if ! terraform plan -input=false -lock-timeout=10s &> /tmp/tf_lock_check.log; then
        if grep -q "Error acquiring the state lock" /tmp/tf_lock_check.log; then
            LOCK_ID=$(grep "ID:" /tmp/tf_lock_check.log | awk '{print $2}')
            LOCK_TIME=$(grep "Created:" /tmp/tf_lock_check.log | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
            LOCK_WHO=$(grep "Who:" /tmp/tf_lock_check.log | awk '{print $2}')

            log_warn "Found state lock:"
            log_warn "  ID: $LOCK_ID"
            log_warn "  Created: $LOCK_TIME"
            log_warn "  By: $LOCK_WHO"
            echo ""

            read -p "$(echo -e ${YELLOW}Automatically unlock? [yes/NO]: ${NC})" -r
            echo ""

            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                log_info "Unlocking state..."
                terraform force-unlock -force "$LOCK_ID"
                log_info "State unlocked ✓"
                sleep 2
            else
                log_error "Cannot proceed with locked state"
                exit 1
            fi
        else
            # Some other error, not a lock issue
            cat /tmp/tf_lock_check.log
            exit 1
        fi
    else
        log_info "No state locks detected ✓"
    fi

    rm -f /tmp/tf_lock_check.log
}

deploy_infrastructure() {
    log_step "Deploying infrastructure with Terraform..."

    cd infra/terraform

    log_info "Initializing Terraform..."
    terraform init -input=false

    log_info "Validating configuration..."
    terraform validate

    # Check and clear any locks before proceeding
    check_and_clear_lock

    log_info "Planning changes..."
    terraform plan -out=tfplan

    log_info "Applying changes..."
    terraform apply -auto-approve tfplan

    log_info "Infrastructure deployed ✓"

    cd ../..
}

verify_deployment() {
    log_step "Verifying deployment..."
    
    cd infra/terraform
    
    DOMAIN=$(terraform output -raw application_url 2>/dev/null | sed 's|https://||' || echo "")
    SERVER_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
    
    cd ../..
    
    if [ -z "$DOMAIN" ] || [ -z "$SERVER_IP" ]; then
        log_warn "Could not get deployment outputs"
        return
    fi
    
    log_info "Waiting for services (60s)..."
    sleep 60
    
    log_info "Checking application..."
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}" 2>/dev/null || echo "000")
    
    if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
        log_info "Application accessible ✓ (HTTP $HTTP_CODE)"
    else
        log_warn "Application returned HTTP $HTTP_CODE (may need more time)"
    fi
    
    echo ""
    log_info "======================================"
    log_info "Deployment Summary"
    log_info "======================================"
    log_info "URL: https://$DOMAIN"
    log_info "IP: $SERVER_IP"
    log_info "SSH: ssh -i ~/.ssh/id_rsa ubuntu@$SERVER_IP"
    log_info "======================================"
}

main() {
    echo ""
    log_info "================================================"
    log_info "TODO Application Deployment"
    log_info "================================================"
    echo ""
    
    FORCE_CLEAN=false
    [[ "${1:-}" =~ ^(-c|--clean)$ ]] && FORCE_CLEAN=true
    
    check_prerequisites
    load_environment
    check_config_files
    setup_remote_state
    
    if check_existing_infrastructure; then
        if [ "$FORCE_CLEAN" = true ]; then
            log_info "Force clean mode..."
            cleanup_infrastructure
        else
            if prompt_clean_slate; then
                cleanup_infrastructure
            else
                log_info "Continuing with existing infrastructure..."
            fi
        fi
    else
        log_info "Fresh deployment..."
    fi
    
    deploy_infrastructure
    verify_deployment
    
    echo ""
    log_info "================================================"
    log_info "Deployment completed successfully! 🚀"
    log_info "================================================"
    echo ""
}

main "$@"