---
layout: default
title: How to Add DNS Records for EKS on AWS
---

# How to Add DNS Records for EKS on AWS (Route 53)

This guide explains how to configure DNS records in Amazon Route 53 for TIBCO Platform deployments on EKS. It covers three approaches: AWS CLI, the Route 53 Console, and automated management via External DNS.

**Last Updated**: June 11, 2026

---

## Table of Contents

- [Overview](#overview)
- [Environment Variables](#environment-variables)
- [Prerequisites](#prerequisites)
- [Option 1: AWS CLI](#option-1-aws-cli)
  - [Find the ALB DNS Name](#find-the-alb-dns-name)
  - [Create Alias Records via CLI](#create-alias-records-via-cli)
- [Option 2: AWS Route 53 Console](#option-2-aws-route-53-console)
- [Option 3: External DNS (Automated)](#option-3-external-dns-automated)
  - [How External DNS Works on EKS](#how-external-dns-works-on-eks)
  - [External DNS Installation](#external-dns-installation)
  - [Verify External DNS is Working](#verify-external-dns-is-working)
- [DNS Records Reference for TIBCO Platform](#dns-records-reference-for-tibco-platform)
- [Troubleshooting](#troubleshooting)

---

## Overview

TIBCO Platform on EKS uses Amazon Route 53 for DNS management. All TIBCO Platform domains (Control Plane and Data Plane) must resolve to the AWS ALB that the `aws-load-balancer-controller` creates.

The recommended approach is **Option 3: External DNS**, which automatically creates and manages Route 53 records based on Kubernetes Ingress annotations. This eliminates manual DNS management during repeated installs and cluster recreation.

For one-time setup or troubleshooting specific records, use the **AWS CLI (Option 1)** or **Route 53 Console (Option 2)**.

---

## Environment Variables

All environment variables for this guide are defined in [`scripts/env.sh`](../scripts/env.sh). Source it before running any commands:

```bash
source scripts/env.sh
```

The following variables are used in this guide:

| Variable | Default in env.sh | Description |
|:---------|:------------------|:------------|
| `AWS_REGION` | `us-west-2` | AWS region for all resources |
| `TP_HOSTED_ZONE_DOMAIN` | `aws.example.com` | Route 53 hosted zone domain (must be a domain you own) |
| `TP_DOMAIN` | `dp1.${TP_HOSTED_ZONE_DOMAIN}` | Primary Data Plane domain |
| `TP_APPS_DOMAIN` | `apps.dp1.${TP_HOSTED_ZONE_DOMAIN}` | Optional user app endpoint domain |
| `CP_INSTANCE_ID` | `cp1` | Unique ID for this CP installation |
| `TP_BASE_DNS_DOMAIN` | `${TP_HOSTED_ZONE_DOMAIN}` | Simplified Control Plane base domain for admin, subscriptions, and tunnel path |
| `CP_ADMIN_HOST_PREFIX` | `admin` | Platform Console hostname prefix |
| `CP_SUBSCRIPTION` | `dev` | Example subscription hostname prefix |
| `TP_MY_DOMAIN` | `${CP_INSTANCE_ID}-my.${TP_HOSTED_ZONE_DOMAIN}` | Legacy Control Plane application domain |
| `TP_TUNNEL_DOMAIN` | `${CP_INSTANCE_ID}-tunnel.${TP_HOSTED_ZONE_DOMAIN}` | Legacy Control Plane hybrid connectivity domain |
| `TP_MAIN_INGRESS_CONTROLLER` | `alb` | Ingress class used by External DNS annotation filter |

The following variables are **not** in `env.sh` because they are only known after the ALB is created:

| Variable | How to Obtain |
|:---------|:--------------|
| `TP_HOSTED_ZONE_ID` | `aws route53 list-hosted-zones` (see Prerequisites below) |
| `ALB_DNS_NAME` | `kubectl get ingress -n ingress-system nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` |
| `ALB_HOSTED_ZONE_ID` | From ALB describe output or the region table below |

---

## Prerequisites

**Why a Route 53 hosted zone:** Amazon Route 53 is the AWS-native DNS service. A **hosted zone** is a container for DNS records for a specific domain (e.g., `aws.example.com`). All TIBCO Platform subdomains are created as records within this zone. You must own this domain and have it registered in Route 53 — External DNS and the AWS CLI both need the hosted zone ID to create records.

- AWS CLI configured with appropriate permissions (`route53:ChangeResourceRecordSets`, `route53:ListHostedZones`, `route53:ListResourceRecordSets`)
- Amazon Route 53 hosted zone for your domain (e.g., `aws.example.com`)
- EKS cluster with ALB created by `aws-load-balancer-controller`

Retrieve your hosted zone ID before proceeding:

```bash
export TP_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${TP_HOSTED_ZONE_DOMAIN}.'].Id" \
  --output text | sed 's|/hostedzone/||')
echo "Hosted Zone ID: ${TP_HOSTED_ZONE_ID}"
```

> **Note:** The trailing dot in `${TP_HOSTED_ZONE_DOMAIN}.` is required by Route 53's API format for the list query.

---

## Option 1: AWS CLI

**Why use the CLI:** The CLI is suitable for one-time DNS setup, for environments where External DNS is not installed, or for debugging specific records. It uses Route 53 **Alias records** (type A) which point directly to an ALB without the need for a separate CNAME intermediate — alias records are free of charge for Route 53 queries and resolve at the AWS network layer.

### Find the ALB DNS Name

**Why alias records require two values:** Route 53 alias records for ALB require both the ALB's DNS name and its **Canonical Hosted Zone ID** — an AWS-internal zone ID specific to the ALB's region and type (distinct from your domain's hosted zone ID). This canonical zone ID allows Route 53 to detect ALB health and route traffic accordingly.

After deploying your ingress controller (Nginx or Traefik), retrieve the ALB DNS name:

```bash
# Get ALB DNS name from the Nginx ingress object
kubectl get ingress -n ingress-system nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Or list all ALBs in your account (DNS name + canonical hosted zone ID)
aws elbv2 describe-load-balancers \
  --region ${AWS_REGION} \
  --query 'LoadBalancers[*].[LoadBalancerName,DNSName,CanonicalHostedZoneId]' \
  --output table
```

Set the values you retrieved:

```bash
export ALB_DNS_NAME="k8s-ingresss-nginx-xxxx.us-west-2.elb.amazonaws.com"
export ALB_HOSTED_ZONE_ID="Z1H1FL5HABSF5"   # ALB canonical hosted zone ID (region-specific, see table below)
```

### Create Alias Records via CLI

**Why wildcard records (`*.domain`):** TIBCO Platform generates a unique subdomain for each capability it deploys. For example, `bwce.dp1.aws.example.com`, `flogo.dp1.aws.example.com`, `kibana.dp1.aws.example.com`. Rather than creating a separate DNS record for each capability, a single wildcard record (`*.dp1.aws.example.com`) matches all subdomains and points them all to the same ALB. Nginx or Traefik then routes each request to the correct service based on the `Host` header.

For current releases, create one wildcard alias record for the simplified Control Plane base domain:

```bash
# Create wildcard alias record for simplified Control Plane domain: *.aws.example.com
aws route53 change-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.'"${TP_BASE_DNS_DOMAIN}"'",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'"${ALB_HOSTED_ZONE_ID}"'",
          "DNSName": "'"${ALB_DNS_NAME}"'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

For legacy split-domain deployments, create separate records for `TP_MY_DOMAIN` and `TP_TUNNEL_DOMAIN`:

```bash
# Create wildcard alias record for legacy Control Plane application domain: *.cp1-my.aws.example.com
aws route53 change-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.'"${TP_MY_DOMAIN}"'",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'"${ALB_HOSTED_ZONE_ID}"'",
          "DNSName": "'"${ALB_DNS_NAME}"'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

```bash
# Create wildcard alias record for legacy Control Plane tunnel domain: *.cp1-tunnel.aws.example.com
aws route53 change-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.'"${TP_TUNNEL_DOMAIN}"'",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'"${ALB_HOSTED_ZONE_ID}"'",
          "DNSName": "'"${ALB_DNS_NAME}"'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

```bash
# Create wildcard alias record for Data Plane domain: *.dp1.aws.example.com
aws route53 change-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.'"${TP_DOMAIN}"'",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'"${ALB_HOSTED_ZONE_ID}"'",
          "DNSName": "'"${ALB_DNS_NAME}"'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

### ALB Canonical Hosted Zone IDs by Region

**Why this is region-specific:** AWS ALBs are regional services. Each region's ALB fleet has a separate canonical hosted zone ID that Route 53 uses internally. Using the wrong canonical zone ID will cause the alias record to fail validation.

| Region | Canonical Hosted Zone ID |
|:-------|:------------------------|
| us-east-1 | Z35SXDOTRQ7X7K |
| us-east-2 | Z3AADJGX6KTTL2 |
| us-west-1 | Z368ELLRRE2KJ0 |
| us-west-2 | Z1H1FL5HABSF5 |
| eu-west-1 | Z32O12XQLNTSW2 |
| eu-central-1 | Z215JYRZR1TBD5 |
| ap-southeast-1 | Z1LMS91P8KMBOT |
| ap-northeast-1 | Z14GRHDCWA56QT |

> For a complete list, see the [AWS documentation on ALB hosted zone IDs](https://docs.aws.amazon.com/general/latest/gr/elb.html).

> **Tip:** You can avoid looking up this value by retrieving it from the ALB describe output directly:
> ```bash
> aws elbv2 describe-load-balancers --region ${AWS_REGION} \
>   --query 'LoadBalancers[?contains(DNSName, `'"${ALB_DNS_NAME}"'`)].CanonicalHostedZoneId' \
>   --output text
> ```

### Verify Records

```bash
# Verify the record was created
aws route53 list-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --query "ResourceRecordSets[?Type=='A'].[Name]" \
  --output text

# Test DNS resolution (allow 1-2 minutes for propagation)
nslookup ${CP_ADMIN_HOST_PREFIX}.${TP_BASE_DNS_DOMAIN}
nslookup ${CP_SUBSCRIPTION}.${TP_BASE_DNS_DOMAIN}
dig *.${TP_DOMAIN}
```

---

## Option 2: AWS Route 53 Console

**Why use the Console:** The Console is the quickest way to create a small number of records interactively. It has a built-in ALB selector that automatically populates the canonical hosted zone ID, eliminating the need to look it up manually.

1. Open the [Route 53 Console](https://console.aws.amazon.com/route53/)
2. Navigate to **Hosted zones** and select your domain (e.g., `aws.example.com`)
3. Click **Create record**
4. Configure the record:
  - **Record name**: `*` or `*.platform` for simplified Control Plane DNS, or `*.dp1` for Data Plane
   - **Record type**: **A – Routes traffic to an IPv4 address and some AWS resources**
   - **Alias**: Toggle **ON**
   - **Route traffic to**: Select **Alias to Application and Classic Load Balancer**
   - **Region**: Select your AWS region
   - **Load balancer**: Select your ALB from the dropdown
5. Click **Create records**

Repeat for each wildcard domain needed. For new 1.18 deployments, the Control Plane normally needs one simplified wildcard record. Legacy split-domain deployments need separate CP my-domain and tunnel-domain records.

---

## Option 3: External DNS (Automated)

> **Source:** [`tp-helm-charts/docs/workshop/eks/data-plane/README.md`](https://github.com/TIBCOSoftware/tp-helm-charts/blob/main/docs/workshop/eks/data-plane/README.md)

**Why External DNS:** Manual DNS management (Options 1 and 2) requires updating Route 53 records every time the cluster is recreated or the ALB's DNS name changes. External DNS eliminates this by automatically synchronizing Route 53 records with the state of Kubernetes `Ingress` and `Service` objects. When a TIBCO capability creates an Ingress, External DNS creates the matching Route 53 record. When the Ingress is deleted, External DNS removes the record.

For workshop environments where clusters are frequently created and destroyed, External DNS is essential — without it you would have to manually update Route 53 after every cluster recreation.

### How External DNS Works on EKS

1. External DNS watches Kubernetes `Ingress` and `Service` objects across all namespaces
2. When an `Ingress` has the annotation `external-dns.alpha.kubernetes.io/hostname: "*.aws.example.com"`, External DNS creates an A alias record in Route 53 pointing to the ALB
3. The `--annotation-filter` flag restricts External DNS to only process `Ingress` objects that have the `kubernetes.io/ingress.class: alb` annotation, preventing it from accidentally managing non-ALB ingresses
4. When the `Ingress` is deleted, External DNS removes the Route 53 record

External DNS uses the IRSA `external-dns` service account created by the `eksctl` recipe. This service account has the `externalDNS` well-known IAM policy, which includes `route53:ChangeResourceRecordSets` and `route53:ListHostedZones` permissions for your hosted zone.

### External DNS Installation

**Why two configurations:** The Control Plane and Data Plane guides both install External DNS with slightly different configurations. For this guide (Data Plane only), the filter uses an annotation-based selector. Both configurations ultimately manage the same Route 53 hosted zone.

```bash
helm upgrade --install --wait --timeout 1h --create-namespace --reuse-values \
  -n external-dns-system external-dns external-dns \
  --labels layer=0 \
  --repo "https://kubernetes-sigs.github.io/external-dns" --version "1.15.2" -f - <<EOF
serviceAccount:
  create: false        # Pre-created by eksctl recipe with IRSA annotation
  name: external-dns
extraArgs:
  - "--annotation-filter=kubernetes.io/ingress.class=${TP_MAIN_INGRESS_CONTROLLER}"
EOF
```

### Triggering External DNS via Annotations

**Why annotations:** External DNS does not create records for all Ingress objects — only those that explicitly declare the `external-dns.alpha.kubernetes.io/hostname` annotation. This prevents External DNS from accidentally managing DNS for internal services. The `dp-config-aws` Helm chart applies these annotations automatically in the `httpIngress.annotations` section when you install Nginx, Traefik, or Kong.

Example: when you install the Nginx ingress controller via `dp-config-aws`, the chart creates this Ingress:

```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: "*.dp1.aws.example.com"
  kubernetes.io/ingress.class: alb
```

External DNS sees this annotation and creates a Route 53 record `*.dp1.aws.example.com → ALB` automatically.

### Verify External DNS is Working

```bash
# Watch External DNS logs for activity
kubectl logs -n external-dns-system deploy/external-dns -f
```

Expected log entries when a record is created:
```
time="..." level=info msg="Desired change: CREATE *.dp1.aws.example.com A [Id: /hostedzone/ZXXXXXXXXX]"
time="..." level=info msg="1 record(s) in zone aws.example.com. were successfully updated"
```

```bash
# Verify Route 53 records were created
aws route53 list-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --query "ResourceRecordSets[?Type=='A'].[Name]" \
  --output text
```

---

## DNS Records Reference for TIBCO Platform

| Record | Type | Target | Purpose |
|:-------|:-----|:-------|:--------|
| `*.${TP_BASE_DNS_DOMAIN}` | A (Alias) | ALB DNS name | Simplified Control Plane traffic: admin, subscriptions, APIs, and `/infra/tunnel` |
| `*.${TP_MY_DOMAIN}` | A (Alias) | ALB DNS name | Legacy Control Plane application traffic (CP UI, APIs) |
| `*.${TP_TUNNEL_DOMAIN}` | A (Alias) | ALB DNS name | Legacy Control Plane hybrid connectivity |
| `*.${TP_DOMAIN}` | A (Alias) | ALB DNS name | Data Plane services and capabilities (BWCE, Flogo, EMS, Kibana, Grafana) |
| `*.${TP_APPS_DOMAIN}` | A (Alias) | ALB DNS name | Data Plane user app endpoints via Kong (optional) |

> **Note on tunnel traffic:** With simplified DNS, tunnel traffic uses the same base domain and is routed by path under `/infra/tunnel`. The `*.${TP_TUNNEL_DOMAIN}` record is only needed for legacy split-domain deployments.

---

## Troubleshooting

### External DNS Not Creating Records

Check whether External DNS has the correct IRSA role and Route 53 permissions:

```bash
# Get the service account — should have an IRSA role ARN annotation
kubectl get serviceaccount -n external-dns-system external-dns -o yaml

# Expected annotation:
# eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/...

# Test Route 53 permissions from the External DNS pod
kubectl exec -n external-dns-system deploy/external-dns -- \
  aws route53 list-hosted-zones
```

If the AWS call fails, the IRSA role may not have been created correctly. Re-run the `eksctl` cluster creation or attach the Route 53 policy manually.

### DNS Record Points to Wrong ALB

External DNS may create records for multiple Ingresses if the annotation filter is too broad. Tighten the filter to a specific ALB group name:

```bash
extraArgs:
  - "--annotation-filter=alb.ingress.kubernetes.io/group.name=${TP_DOMAIN}"
```

### Record Created but DNS Not Resolving

Route 53 record propagation typically takes 30-60 seconds, but can take up to 2 minutes. Test with a specific public resolver:

```bash
# Test from outside using Google's public DNS resolver
nslookup ${CP_ADMIN_HOST_PREFIX}.${TP_BASE_DNS_DOMAIN} 8.8.8.8

# Or use dig with a short timeout
dig +short *.${TP_DOMAIN} @8.8.8.8
```

Check the TTL on the record — External DNS sets a short TTL by default (300s), which is appropriate for workshop environments:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --query "ResourceRecordSets[?Type=='A']"
```

### ALB Not Getting a DNS Name

**Why:** The ALB is created by the `aws-load-balancer-controller` when it processes the Ingress object. If the ALB DNS name is not appearing on the Ingress after 5 minutes, the controller may be misconfigured.

Check ALB provisioning status:

```bash
aws elbv2 describe-load-balancers \
  --region ${AWS_REGION} \
  --query 'LoadBalancers[*].[LoadBalancerName,State.Code,DNSName]' \
  --output table

# Check ALB controller logs for errors
kubectl logs -n kube-system deploy/aws-load-balancer-controller
```

Common causes:
- IRSA role missing `elasticloadbalancing:CreateLoadBalancer` permission
- Subnets not tagged correctly for ALB (`kubernetes.io/role/elb: 1` for public, `kubernetes.io/role/internal-elb: 1` for private)
- Ingress missing the `kubernetes.io/ingress.class: alb` annotation

---

## Additional Resources

- [Amazon Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
- [External DNS on AWS](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ALB Canonical Hosted Zone IDs](https://docs.aws.amazon.com/general/latest/gr/elb.html)
- [Route 53 Alias Records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html)
- [CP and DP Setup Guide](how-to-cp-and-dp-eks-setup-guide)
- [Prerequisites Checklist](prerequisites-checklist-for-customer)
