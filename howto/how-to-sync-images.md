---
layout: default
title: How to Push TIBCO Platform Images to a Custom Container Registry
---

# How to Push TIBCO Platform Images to a Custom Container Registry

When deploying TIBCO Platform in environments where EKS cluster nodes cannot reach the TIBCO JFrog registry directly — such as corporate firewalled environments, regulated environments requiring private registry policies, or air-gapped deployments — you must first mirror the required container images to an accessible internal registry before running the Helm install.

This guide covers the official TIBCO synchronization script, safe copy methods for each environment type, BusinessWorks plugin image requirements, and a verification and remediation runbook.

> **Official sync script**: [TIBCOSoftware/tp-helm-charts — sync-artifacts](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/scripts/sync-artifacts)  
> **See also**: If BW plugin extraction jobs fail after pushing images, see the [Troubleshooting Guide](./troubleshooting) for diagnosis steps and remediation.

---

## Prerequisites

### Tools

| Tool | Purpose | Required For |
|------|---------|-------------|
| `docker` + `buildx` plugin | Bit-perfect manifest copy | `sync-images.sh` and `imagetools` |
| `skopeo` | Bit-perfect registry-to-registry copy | Podman or skopeo-only environments |
| `aws` CLI | ECR authentication | Amazon ECR target registries |
| `helm` 3.17+ | Chart sync (optional) | `sync-charts.sh` |

### Credentials

- [ ] TIBCO JFrog registry credentials (provided by TIBCO): `csgprduswrepoedge.jfrog.io`
- [ ] AWS IAM credentials with `ecr:GetAuthorizationToken` and push permissions to the target ECR repository
- [ ] `RELEASE_VERSION` — the TIBCO Platform version being deployed (e.g., `1.18.0`)

### Clone the TIBCO tp-helm-charts Repository

The sync script and image lists live in the tp-helm-charts repository:

```bash
git clone https://github.com/TIBCOSoftware/tp-helm-charts.git
cd tp-helm-charts/scripts/sync-artifacts
```

---

## The Official TIBCO sync-images.sh Script

TIBCO provides an official synchronization script at [`scripts/sync-artifacts/sync-images.sh`](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/scripts/sync-artifacts).

**This is the recommended method.** The script uses `docker buildx imagetools create` internally, which performs a bit-perfect registry-to-registry copy — images are never pulled or re-compressed locally. This is safe for all image types including BusinessWorks plugins.

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SOURCE_REGISTRY` | TIBCO JFrog source registry | `csgprduswrepoedge.jfrog.io` |
| `SOURCE_REGISTRY_USERNAME` | JFrog username | `john.doe@company.com` |
| `SOURCE_REGISTRY_PASSWORD` | JFrog password or API token | `AKCp8...` |
| `RELEASE_VERSION` | Platform version (`major.minor.patch`) | `1.18.0` |
| `TARGET_REGISTRY` | Your ECR registry URL | `123456789012.dkr.ecr.us-east-1.amazonaws.com` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_REGISTRY_USERNAME` | — | Target registry username (`AWS` for ECR) |
| `TARGET_REGISTRY_PASSWORD` | — | Target registry password (ECR auth token) |
| `TARGET_REGISTRY_REPO` | — | Target repository path override |
| `CAPABILITY_NAME` | _(all)_ | Sync only a specific capability (e.g., `bwce`) |
| `MAX_RETRY` | `0` | Retry count for failed copy operations |
| `WAIT_BEFORE_RETRY` | `0` | Seconds between retries |
| `WRITE_SCRIPT_LOGS_TO_FILE` | `false` | Write logs to `image_sync_<timestamp>.log` |

### Usage

```bash
# Get an ECR auth token
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)

export SOURCE_REGISTRY="csgprduswrepoedge.jfrog.io"
export SOURCE_REGISTRY_USERNAME="john.doe@company.com"
export SOURCE_REGISTRY_PASSWORD="AKCp8mnyYZQ..."
export RELEASE_VERSION="1.18.0"
export TARGET_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"
export TARGET_REGISTRY_USERNAME="AWS"
export TARGET_REGISTRY_PASSWORD="$ECR_TOKEN"

cd tp-helm-charts/scripts/sync-artifacts
./sync-images.sh
```

