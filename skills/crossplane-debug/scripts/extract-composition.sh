#!/usr/bin/env bash
#
# Extract Crossplane composition, functions, and sample XR from a cluster
# for local debugging with `crossplane beta render`
#
# Usage:
#   extract-composition.sh <composition-name> [xr-kind] [xr-name] [namespace]
#
# Examples:
#   extract-composition.sh my-database-composition
#   extract-composition.sh my-app-composition XMyApp my-app-instance
#   extract-composition.sh my-app-composition XMyApp my-app-instance default
#
# Output:
#   Creates debug-<composition-name>/ directory with:
#   - composition.yaml
#   - functions.yaml
#   - xr.yaml (if XR provided or found)
#   - kcl-source.k (extracted inline KCL if present)

set -euo pipefail

COMPOSITION_NAME="${1:-}"
XR_KIND="${2:-}"
XR_NAME="${3:-}"
XR_NAMESPACE="${4:-}"

if [[ -z "$COMPOSITION_NAME" ]]; then
    echo "Usage: extract-composition.sh <composition-name> [xr-kind] [xr-name] [namespace]"
    echo ""
    echo "Examples:"
    echo "  extract-composition.sh my-database-composition"
    echo "  extract-composition.sh my-app-composition XMyApp my-app-instance"
    exit 1
fi

# Check prerequisites
for cmd in kubectl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Create output directory
OUTPUT_DIR="debug-${COMPOSITION_NAME}"
mkdir -p "$OUTPUT_DIR"
echo "Creating debug directory: $OUTPUT_DIR"

# Extract composition
echo "Extracting composition: $COMPOSITION_NAME"
if ! kubectl get composition "$COMPOSITION_NAME" -o yaml > "$OUTPUT_DIR/composition.yaml" 2>/dev/null; then
    echo "Error: Composition '$COMPOSITION_NAME' not found"
    exit 1
fi
echo "  -> composition.yaml"

# Extract XR type from composition
XR_API_VERSION=$(kubectl get composition "$COMPOSITION_NAME" -o jsonpath='{.spec.compositeTypeRef.apiVersion}')
XR_KIND_FROM_COMP=$(kubectl get composition "$COMPOSITION_NAME" -o jsonpath='{.spec.compositeTypeRef.kind}')
echo "  Composite type: $XR_KIND_FROM_COMP ($XR_API_VERSION)"

# Extract functions used in pipeline
echo "Extracting function definitions..."
FUNCTION_NAMES=$(kubectl get composition "$COMPOSITION_NAME" -o json | \
    jq -r '.spec.pipeline[]?.functionRef.name // empty' | sort -u)

if [[ -n "$FUNCTION_NAMES" ]]; then
    echo "  Functions found: $FUNCTION_NAMES"
    > "$OUTPUT_DIR/functions.yaml"
    
    for func in $FUNCTION_NAMES; do
        echo "  Extracting: $func"
        if kubectl get function "$func" -o yaml >> "$OUTPUT_DIR/functions.yaml" 2>/dev/null; then
            echo "---" >> "$OUTPUT_DIR/functions.yaml"
        else
            echo "  Warning: Function '$func' not found in cluster, adding placeholder"
            cat >> "$OUTPUT_DIR/functions.yaml" <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: $func
  annotations:
    render.crossplane.io/runtime: Default
---
EOF
        fi
    done
    echo "  -> functions.yaml"
else
    echo "  No functions found in pipeline"
fi

# Extract inline KCL source if present
echo "Checking for inline KCL..."
KCL_SOURCE=$(kubectl get composition "$COMPOSITION_NAME" -o json | \
    jq -r '.spec.pipeline[]? | select(.functionRef.name == "function-kcl") | .input.source // empty' 2>/dev/null || true)

if [[ -n "$KCL_SOURCE" ]]; then
    echo "$KCL_SOURCE" > "$OUTPUT_DIR/kcl-source.k"
    echo "  -> kcl-source.k (inline KCL extracted)"
fi

# Try to find or use provided XR
if [[ -n "$XR_KIND" && -n "$XR_NAME" ]]; then
    echo "Extracting XR: $XR_KIND/$XR_NAME"
    
    if [[ -n "$XR_NAMESPACE" ]]; then
        XR_JSON=$(kubectl get "$XR_KIND" "$XR_NAME" -n "$XR_NAMESPACE" -o json 2>/dev/null || true)
    else
        XR_JSON=$(kubectl get "$XR_KIND" "$XR_NAME" -o json 2>/dev/null || true)
    fi
    
    if [[ -n "$XR_JSON" ]]; then
        # Clean up the XR for use as render input
        echo "$XR_JSON" | jq 'del(.status) | 
            del(.metadata.resourceVersion) | 
            del(.metadata.uid) | 
            del(.metadata.generation) | 
            del(.metadata.creationTimestamp) | 
            del(.metadata.managedFields) |
            del(.metadata.finalizers) |
            del(.metadata.ownerReferences)' > "$OUTPUT_DIR/xr.yaml"
        echo "  -> xr.yaml"
    else
        echo "  Warning: Could not find XR $XR_KIND/$XR_NAME"
    fi
else
    # Try to find an XR of this type
    echo "Looking for existing XR of type $XR_KIND_FROM_COMP..."
    FOUND_XR=$(kubectl get "$XR_KIND_FROM_COMP" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    
    if [[ -n "$FOUND_XR" ]]; then
        echo "  Found: $FOUND_XR"
        kubectl get "$XR_KIND_FROM_COMP" "$FOUND_XR" -o json | jq 'del(.status) | 
            del(.metadata.resourceVersion) | 
            del(.metadata.uid) | 
            del(.metadata.generation) | 
            del(.metadata.creationTimestamp) | 
            del(.metadata.managedFields) |
            del(.metadata.finalizers) |
            del(.metadata.ownerReferences)' > "$OUTPUT_DIR/xr.yaml"
        echo "  -> xr.yaml"
    else
        echo "  No existing XR found. Creating template..."
        cat > "$OUTPUT_DIR/xr.yaml" <<EOF
# Template XR - fill in spec values
apiVersion: $XR_API_VERSION
kind: $XR_KIND_FROM_COMP
metadata:
  name: debug-example
spec:
  # TODO: Add spec fields based on your XRD
  {}
EOF
        echo "  -> xr.yaml (template - needs spec values)"
    fi
fi

# Summary
echo ""
echo "Extraction complete!"
echo ""
echo "Files created in $OUTPUT_DIR/:"
ls -la "$OUTPUT_DIR/"
echo ""
echo "To debug locally, run:"
echo "  cd $OUTPUT_DIR"
echo "  crossplane beta render xr.yaml composition.yaml functions.yaml"
echo ""
echo "If using local function development:"
echo "  # Terminal 1: Start function"
echo "  docker run --rm -p 9443:9443 xpkg.upbound.io/crossplane-contrib/function-kcl:latest --insecure --debug"
echo ""
echo "  # Terminal 2: Render (after updating functions.yaml with Development runtime)"
echo "  crossplane beta render xr.yaml composition.yaml functions.yaml"
