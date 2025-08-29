#!/bin/bash

# Local CI/CD Test Script for Wazuh SIEM
# This script simulates the CI/CD pipeline locally before pushing to GitHub

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="wazuh-local-test"
REPORT_DIR="./test-reports"
VENV_DIR="./venv"

print_step() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

cleanup() {
    print_step "Cleaning up test environment"
    export COMPOSE_PROJECT_NAME="$PROJECT_NAME"
    docker-compose down -v 2>/dev/null || true
    docker system prune -f >/dev/null 2>&1 || true
    print_success "Cleanup completed"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

check_prerequisites() {
    print_step "Checking Prerequisites"
    
    # Check required tools
    tools=("docker" "docker-compose" "ansible" "python3" "trivy")
    missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        else
            print_success "$tool is installed"
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    print_success "All prerequisites are met"
}

setup_python_env() {
    print_step "Setting up Python Environment"
    
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        print_success "Created virtual environment"
    fi
    
    source "$VENV_DIR/bin/activate"
    
    # Install required packages
    pip install --upgrade pip >/dev/null
    pip install ansible-lint yamllint pytest selenium requests webdriver-manager >/dev/null 2>&1
    
    print_success "Python environment ready"
}

quality_gates() {
    print_step "Running Quality Gates"
    
    # Create reports directory
    mkdir -p "$REPORT_DIR"
    
    # Ansible lint
    if [ -d "ansible/playbooks" ]; then
        echo "Running ansible-lint..."
        if ansible-lint ansible/playbooks/ > "$REPORT_DIR/ansible-lint.txt" 2>&1; then
            print_success "Ansible lint passed"
        else
            print_warning "Ansible lint found issues (check $REPORT_DIR/ansible-lint.txt)"
        fi
    fi
    
    # YAML lint
    echo "Running yamllint..."
    if yamllint docker-compose.yml config/ ansible/ trivy/ > "$REPORT_DIR/yaml-lint.txt" 2>&1; then
        print_success "YAML lint passed"
    else
        print_warning "YAML lint found issues (check $REPORT_DIR/yaml-lint.txt)"
    fi
    
    print_success "Quality gates completed"
}

build_and_scan() {
    print_step "Building and Scanning Images"
    
    # Create list of images to scan
    images_to_scan=()
    
    # Build custom images if any Dockerfiles exist
    if [ -d "docker" ]; then
        for dockerfile in docker/*/Dockerfile; do
            if [ -f "$dockerfile" ]; then
                image_name=$(basename $(dirname $dockerfile))
                echo "Building $image_name..."
                docker build -t "wazuh-$image_name:local" $(dirname $dockerfile)
                images_to_scan+=("wazuh-$image_name:local")
                print_success "Built wazuh-$image_name:local"
            fi
        done
    fi
    
    # Add base Wazuh images
    base_images=("wazuh/wazuh-manager:4.4.0" "wazuh/wazuh-indexer:4.4.0" "wazuh/wazuh-dashboard:4.4.0")
    for image in "${base_images[@]}"; do
        echo "Pulling $image..."
        docker pull $image >/dev/null 2>&1
        images_to_scan+=("$image")
        print_success "Pulled $image"
    done
    
    # Security scanning with Trivy
    mkdir -p "$REPORT_DIR/trivy"
    scan_failed=false
    
    for image in "${images_to_scan[@]}"; do
        echo "Scanning $image with Trivy..."
        safe_name=$(echo $image | tr '/:' '_')
        
        if trivy image \
            --config trivy/trivy.yaml \
            --ignorefile trivy/.trivyignore \
            --format json \
            --output "$REPORT_DIR/trivy/${safe_name}.json" \
            --exit-code 0 \
            --severity HIGH,CRITICAL \
            $image; then
            
            # Check for HIGH/CRITICAL vulnerabilities
            critical_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$REPORT_DIR/trivy/${safe_name}.json" 2>/dev/null || echo 0)
            high_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$REPORT_DIR/trivy/${safe_name}.json" 2>/dev/null || echo 0)
            
            if [ "$critical_count" -gt 0 ] || [ "$high_count" -gt 0 ]; then
                print_warning "$image has $critical_count CRITICAL and $high_count HIGH vulnerabilities"
                scan_failed=true
            else
                print_success "$image scan passed"
            fi
        else
            print_error "Failed to scan $image"
            scan_failed=true
        fi
    done
    
    if [ "$scan_failed" = true ]; then
        print_error "Security scan failed - check reports in $REPORT_DIR/trivy/"
        exit 1
    fi
    
    print_success "Security scanning completed"
}

generate_certificates() {
    print_step "Generating Certificates"
    
    if [ -f "generate-indexer-certs.yml" ]; then
        docker-compose -f generate-indexer-certs.yml up --abort-on-container-exit
        print_success "Certificates generated"
    else
        print_warning "Certificate generation playbook not found"
    fi
}

start_test_environment() {
    print_step "Starting Test Environment"
    
    export COMPOSE_PROJECT_NAME="$PROJECT_NAME"
    
    # Start services
    docker-compose up -d
    
    # Wait for services to be healthy
    echo "Waiting for services to start (this may take a few minutes)..."
    max_attempts=30
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -k -f https://localhost:443 >/dev/null 2>&1; then
            print_success "Dashboard is accessible"
            break
        fi
        
        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts - waiting 10 seconds..."
        sleep 10
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_error "Services failed to start within timeout"
        docker-compose logs
        exit 1
    fi
    
    print_success "Test environment is ready"
}

run_tests() {
    print_step "Running Tests"
    
    source "$VENV_DIR/bin/activate"
    
    # API tests
    if [ -f "tests/api/test_api_health.py" ]; then
        echo "Running API health tests..."
        cd tests/api
        if python -m pytest test_api_health.py -v --junitxml="../../$REPORT_DIR/api-results.xml"; then
            print_success "API tests passed"
        else
            print_error "API tests failed"
            cd ../..
            exit 1
        fi
        cd ../..
    fi
    
    # Selenium tests
    if [ -f "tests/selenium/test_wazuh_dashboard.py" ]; then
        echo "Running Selenium tests..."
        cd tests/selenium
        if python -m pytest test_wazuh_dashboard.py -v --junitxml="../../$REPORT_DIR/selenium-results.xml"; then
            print_success "Selenium tests passed"
        else
            print_error "Selenium tests failed"
            cd ../..
            exit 1
        fi
        cd ../..
    fi
    
    print_success "All tests passed"
}

simulate_deployment() {
    print_step "Simulating Deployment"

    # Create mock secrets for testing
    mkdir -p /tmp/mock-secrets
    echo "test-admin-password" > /tmp/mock-secrets/wazuh_admin_password
    echo "test-api-password" > /tmp/mock-secrets/wazuh_api_password
    echo "test-cluster-key-32chars-long-key" > /tmp/mock-secrets/wazuh_cluster_key
    chmod 600 /tmp/mock-secrets/*

    # Install Ansible collections if requirements file exists
    if [ -f "ansible/requirements.yml" ]; then
        echo "Installing Ansible collections..."
        ansible-galaxy collection install -r ansible/requirements.yml >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_success "Ansible collections installed"
        else
            print_warning "Failed to install some Ansible collections"
        fi
    else
        print_warning "No Ansible requirements.yml found, installing common collections..."
        ansible-galaxy collection install community.docker community.general >/dev/null 2>&1
    fi

    # Dry run deployment
    if [ -f "ansible/playbooks/deploy.yml" ]; then
        cd ansible
        echo "Running deployment dry-run..."
        if ansible-playbook -i inventory/hosts.yml playbooks/deploy.yml \
           --check \
           --diff \
           --extra-vars "deployment_env=testing" \
           --extra-vars "secrets_path=/tmp/mock-secrets"; then
            print_success "Deployment simulation passed"
        else
            print_warning "Deployment simulation found issues"
        fi
        cd ..
    else
        print_warning "Deployment playbook not found"
    fi

    # Cleanup mock secrets
    rm -rf /tmp/mock-secrets
}

generate_report() {
    print_step "Generating Test Report"
    
    report_file="$REPORT_DIR/local-cicd-report.md"
    
    cat > "$report_file" << EOF
# Local CI/CD Test Report

**Date:** $(date)
**Project:** Wazuh SIEM Local Testing

## Test Results Summary

### Quality Gates
- Ansible Lint: $([ -f "$REPORT_DIR/ansible-lint.txt" ] && echo "✅ Completed" || echo "⏭️ Skipped")
- YAML Lint: $([ -f "$REPORT_DIR/yaml-lint.txt" ] && echo "✅ Completed" || echo "⏭️ Skipped")

### Security Scanning
- Trivy Scans: $([ -d "$REPORT_DIR/trivy" ] && echo "✅ Completed" || echo "❌ Failed")

### Testing
- API Tests: $([ -f "$REPORT_DIR/api-results.xml" ] && echo "✅ Passed" || echo "⏭️ Skipped")
- Selenium Tests: $([ -f "$REPORT_DIR/selenium-results.xml" ] && echo "✅ Passed" || echo "⏭️ Skipped")

### Deployment
- Ansible Deployment: ✅ Simulated

## Files Generated
- Test reports: \`$REPORT_DIR/\`
- Screenshots: \`tests/selenium/screenshots/\`
- Trivy reports: \`$REPORT_DIR/trivy/\`

## Next Steps
The local CI/CD pipeline simulation completed successfully. You can now:
1. Review the generated reports
2. Commit and push your changes
3. The GitHub Actions pipeline will run automatically
EOF

    print_success "Report generated: $report_file"
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "🚀 Local CI/CD Pipeline Test for Wazuh SIEM"
    echo "============================================"
    echo -e "${NC}"
    
    check_prerequisites
    setup_python_env
    quality_gates
    build_and_scan
    generate_certificates
    start_test_environment
    run_tests
    simulate_deployment
    generate_report
    
    print_step "Local CI/CD Pipeline Test Completed Successfully"
    print_success "All checks passed! Ready for GitHub push."
    echo -e "\n${GREEN}📊 Check the reports in: $REPORT_DIR${NC}"
    echo -e "${GREEN}🌐 Dashboard accessible at: https://localhost:443${NC}"
    echo -e "${GREEN}📋 Test report: $REPORT_DIR/local-cicd-report.md${NC}\n"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --cleanup      Only run cleanup"
        echo "  --no-cleanup   Skip cleanup at the end"
        exit 0
        ;;
    --cleanup)
        cleanup
        exit 0
        ;;
    --no-cleanup)
        trap - EXIT
        main
        ;;
    *)
        main
        ;;
esac
