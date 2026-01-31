# KCL Patterns for Crossplane Compositions

## Table of Contents
- [Basic Structure](#basic-structure)
- [Reading Composite Resource](#reading-composite-resource)
- [Generating Resources](#generating-resources)
- [Conditional Logic](#conditional-logic)
- [Loops and Iterations](#loops-and-iterations)
- [Common Debugging Patterns](#common-debugging-patterns)

## Basic Structure

KCL in Crossplane compositions receives input via `option("params")`:

```python
# Import required schemas
import models.k8s.apimachinery.pkg.apis.meta.v1 as metav1

# Get the composite resource and observed state
oxr = option("params").oxr          # Observed XR (current state)
dxr = option("params").dxr          # Desired XR (to modify)
ocds = option("params").ocds        # Observed composed resources
dcds = option("params").dcds        # Desired composed resources (from previous functions)

# Output: list of resources to create/update
items = []
```

## Reading Composite Resource

### Access Spec Fields

```python
oxr = option("params").oxr

# Direct access
region = oxr.spec.region
name = oxr.spec.name

# With defaults (safe access)
region = oxr.spec.region or "us-east-1"
replicas = oxr.spec.replicas or 1

# Nested with defaults
config = oxr.spec.config or {}
timeout = config.timeout or 30
```

### Access Metadata

```python
oxr = option("params").oxr

xr_name = oxr.metadata.name
xr_namespace = oxr.metadata.namespace or "default"
labels = oxr.metadata.labels or {}
```

### Access Status

```python
oxr = option("params").oxr

# Check if resource has status
if oxr.status:
    ready = oxr.status.conditions
```

## Generating Resources

### Basic Resource Generation

```python
items = [
    {
        apiVersion = "s3.aws.upbound.io/v1beta1"
        kind = "Bucket"
        metadata = {
            name = "{}-bucket".format(oxr.metadata.name)
            annotations = {
                "crossplane.io/external-name" = oxr.spec.bucketName
            }
        }
        spec = {
            forProvider = {
                region = oxr.spec.region
            }
        }
    }
]
```

### Multiple Resources

```python
bucket = {
    apiVersion = "s3.aws.upbound.io/v1beta1"
    kind = "Bucket"
    metadata.name = "{}-bucket".format(oxr.metadata.name)
    spec.forProvider.region = oxr.spec.region
}

policy = {
    apiVersion = "s3.aws.upbound.io/v1beta1"
    kind = "BucketPolicy"
    metadata.name = "{}-policy".format(oxr.metadata.name)
    spec.forProvider = {
        bucketRef.name = bucket.metadata.name
        policy = oxr.spec.policy
    }
}

items = [bucket, policy]
```

### Setting Composed Resource Name (Required)

Every composed resource needs a unique name annotation:

```python
{
    metadata = {
        name = "{}-bucket".format(oxr.metadata.name)
        annotations = {
            "crossplane.io/composition-resource-name" = "my-bucket"
        }
    }
}
```

## Conditional Logic

### Simple Conditions

```python
items = []

if oxr.spec.enableLogging:
    items += [{
        apiVersion = "s3.aws.upbound.io/v1beta1"
        kind = "BucketLogging"
        metadata.name = "{}-logging".format(oxr.metadata.name)
        spec.forProvider.bucket = oxr.spec.bucketName
    }]
```

### Ternary Expressions

```python
storage_class = "STANDARD" if oxr.spec.tier == "premium" else "STANDARD_IA"

replicas = 3 if oxr.spec.highAvailability else 1
```

### Multiple Conditions

```python
items = []

# Base resource always created
items += [base_bucket]

# Optional resources
if oxr.spec.enableVersioning:
    items += [versioning_config]

if oxr.spec.enableEncryption:
    items += [encryption_config]

if oxr.spec.enableReplication and oxr.spec.replicationRegion:
    items += [replication_config]
```

## Loops and Iterations

### Generate Multiple Similar Resources

```python
regions = oxr.spec.regions or ["us-east-1"]

buckets = [
    {
        apiVersion = "s3.aws.upbound.io/v1beta1"
        kind = "Bucket"
        metadata = {
            name = "{}-bucket-{}".format(oxr.metadata.name, region)
            annotations = {
                "crossplane.io/composition-resource-name" = "bucket-{}".format(region)
            }
        }
        spec.forProvider.region = region
    }
    for region in regions
]

items = buckets
```

### Enumerate with Index

```python
subnets = [
    {
        apiVersion = "ec2.aws.upbound.io/v1beta1"
        kind = "Subnet"
        metadata.name = "{}-subnet-{}".format(oxr.metadata.name, i)
        spec.forProvider = {
            cidrBlock = cidr
            availabilityZone = oxr.spec.azs[i % len(oxr.spec.azs)]
        }
    }
    for i, cidr in enumerate(oxr.spec.subnetCidrs or [])
]
```

### Filter and Transform

```python
# Filter items
enabled_features = [f for f in oxr.spec.features if f.enabled]

# Transform items
resource_names = ["{}-{}".format(oxr.metadata.name, f.name) for f in enabled_features]
```

## Common Debugging Patterns

### Print Debug Output

KCL doesn't have print, but you can add debug info to resource annotations:

```python
{
    metadata.annotations = {
        "debug/oxr-spec" = str(oxr.spec)
        "debug/computed-value" = str(some_value)
    }
}
```

### Validate Required Fields

```python
# Assert required fields exist
assert oxr.spec.region, "spec.region is required"
assert oxr.spec.name, "spec.name is required"

# Provide clear error messages
if not oxr.spec.bucketName:
    assert False, "spec.bucketName must be provided"
```

### Check Observed Composed Resources

```python
ocds = option("params").ocds

# Check if a specific resource exists and is ready
bucket_ready = False
if "my-bucket" in ocds:
    bucket = ocds["my-bucket"]
    if bucket.Resource.status:
        for cond in (bucket.Resource.status.conditions or []):
            if cond.type == "Ready" and cond.status == "True":
                bucket_ready = True
```

### Reference Previous Function Output

```python
dcds = option("params").dcds

# Get resource created by previous function in pipeline
if "previous-resource" in dcds:
    prev = dcds["previous-resource"]
    # Use values from previous resource
```

### Safe Nested Access Pattern

```python
# Unsafe - will fail if intermediate is None
# value = oxr.spec.nested.deeply.value

# Safe pattern
spec = oxr.spec or {}
nested = spec.nested or {}
deeply = nested.deeply or {}
value = deeply.value or "default"

# Or use helper
_get = lambda obj, path, default: (
    default if not obj else
    obj.get(path[0], default) if len(path) == 1 else
    _get(obj.get(path[0], {}), path[1:], default)
)
```

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `NoneType has no attribute` | Accessing field on None | Use `or {}` / `or []` defaults |
| `KeyError` | Missing dict key | Use `.get()` or check key exists |
| `name must be unique` | Duplicate resource names | Ensure unique composition-resource-name |
| `invalid character` | YAML/JSON syntax in KCL | Check string quoting and escaping |
| `undefined variable` | Typo or missing import | Check variable names and imports |