The script reads image lists from `../../artifacts/*-${RELEASE_VERSION}-images.txt` and copies each image directly between registries without touching local disk.

---

## ⚠️ Critical: BusinessWorks Plugin Images Require Bit-Perfect Copying

> **Do not use `docker push`, `podman push`, `docker save`, or `podman save` to transfer BusinessWorks plugin images.** These commands silently re-compress image layers and cause extraction jobs to fail during BW capability deployment.

### What Breaks

When using standard push/save commands, the container engine decompresses and re-compresses image layers locally. For BusinessWorks plugin images (which contain nested Java archives), this changes the internal GZIP DEFLATE block type:

| Block Type | Bytes 10–11 | Extraction Result |
|-----------|-------------|------------------|
| `BTYPE=01` Fixed Huffman — original TIBCO layer | `ecf2` | ✅ Succeeds |
| `BTYPE=00` Stored block — re-compressed by push | `00ff` | ❌ `tar: invalid tar header checksum` |

The `busybox tar` binary inside the `bwce-utilities` extraction container cannot handle `BTYPE=00` stored blocks.

### What to Use Instead

Any of the safe methods below perform registry-to-registry copies that stream raw layer blobs without local re-compression, preserving the original `BTYPE=01` headers.

---

## Safe Image Copy Methods

### Method 1 — sync-images.sh (Recommended)

See [the previous section](#the-official-tibco-sync-imagessh-script). The official script handles all images at once with retry logic and logging.

---

### Method 2 — docker buildx imagetools (Manual, per-image)

Use this for copying individual images or when the full sync script is not needed.

```bash
# Log in to the TIBCO JFrog source registry
docker login csgprduswrepoedge.jfrog.io \
  --username john.doe@company.com --password AKCp8mnyYZQ...

# Log in to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com

# Copy directly — no local disk use
docker buildx imagetools create \
  --tag 123456789012.dkr.ecr.us-east-1.amazonaws.com/tibco-platform/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0 \
  csgprduswrepoedge.jfrog.io/tibco-platform-docker-prod/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0
```

---

### Method 3 — skopeo copy (Podman or skopeo-only environments)

`skopeo` streams raw binary chunks directly between registries without local decompression. Use `--format v2s2` to preserve the Docker V2 Schema 2 layer structure.

```bash
# Log in to source registry
skopeo login csgprduswrepoedge.jfrog.io \
  --username john.doe@company.com --password AKCp8mnyYZQ...

# Log in to ECR — skopeo accepts the same token as docker
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)
skopeo login 123456789012.dkr.ecr.us-east-1.amazonaws.com \
  --username AWS --password "$ECR_TOKEN"

# Copy a single image
skopeo copy --format v2s2 \
  docker://csgprduswrepoedge.jfrog.io/tibco-platform-docker-prod/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0 \
  docker://123456789012.dkr.ecr.us-east-1.amazonaws.com/tibco-platform/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0
```

---

### Method 4 — skopeo dir:// (Air-Gapped / No Direct Connectivity)

Use this when the EKS cluster and the TIBCO JFrog registry have no shared network path and images must be physically transported across an air-gap.

> **Do not use `docker save` / `podman save` for this.** Always use `skopeo copy dir://` which preserves raw layer blobs.

**On the internet-connected machine:**

```bash
# Dump raw blobs to a staging directory (preserves original GZIP headers)
skopeo copy \
  docker://csgprduswrepoedge.jfrog.io/tibco-platform-docker-prod/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0 \
  dir:/tmp/staging/tci-bw-plugin-cics

# Archive the staging directory
tar -cvf tibco-bw-plugins.tar -C /tmp/staging tci-bw-plugin-cics

# [Transfer the archive across the air-gap]
```

**On the target machine (inside the secure network):**

```bash
tar -xvf tibco-bw-plugins.tar -C /tmp/staging

# --force overwrites cached blobs; --preserve-digests forces the registry to write
# original upstream blobs exactly (prevents re-compression of BW plugin layers)
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)
skopeo login 123456789012.dkr.ecr.us-east-1.amazonaws.com \
  --username AWS --password "$ECR_TOKEN"

skopeo copy --force --preserve-digests --format v2s2 \
  dir:/tmp/staging/tci-bw-plugin-cics \
  docker://123456789012.dkr.ecr.us-east-1.amazonaws.com/tibco-platform/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0
```

---

### Method Comparison

| Method | Tooling | Best For | Bit-Perfect |
|--------|---------|----------|-------------|
| `sync-images.sh` | Docker + buildx | All images at once, recommended path | ✅ Yes |
| `docker buildx imagetools` | Docker + buildx | Manual per-image copy | ✅ Yes |
| `skopeo copy` | skopeo | Scripted copy, Podman environments | ✅ Yes |
| `skopeo dir://` | skopeo | Air-gapped / physical data transfer | ✅ Yes |
| `docker push` / `podman push` | Any | ❌ Avoid for BW plugin images | ❌ No |

---

## Amazon ECR Setup

### Create ECR Repositories

ECR requires a repository to exist before you can push to it. Create one per image or use a shared prefix:

```bash
# Create a repository for a BW plugin image
aws ecr create-repository \
  --repository-name tibco-platform/tci-bw-plugin-cics \
  --region us-east-1

# Or create all required repositories from a list
for IMAGE in tci-bw-plugin-cics tci-bw-plugin-as2 tci-bw-plugin-ap; do
  aws ecr create-repository \
    --repository-name tibco-platform/$IMAGE \
    --region us-east-1
done
```

### Authenticate to ECR

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com
```

### Create the Kubernetes Image Pull Secret

```bash
# Generate an ECR auth token
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)

