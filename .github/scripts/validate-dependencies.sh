#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

K8S_DIR="${1:-k8s}"
ERRORS=0
WARNINGS=0

echo "=== Kubernetes Dependency Validation ==="
echo "Analyzing manifests in: $K8S_DIR"
echo ""

# Temporary files for tracking
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

NAMESPACES_DEFINED="$TMP_DIR/namespaces-defined.txt"
NAMESPACES_REQUIRED="$TMP_DIR/namespaces-required.txt"
CRDS_DEFINED="$TMP_DIR/crds-defined.txt"
CRDS_REQUIRED="$TMP_DIR/crds-required.txt"

# Initialize files
touch "$NAMESPACES_DEFINED" "$NAMESPACES_REQUIRED" "$CRDS_DEFINED" "$CRDS_REQUIRED"

echo "📋 Step 1: Extracting defined namespaces and CRDs..."

# Find all YAML files
find "$K8S_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) | while read -r file; do
    # Extract namespaces
    if grep -q "kind: Namespace" "$file"; then
        grep -A 5 "kind: Namespace" "$file" | grep "name:" | awk '{print $2}' >> "$NAMESPACES_DEFINED"
    fi

    # Extract CRDs
    if grep -q "kind: CustomResourceDefinition" "$file"; then
        grep "name:" "$file" | head -1 | awk '{print $2}' >> "$CRDS_DEFINED"
    fi
done

# Built-in namespaces
echo "default" >> "$NAMESPACES_DEFINED"
echo "kube-system" >> "$NAMESPACES_DEFINED"
echo "kube-public" >> "$NAMESPACES_DEFINED"
echo "kube-node-lease" >> "$NAMESPACES_DEFINED"

# Sort and unique
sort -u "$NAMESPACES_DEFINED" -o "$NAMESPACES_DEFINED"
sort -u "$CRDS_DEFINED" -o "$CRDS_DEFINED"

echo "   Found $(wc -l < "$NAMESPACES_DEFINED" | tr -d ' ') namespaces"
echo "   Found $(wc -l < "$CRDS_DEFINED" | tr -d ' ') CRDs"
echo ""

echo "📋 Step 2: Extracting required namespaces and CRDs..."

find "$K8S_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) | while read -r file; do
    # Skip if file is a namespace or CRD definition
    if grep -q "kind: Namespace" "$file" || grep -q "kind: CustomResourceDefinition" "$file"; then
        continue
    fi

    # Extract namespace references
    if grep -q "namespace:" "$file"; then
        grep "namespace:" "$file" | awk '{print $2}' | sed 's/[",]//g' >> "$NAMESPACES_REQUIRED"
    fi

    # Extract custom apiVersions (potential CRD usage)
    grep "apiVersion:" "$file" | awk '{print $2}' | grep -v "^v1$" | grep -v "^apps/" | grep -v "^batch/" | grep -v "^networking.k8s.io/" | grep -v "^rbac.authorization.k8s.io/" | grep -v "^policy/" | grep -v "^storage.k8s.io/" | grep -v "^admissionregistration.k8s.io/" >> "$CRDS_REQUIRED" || true
done

sort -u "$NAMESPACES_REQUIRED" -o "$NAMESPACES_REQUIRED"
sort -u "$CRDS_REQUIRED" -o "$CRDS_REQUIRED"

echo "   Found $(wc -l < "$NAMESPACES_REQUIRED" | tr -d ' ') namespace references"
echo "   Found $(wc -l < "$CRDS_REQUIRED" | tr -d ' ') potential CRD usages"
echo ""

echo "🔍 Step 3: Validating namespace dependencies..."

MISSING_NAMESPACES=0
while read -r ns; do
    if [ -z "$ns" ]; then continue; fi
    if ! grep -q "^${ns}$" "$NAMESPACES_DEFINED"; then
        echo -e "${RED}✗${NC} Namespace '$ns' is referenced but not defined"
        MISSING_NAMESPACES=$((MISSING_NAMESPACES + 1))
        ERRORS=$((ERRORS + 1))
    fi
done < "$NAMESPACES_REQUIRED"

if [ $MISSING_NAMESPACES -eq 0 ]; then
    echo -e "${GREEN}✓${NC} All referenced namespaces are defined"
fi
echo ""

echo "🔍 Step 4: Validating ArgoCD bootstrap order..."

# Check bootstrap exists
if [ ! -d "$K8S_DIR/bootstrap" ]; then
    echo -e "${RED}✗${NC} ArgoCD bootstrap directory not found"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓${NC} ArgoCD bootstrap directory exists"
fi

# Check root-app exists
if [ ! -d "$K8S_DIR/root-app" ]; then
    echo -e "${RED}✗${NC} Root application directory not found"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓${NC} Root application directory exists"
fi

# Check apps exist
if [ ! -d "$K8S_DIR/apps" ]; then
    echo -e "${RED}✗${NC} Apps directory not found"
    ERRORS=$((ERRORS + 1))
else
    APP_COUNT=$(find "$K8S_DIR/apps" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    echo -e "${GREEN}✓${NC} Apps directory exists with $APP_COUNT applications"
fi
echo ""

echo "🔍 Step 5: Validating ArgoCD application definitions..."

if [ -d "$K8S_DIR/apps" ]; then
    INVALID_APPS=0
    find "$K8S_DIR/apps" -mindepth 1 -maxdepth 1 -type d | while read -r app_dir; do
        app_name=$(basename "$app_dir")

        # Check if application.yaml exists
        if [ ! -f "$app_dir/application.yaml" ]; then
            echo -e "${YELLOW}⚠${NC}  App '$app_name' missing application.yaml"
            WARNINGS=$((WARNINGS + 1))
            continue
        fi

        # Validate Application kind
        if ! grep -q "kind: Application" "$app_dir/application.yaml"; then
            echo -e "${RED}✗${NC} App '$app_name' application.yaml is not an Application kind"
            INVALID_APPS=$((INVALID_APPS + 1))
        fi
    done

    if [ $INVALID_APPS -eq 0 ]; then
        echo -e "${GREEN}✓${NC} All ArgoCD applications are valid"
    fi
fi
echo ""

echo "📊 Summary:"
echo "   Errors: $ERRORS"
echo "   Warnings: $WARNINGS"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ Dependency validation FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Dependency validation PASSED${NC}"
    exit 0
fi
