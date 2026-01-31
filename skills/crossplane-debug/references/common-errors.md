# Common Crossplane Errors and Solutions

## Table of Contents
- [Composition Errors](#composition-errors)
- [Function Pipeline Errors](#function-pipeline-errors)
- [Managed Resource Errors](#managed-resource-errors)
- [Provider Errors](#provider-errors)
- [Claim/XR Errors](#claimxr-errors)

## Composition Errors

### "cannot compose resources: cannot render pipeline"

**Cause:** Function pipeline failed to execute.

**Debug:**
```bash
crossplane beta render xr.yaml composition.yaml functions.yaml 2>&1
```

**Common fixes:**
- Check function is installed: `kubectl get functions`
- Verify function name in pipeline matches installed function
- Check function logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/function=<name>`

---

### "cannot find composition for composite resource"

**Cause:** No Composition matches the XR type or selector.

**Debug:**
```bash
kubectl get compositions -o wide
kubectl get <xr> -o yaml | grep compositionRef
```

**Fixes:**
- Verify Composition `spec.compositeTypeRef` matches XR's apiVersion/kind
- Check label selectors if using `compositionSelector`

---

### "cannot get composite resource"

**Cause:** Claim cannot find or access the XR it created.

**Fixes:**
- Check XR exists: `kubectl get <xr-kind> -A`
- Verify claim has correct namespace
- Check RBAC permissions

## Function Pipeline Errors

### KCL: "attribute not found"

**Cause:** Accessing non-existent field on object.

**Example error:**
```
attribute 'bucketName' not found in schema 'Spec'
```

**Fix:** Use safe access with defaults:
```python
# Wrong
bucket_name = oxr.spec.bucketName

# Correct
bucket_name = oxr.spec.bucketName or "default-name"
```

---

### KCL: "None type has no attribute"

**Cause:** Calling method or accessing attribute on None value.

**Fix:** Add null checks:
```python
spec = oxr.spec or {}
nested = spec.get("nested", {})
```

---

### KCL: "expected list, got NoneType"

**Cause:** Iterating over None instead of list.

**Fix:**
```python
# Wrong
for item in oxr.spec.items:

# Correct
for item in (oxr.spec.items or []):
```

---

### "function-kcl: error running function"

**Cause:** KCL code has syntax or runtime error.

**Debug:**
```bash
# Run function in debug mode
docker run --rm -p 9443:9443 xpkg.upbound.io/crossplane-contrib/function-kcl:latest --insecure --debug

# In another terminal
crossplane beta render xr.yaml composition.yaml functions.yaml
```

Check the function container logs for stack trace.

---

### "function not found: function-xyz"

**Cause:** Function referenced in pipeline but not in functions.yaml or not installed.

**Fix for local render:**
Add to functions.yaml:
```yaml
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-xyz
```

**Fix for cluster:**
```bash
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-xyz
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-xyz:latest
EOF
```

## Managed Resource Errors

### Synced=False: "cannot create resource"

**Causes:**
1. Invalid spec values
2. Missing required fields
3. Provider authentication issue

**Debug:**
```bash
kubectl describe <managed-resource> <name>
kubectl logs -n crossplane-system deploy/<provider-name> --tail=50
```

---

### Synced=False: "cannot observe resource: not found"

**Cause:** External resource was deleted outside Crossplane.

**Fixes:**
- Recreate: `kubectl annotate <resource> crossplane.io/external-create-pending=-`
- Or delete and recreate the managed resource

---

### Ready=False: "resource is not ready"

**Cause:** Cloud resource still provisioning.

**Action:** Wait and check cloud console for actual status.

---

### "cannot resolve references"

**Cause:** Referenced resource doesn't exist or selector doesn't match.

**Debug:**
```bash
# Check reference target exists
kubectl get <referenced-kind> <referenced-name>

# Check selector matches
kubectl get <referenced-kind> -l <selector-labels>
```

**Fix:** Ensure referenced resource exists before referencing resource.

---

### "cannot update resource: immutable field"

**Cause:** Trying to change a field that cannot be updated after creation.

**Fixes:**
- Delete and recreate the resource
- Or remove the field from the composition and let it keep its current value

## Provider Errors

### "cannot initialize provider: missing credentials"

**Cause:** ProviderConfig missing or credentials secret not found.

**Fix:**
```bash
# Check ProviderConfig exists
kubectl get providerconfig

# Check credentials secret
kubectl get secret -n crossplane-system <secret-name>
```

---

### "rate limit exceeded"

**Cause:** Too many API calls to cloud provider.

**Fixes:**
- Wait and retry
- Reduce number of managed resources reconciling simultaneously
- Request limit increase from cloud provider

---

### "insufficient permissions"

**Cause:** IAM/RBAC doesn't allow the operation.

**Debug:**
```bash
kubectl logs -n crossplane-system deploy/<provider> | grep -i permission
```

**Fix:** Update IAM role/policy for provider credentials.

## Claim/XR Errors

### Claim stuck in "Waiting"

**Causes:**
1. Composition not found
2. Function error
3. Managed resource creation failed

**Debug:**
```bash
crossplane beta trace <claim-kind>/<name> -n <namespace>
kubectl describe <claim-kind> <name> -n <namespace>
```

---

### "cannot publish connection details"

**Cause:** Connection secret already exists or namespace issue.

**Fixes:**
- Delete existing secret: `kubectl delete secret <name> -n <namespace>`
- Check `writeConnectionSecretToRef` namespace matches claim namespace

---

### XR missing composed resources

**Cause:** Function pipeline returned no resources or error.

**Debug:**
```bash
crossplane beta render xr.yaml composition.yaml functions.yaml
```

Check if output contains expected resources.

---

### "status.conditions: Ready=False"

**Common messages and fixes:**

| Message | Fix |
|---------|-----|
| "Waiting for composed resources" | Check managed resources status |
| "Composing resources failed" | Check composition/function errors |
| "Cannot resolve references" | Ensure referenced resources exist |

## Quick Diagnostic Commands

```bash
# Full diagnostic for a claim
CLAIM_KIND=MyApp
CLAIM_NAME=my-app
NAMESPACE=default

echo "=== Claim Status ==="
kubectl get $CLAIM_KIND $CLAIM_NAME -n $NAMESPACE -o yaml | grep -A20 "status:"

echo "=== Resource Trace ==="
crossplane beta trace $CLAIM_KIND/$CLAIM_NAME -n $NAMESPACE

echo "=== Recent Events ==="
kubectl get events -n $NAMESPACE --field-selector involvedObject.name=$CLAIM_NAME --sort-by='.lastTimestamp' | tail -10

echo "=== Crossplane Logs ==="
kubectl logs -n crossplane-system deploy/crossplane --tail=20
```