kubectl create secret docker-registry tibco-container-registry-credentials \
  --docker-server=123456789012.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$ECR_TOKEN" \
  --docker-email=platform-team@company.com \
  -n <CP_INSTANCE_ID>-ns
```

> **Note**: ECR auth tokens expire after 12 hours. For production, use an IRSA-enabled service account or a token refresh mechanism instead of a static secret.

---

## Verify Image Integrity

After pushing images, verify that BusinessWorks plugin layer headers are intact before running the Helm install.

```bash
AWS_REGION="us-east-1"
ACCOUNT="123456789012"
REGISTRY="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
REPO="tibco-platform"
IMAGE="tci-bw-plugin-cics"
TAG="2.5.0.v4.3-tci-2.0"

# Get an ECR Bearer token
TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

# Get the first layer digest
DIGEST=$(curl -s \
  -H "Authorization: Basic $(echo -n "AWS:$TOKEN" | base64)" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://$REGISTRY/v2/$REPO/$IMAGE/manifests/$TAG" \
  | jq -r '.layers[0].digest')

# Download and inspect the layer blob
curl -s \
  -H "Authorization: Basic $(echo -n "AWS:$TOKEN" | base64)" \
  "https://$REGISTRY/v2/$REPO/$IMAGE/blobs/$DIGEST" \
  -o /tmp/check_header.tar.gz

xxd /tmp/check_header.tar.gz | head -1
```

**Expected output (intact image):**
```
00000000: 1f8b 0800 0000 0000 00ff ecf2 638c 2f40 ...
```

Bytes 10–11 should read `ecf2` (BTYPE=01 Fixed Huffman). If you see `00ff` (BTYPE=00 Stored), re-mirror the image using a bit-perfect method before proceeding with the Helm install.

---

## Runbook: Fix an Already-Corrupted Registry

If images were previously pushed using standard push commands and ECR has cached corrupted layers, a new push will be skipped (`already exists`). Force-overwrite with `--force`.

### Step 1 — Re-push with --force

```bash
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)
skopeo login 123456789012.dkr.ecr.us-east-1.amazonaws.com \
  --username AWS --password "$ECR_TOKEN"

skopeo copy --force --format v2s2 \
  docker://csgprduswrepoedge.jfrog.io/tibco-platform-docker-prod/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0 \
  docker://123456789012.dkr.ecr.us-east-1.amazonaws.com/tibco-platform/tci-bw-plugin-cics:2.5.0.v4.3-tci-2.0
```

### Step 2 — Delete Broken Extraction Job Pods

```bash
kubectl delete jobs -n <CP_INSTANCE_ID>-ns \
  --selector=app.kubernetes.io/component=bwce-utilities
