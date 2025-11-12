#!/usr/bin/env bash
set -euo pipefail

# Apply configuration from config.env to all manifests
# This replaces placeholders with actual values

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$K8S_DIR/config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Applying k8s Configuration"
echo "========================================"
echo ""

# Check if config.env exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: config.env not found${NC}"
    echo "Please copy config.env.example to config.env and edit it:"
    echo "  cp $K8S_DIR/config.env.example $K8S_DIR/config.env"
    exit 1
fi

# Load configuration
echo -e "${GREEN}Loading configuration from config.env...${NC}"
source "$CONFIG_FILE"

# Validate required variables
if [ -z "${DOMAIN:-}" ] || [ "$DOMAIN" = "example.com" ]; then
    echo -e "${RED}Error: DOMAIN is not set or still has default value${NC}"
    echo "Please edit config.env and set your actual domain"
    exit 1
fi

if [ -z "${GITHUB_USERNAME:-}" ] || [ "$GITHUB_USERNAME" = "YOUR_USERNAME" ]; then
    echo -e "${RED}Error: GITHUB_USERNAME is not set or still has default value${NC}"
    echo "Please edit config.env and set your GitHub username"
    exit 1
fi

# Build derived values
CLUSTER_DOMAIN="${CLUSTER_SUBDOMAIN}.${DOMAIN}"
GIT_REPO_URL="https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO}.git"

echo ""
echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  Cluster Domain: $CLUSTER_DOMAIN"
echo "  GitHub: $GITHUB_USERNAME/$GITHUB_REPO"
echo "  Branch: $GIT_BRANCH"
echo ""

# Confirm before proceeding
read -p "Apply this configuration? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

echo ""
echo -e "${GREEN}Applying configuration...${NC}"

# Function to replace in file
replace_in_file() {
    local file=$1
    local search=$2
    local replace=$3

    if [ -f "$file" ]; then
        # Use different delimiter for sed to handle URLs
        sed -i.bak "s|${search}|${replace}|g" "$file"
        rm -f "${file}.bak"
    fi
}

# Replace in all YAML files
find "$K8S_DIR" -name "*.yaml" -type f | while read -r file; do
    # Skip config files themselves
    if [[ "$file" == *"kustomization.yaml"* ]]; then
        continue
    fi

    # Replace placeholders
    replace_in_file "$file" "YOURDOMAIN.COM" "$CLUSTER_DOMAIN"
    replace_in_file "$file" "YOUR_USERNAME" "$GITHUB_USERNAME"
    replace_in_file "$file" "k8s-hetzner" "$GITHUB_REPO"
    replace_in_file "$file" "yourdomain.com" "$DOMAIN"
done

# Count replacements made
DOMAIN_COUNT=$(grep -r "YOURDOMAIN.COM" "$K8S_DIR" --include="*.yaml" 2>/dev/null | wc -l || echo "0")
USERNAME_COUNT=$(grep -r "YOUR_USERNAME" "$K8S_DIR" --include="*.yaml" 2>/dev/null | wc -l || echo "0")

echo ""
if [ "$DOMAIN_COUNT" -eq 0 ] && [ "$USERNAME_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration applied successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review the changes: git diff"
    echo "  2. Update Authelia secrets in apps/authelia/manifests/configmap.yaml"
    echo "  3. Commit changes: git add . && git commit -m 'Configure cluster'"
    echo "  4. Deploy: kubectl apply -k bootstrap/argocd/"
else
    echo -e "${YELLOW}Warning: Some placeholders remain:${NC}"
    echo "  Domains with YOURDOMAIN.COM: $DOMAIN_COUNT"
    echo "  Files with YOUR_USERNAME: $USERNAME_COUNT"
    echo ""
    echo "Run the script again or check these files manually."
fi