```

### Step 3 — Verify Header Integrity

Run the verification commands above and confirm `ecf2` is present in bytes 10–11.

### Step 4 — Retry the Helm Install

The extraction jobs will now find intact images and complete successfully.

---

## Production Air-Gap Scripts (Validated Download + Upload)

For proxy-segmented environments where the JFrog source and the ECR target have no shared network path, use the following two-script workflow. Both scripts include integrity validation using `skopeo inspect` layer size comparison, validated in production air-gapped deployments.

**Why `--preserve-digests` matters:** Without this flag, the target registry may reassign layer checksums internally during upload, allowing re-compression that corrupts BW plugin GZIP headers (the `BTYPE=00` failure mode). The `--preserve-digests` flag forces the registry API to write the original upstream blobs exactly as-is.

### Script 1 — Download and Validate (Proxy ON)

Run on the internet-connected jump server. Downloads each image as a `dir://` staging directory, validates local byte sizes against the JFrog baseline, then archives for transport.

```bash
#!/bin/bash
LOG_FILE="DownloadAndVerify_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

SRC_CREDS="<jfrog-username>:<jfrog-api-token>"
SOURCE_REGISTRY="csgprduswrepoedge.jfrog.io/tibco-platform-docker-prod"
LOCAL_ARCHIVE_DIR="/transfer/tibco-images"

IMAGES=(
  "tci-bw-plugin-ap:5.0.0.v11.2-tci-2.0"
  "tci-bw-plugin-kafka:5.0.1.v13.1-tci-2.0"
  "tci-bw-plugin-pdf:1.0.0.v12.3-tci-2.0"
  "tci-bw-plugin-salesforce:2.6.0.v26-tci-2.0"
  "tci-bw-plugin-sharepoint:1.1.0.v19-tci-2.0"
  "tci-bw-plugin-sp:1.1.1.v3-tci-2.0"
  "tci-bw-plugin-cassandra:6.3.3.v12-tci-2.0"
  "infra-container-image-extractor:170-distroless"
  "common-distroless-base-debian-debug:13.3"
)

mkdir -p "${LOCAL_ARCHIVE_DIR}" /tmp/skopeo_scratch

for IMAGE in "${IMAGES[@]}"; do
    NAME=$(echo "$IMAGE" | cut -d':' -f1)
    TAG=$(echo "$IMAGE" | cut -d':' -f2)
    SAFE_NAME="${NAME}-${TAG}"

    echo "=== Processing: ${IMAGE} ==="

    JFROG_SIZE=$(skopeo inspect --creds "${SRC_CREDS}" \
      docker://${SOURCE_REGISTRY}/${IMAGE} | jq '[.LayersData[].Size] | add')

    rm -rf "/tmp/skopeo_scratch/${SAFE_NAME}"
    mkdir -p "/tmp/skopeo_scratch/${SAFE_NAME}"

    if skopeo copy --src-creds "${SRC_CREDS}" \
      docker://${SOURCE_REGISTRY}/${IMAGE} \
      dir:///tmp/skopeo_scratch/${SAFE_NAME}; then

        LOCAL_SIZE=$(find /tmp/skopeo_scratch/${SAFE_NAME} -type f \
          -not -name "manifest.json" -not -name "version" \
          -exec stat -c%s {} + | awk '{s+=$1} END {print s}')

        if [ "${JFROG_SIZE}" -eq "${LOCAL_SIZE}" ]; then
            echo "INTEGRITY CHECK PASSED: ${SAFE_NAME} — JFrog (${JFROG_SIZE}) == Local (${LOCAL_SIZE})"
            tar -cf "${LOCAL_ARCHIVE_DIR}/${SAFE_NAME}.tar" \
              -C /tmp/skopeo_scratch "${SAFE_NAME}"
        else
            echo "ERROR: Size mismatch — JFrog: ${JFROG_SIZE}, Local: ${LOCAL_SIZE}. Skipping archive."
        fi
    fi
    rm -rf "/tmp/skopeo_scratch/${SAFE_NAME}"
done

rm -rf /tmp/skopeo_scratch
echo "=== Done. Transfer ${LOCAL_ARCHIVE_DIR} to the target jump server. ==="
```

Transfer the archive directory across the air-gap to the target-side jump server.

### Script 2 — Upload and Post-Verify (Proxy OFF, ECR Target)

Run on the target-side jump server inside the secure network. Extracts archives, pushes with `--preserve-digests`, and post-verifies that ECR layer sizes match the local baseline.

```bash
#!/bin/bash
LOG_FILE="UploadAndVerify_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

TARGET_REGISTRY="<account-id>.dkr.ecr.<region>.amazonaws.com"
REPO="tibco-platform"
ARCHIVE_DIR="/transfer/tibco-images"
TMP_DIR="/tmp/skopeo-upload"
AWS_REGION="<region>"

IMAGES=(
  "tci-bw-plugin-ap:5.0.0.v11.2-tci-2.0"
  "tci-bw-plugin-kafka:5.0.1.v13.1-tci-2.0"
  "tci-bw-plugin-pdf:1.0.0.v12.3-tci-2.0"
  "tci-bw-plugin-salesforce:2.6.0.v26-tci-2.0"
  "tci-bw-plugin-sharepoint:1.1.0.v19-tci-2.0"
  "tci-bw-plugin-sp:1.1.1.v3-tci-2.0"
  "tci-bw-plugin-cassandra:6.3.3.v12-tci-2.0"
  "infra-container-image-extractor:170-distroless"
  "common-distroless-base-debian-debug:13.3"
)

ECR_TOKEN=$(aws ecr get-login-password --region "${AWS_REGION}")
skopeo login "${TARGET_REGISTRY}" --username AWS --password "${ECR_TOKEN}"

mkdir -p "${TMP_DIR}"

for IMAGE in "${IMAGES[@]}"; do
    NAME=$(echo "$IMAGE" | cut -d':' -f1)
    TAG=$(echo "$IMAGE" | cut -d':' -f2)
    SAFE_NAME="${NAME}-${TAG}"
    TAR_FILE="${ARCHIVE_DIR}/${SAFE_NAME}.tar"
    WORK_DIR="${TMP_DIR}/${SAFE_NAME}"

    echo "=== Uploading: ${IMAGE} ==="

    [ ! -f "${TAR_FILE}" ] && echo "ERROR: Archive not found: ${TAR_FILE}" && continue

    rm -rf "${WORK_DIR}" && mkdir -p "${WORK_DIR}"
    tar -xf "${TAR_FILE}" -C "${WORK_DIR}"

    IMAGE_DIR=$(find "${WORK_DIR}" -maxdepth 2 -type f \
      \( -name "oci-layout" -o -name "manifest.json" \) | head -1 | xargs -r dirname)
    [ -z "${IMAGE_DIR}" ] && echo "ERROR: Cannot locate image dir in ${WORK_DIR}" && continue

    LOCAL_SUM=$(find "${IMAGE_DIR}" -type f \
      -not -name "manifest.json" -not -name "version" \
      -exec stat -c%s {} + | awk '{s+=$1} END {print s}')

    if skopeo copy --preserve-digests --format v2s2 \
      dir://"${IMAGE_DIR}" \
      docker://${TARGET_REGISTRY}/${REPO}/${NAME}:${TAG}; then

        sleep 2
        REMOTE_SUM=$(skopeo inspect \
          docker://${TARGET_REGISTRY}/${REPO}/${NAME}:${TAG} \
          | jq '[.LayersData[].Size] | add')

        if [ "${LOCAL_SUM}" -eq "${REMOTE_SUM}" ]; then
            echo "VERIFICATION PASSED: ${NAME}:${TAG} — Registry (${REMOTE_SUM}) matches local."
        else
            echo "WARNING: Size mismatch — expected ${LOCAL_SUM}, registry reports ${REMOTE_SUM}"
        fi
    fi
    rm -rf "${WORK_DIR}"
done

rm -rf "${TMP_DIR}"
echo "=== Upload and post-verification complete. ==="
```

---

## Additional Resources

- [TIBCOSoftware/tp-helm-charts — sync-artifacts](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/scripts/sync-artifacts)
- [TIBCO Platform — Pushing Images to Custom Container Registry](https://docs.tibco.com/pub/platform-cp/latest/doc/html/UserGuide/pushing-images-to-registry.htm)
- [Customer Prerequisites Checklist](./prerequisites-checklist-for-customer)
- [EKS Firewall Requirements](../docs/firewall-requirements-eks)
- [skopeo documentation](https://github.com/containers/skopeo)
- [docker buildx imagetools](https://docs.docker.com/engine/reference/commandline/buildx_imagetools/)
- [Amazon ECR User Guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)
- [Authenticating to Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
