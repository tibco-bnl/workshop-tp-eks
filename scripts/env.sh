#!/bin/bash
# =============================================================================
# TIBCO Platform on EKS - Environment Variables
#
# Usage:
#   source scripts/env.sh
#
# This file defines ALL environment variables used across the workshop guides.
# Customize the values for your environment before sourcing.
#
# Variable prefix convention:
#   TP_   = TIBCO Platform (shared across CP and DP)
#   CP_   = Control Plane specific
#   DP_   = Data Plane specific
#   AWS_  = AWS CLI / SDK built-in variables
# =============================================================================


# =============================================================================
# SECTION 1: AWS CONFIGURATION
# =============================================================================
# These variables configure the AWS CLI and identify your target region.
# AWS_PAGER="" disables the interactive pager for non-interactive use.
# Reference: https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-output-format.html

export AWS_PAGER=""
export AWS_REGION="us-west-2"               # AWS region for all resources
export TP_CLUSTER_REGION="${AWS_REGION}"     # Alias used throughout workshop scripts


# =============================================================================
# SECTION 2: EKS CLUSTER CONFIGURATION
# =============================================================================
# These variables define the shape of the EKS cluster created by eksctl.
# Reference: https://eksctl.io/usage/creating-and-managing-clusters/
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

export TP_CLUSTER_NAME="eks-cluster-${TP_CLUSTER_REGION}"   # EKS cluster name; used in kubeconfig and Helm chart values
export TP_KUBERNETES_VERSION="1.33"                          # Kubernetes version; use 1.33 or above
export TP_NODEGROUP_INSTANCE_TYPE="m5a.xlarge"               # EC2 instance type: 4 vCPU / 16 GB RAM per node
export TP_NODEGROUP_INITIAL_COUNT=3                          # Number of nodes; 3 provides basic HA across AZs
export TP_VPC_CIDR="10.180.0.0/16"                          # VPC CIDR for the EKS cluster; must not overlap with other VPCs
export TP_SERVICE_CIDR="172.20.0.0/16"                      # Kubernetes service (ClusterIP) address range; must not overlap with VPC CIDR
export KUBECONFIG="$(pwd)/${TP_CLUSTER_NAME}.yaml"           # Path to kubeconfig file; set per cluster to avoid conflicts


# =============================================================================
# SECTION 3: HELM REPOSITORY
# =============================================================================
# The TIBCO Platform official Helm chart repository.
# All dp-config-aws, dp-config-es, tibco-cp-base charts are published here.
# Reference: https://github.com/TIBCOSoftware/tp-helm-charts

export TP_TIBCO_HELM_CHART_REPO="https://tibcosoftware.github.io/tp-helm-charts"


# =============================================================================
# SECTION 4: NETWORK POLICY
# =============================================================================
# VPC CNI supports Kubernetes NetworkPolicy resources starting with EKS 1.25+.
# Set to "true" to enable NetworkPolicy enforcement at the VPC CNI level.
# This replaces the previous Calico-based network policy approach.
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html

export TP_ENABLE_NETWORK_POLICY="true"


# =============================================================================
# SECTION 5: DOMAIN AND DNS
# =============================================================================
# Route 53 hosted zone domain — must be a domain you own and have registered
# in Route 53. External DNS will manage records within this zone.
# Reference: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html
#
# Control Plane domains follow the pattern:
#   TP_MY_DOMAIN     = ${CP_INSTANCE_ID}-my.${TP_HOSTED_ZONE_DOMAIN}
#   TP_TUNNEL_DOMAIN = ${CP_INSTANCE_ID}-tunnel.${TP_HOSTED_ZONE_DOMAIN}
#
# Data Plane domain follows the pattern:
#   TP_DOMAIN = dp1.${TP_HOSTED_ZONE_DOMAIN}

export TP_HOSTED_ZONE_DOMAIN="aws.example.com"               # Replace with your Route 53 hosted zone domain

# Control Plane domains (derived; set after CP_INSTANCE_ID is set below)
# export TP_MY_DOMAIN="${CP_INSTANCE_ID}-my.${TP_HOSTED_ZONE_DOMAIN}"
# export TP_TUNNEL_DOMAIN="${CP_INSTANCE_ID}-tunnel.${TP_HOSTED_ZONE_DOMAIN}"

# Data Plane domains
export TP_DOMAIN="dp1.${TP_HOSTED_ZONE_DOMAIN}"              # Primary DP domain for services and capabilities
export TP_APPS_DOMAIN="apps.dp1.${TP_HOSTED_ZONE_DOMAIN}"   # Optional: separate domain for user app endpoints (Kong)

# Route 53 hosted zone ID (auto-derived; or set manually if you have multiple zones)
# Uncomment to set manually:
# export TP_HOSTED_ZONE_ID="Z1234567890ABC"
# Or auto-derive with:
# export TP_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
#   --query "HostedZones[?Name=='${TP_HOSTED_ZONE_DOMAIN}.'].Id" \
#   --output text | sed 's|/hostedzone/||')


# =============================================================================
# SECTION 6: INGRESS CONFIGURATION
# =============================================================================
# TP_MAIN_INGRESS_CONTROLLER = "alb" — the AWS ALB ingress class created by
#   aws-load-balancer-controller. Used by External DNS annotation filter.
# TP_INGRESS_CONTROLLER = the Kubernetes ingress class that TIBCO CP/DP uses
#   internally. Can be "nginx", "traefik", or "alb" (if using ALB directly).
# TP_INGRESS_CLASS = same as TP_INGRESS_CONTROLLER; used in DP-specific guides.
# Reference: https://kubernetes-sigs.github.io/aws-load-balancer-controller/

export TP_MAIN_INGRESS_CONTROLLER="alb"      # AWS ALB ingress class (always "alb")
export TP_INGRESS_CONTROLLER="nginx"         # Kubernetes ingress class for CP (nginx or traefik)
export TP_INGRESS_CLASS="nginx"              # Kubernetes ingress class for DP (nginx or traefik)


# =============================================================================
# SECTION 7: STORAGE CONFIGURATION
# =============================================================================
# EFS (Elastic File System) provides ReadWriteMany (RWX) persistent storage.
# Required for:
#   - TIBCO Control Plane shared storage
#   - BWCE artifact manager (ReadWriteMany required)
#   - EMS log storage
#
# EBS (Elastic Block Store) gp3 provides ReadWriteOnce (RWO) block storage.
# Required for:
#   - EMS capability data storage
#   - Elasticsearch data storage (observability)
#
# Reference: https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html
# Reference: https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html

export TP_STORAGE_CLASS_EFS="efs-sc"         # EFS storage class name (created by dp-config-aws chart or manually)
export TP_EFS_ENABLED=true                   # Enable EFS storage class creation in dp-config-aws
export TP_EBS_ENABLED=true                   # Enable EBS gp3 storage class creation in dp-config-aws
export TP_STORAGE_CLASS="ebs-gp3"           # EBS gp3 storage class name (for EMS, Elasticsearch)

# EFS file system IDs (set after EFS is created by script or Crossplane)
# The create-efs-control-plane.sh and create-efs-data-plane.sh helper scripts
# are maintained upstream at:
# https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks/scripts
# export TP_EFS_ID="fs-0xxxxxxxxxxxxxxxxx"   # EFS ID for CP or DP (replace after creation)


# =============================================================================
# SECTION 8: CONTAINER REGISTRY
# =============================================================================
# TIBCO Platform images are hosted on JFrog Artifactory.
# The registry URL varies by region — use the edge node closest to your cluster.
# Credentials are provided by TIBCO as part of your platform subscription.
# Reference: https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm#UserGuide/pushing-images-to-registry.htm
#
# Common JFrog edge node URLs by region:
#   us-west-2:  csgprduswrepoedge.jfrog.io
#   us-east-1:  csgprduserepoedge.jfrog.io
#   eu-west-1:  csgprdeuwrepoedge.jfrog.io

export TP_CONTAINER_REGISTRY_URL="csgprduswrepoedge.jfrog.io"  # Replace with your region's edge node
export TP_CONTAINER_REGISTRY_USER=""                            # JFrog username (from TIBCO)
export TP_CONTAINER_REGISTRY_PASSWORD=""                        # JFrog password / API key (from TIBCO)


# =============================================================================
# SECTION 9: CONTROL PLANE CONFIGURATION
# =============================================================================
# CP_INSTANCE_ID identifies a specific CP installation within a cluster.
# Multiple CP instances can coexist in the same cluster using different IDs.
# - Max 5 alphanumeric characters
# - Used as namespace prefix: ${CP_INSTANCE_ID}-ns
# - Used as service account name: ${CP_INSTANCE_ID}-sa
# Reference: https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm#Installation/deploying-control-plane-in-kubernetes.htm

export CP_INSTANCE_ID="cp1"                  # Unique ID for this CP installation (max 5 alphanumeric chars)

# =============================================================================
# CONTROL PLANE DNS — Choose ONE approach and uncomment the relevant block
# =============================================================================

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ OPTION 1: Simplified DNS Structure (RECOMMENDED for v1.17.0+)              │
# │ Single base domain — admin, subscription, and tunnel share one domain       │
# │ One wildcard ACM certificate covers all CP subdomains                       │
# │ Simpler setup: fewer certs, fewer DNS records, lower resource usage         │
# └─────────────────────────────────────────────────────────────────────────────┘
# Results in:
#   Admin UI      : https://admin.${TP_HOSTED_ZONE_DOMAIN}
#   Subscription  : https://dev.${TP_HOSTED_ZONE_DOMAIN}
#   Tunnel        : shared domain path /infra/tunnel (if hybrid enabled)
#   ACM cert      : *.${TP_HOSTED_ZONE_DOMAIN}  (single wildcard)

export TP_BASE_DNS_DOMAIN="${TP_HOSTED_ZONE_DOMAIN}"  # Base domain for all CP services
export CP_ADMIN_HOST_PREFIX="admin"                   # Admin UI hostname prefix
export CP_SUBSCRIPTION="dev"                          # Subscription portal hostname prefix
export CP_HYBRID_CONNECTIVITY="true"                  # Set "false" to disable hybrid-proxy (saves resources)

# Single ACM wildcard cert covering all CP subdomains (*.${TP_BASE_DNS_DOMAIN})
export TP_BASE_DOMAIN_CERT_ARN=""                     # ACM cert ARN for *.${TP_BASE_DNS_DOMAIN}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ OPTION 2: Legacy Multi-Level DNS Structure (Backward Compatible)            │
# │ Multi-level subdomain: admin.cp1-my.aws.example.com                         │
# │ Use when: upgrading from v1.14.x, or running multiple CP instances          │
# └─────────────────────────────────────────────────────────────────────────────┘
# Results in:
#   Admin UI      : https://admin.cp1-my.${TP_HOSTED_ZONE_DOMAIN}
#   Subscription  : https://<sub>.cp1-my.${TP_HOSTED_ZONE_DOMAIN}
#   Tunnel        : https://<sub>.cp1-tunnel.${TP_HOSTED_ZONE_DOMAIN}
#   ACM certs     : *.cp1-my.${TP_HOSTED_ZONE_DOMAIN} and *.cp1-tunnel.${TP_HOSTED_ZONE_DOMAIN}

# Uncomment these and comment out Option 1 above to use legacy DNS:
# export TP_MY_DOMAIN="${CP_INSTANCE_ID}-my.${TP_HOSTED_ZONE_DOMAIN}"         # CP application domain
# export TP_TUNNEL_DOMAIN="${CP_INSTANCE_ID}-tunnel.${TP_HOSTED_ZONE_DOMAIN}" # CP hybrid connectivity domain
# export TP_MY_DOMAIN_CERT_ARN=""    # ACM cert ARN for *.${TP_MY_DOMAIN}
# export TP_TUNNEL_DOMAIN_CERT_ARN="" # ACM cert ARN for *.${TP_TUNNEL_DOMAIN}


# =============================================================================
# SECTION 10: RDS / DATABASE CONFIGURATION
# =============================================================================
# TIBCO Control Plane requires a PostgreSQL 16 database.
# Amazon Aurora PostgreSQL is the recommended option — it provides automatic
# failover, automatic backups, and scales read capacity independently.
#
# TP_RDS_AVAILABILITY: "public" exposes RDS with a public endpoint (dev/test only).
# For production, use "private" and connect via VPC peering or internal routes.
#
# Reference: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/

export TP_RDS_AVAILABILITY="public"          # "public" or "private" — use "private" for production
export TP_RDS_USERNAME="TP_rdsadmin"         # RDS master username (cannot be "admin" in Aurora)
export TP_RDS_MASTER_PASSWORD="TP_DBAdminPassword"   # RDS master password; use a strong password
export TP_RDS_INSTANCE_CLASS="db.t3.medium"  # RDS instance class; scale up for production workloads
export TP_RDS_PORT="5432"                    # PostgreSQL port (default 5432)
export TP_WAIT_FOR_RESOURCE_AVAILABLE="false" # Set to "true" to wait for RDS to be available before continuing


# =============================================================================
# SECTION 11: DATA PLANE CONFIGURATION
# =============================================================================
# DP_NAMESPACE is the Kubernetes namespace where the Data Plane is registered.
# It is created by TIBCO Control Plane during Data Plane registration and
# is used in OpenTelemetry trace collector service discovery.

export DP_NAMESPACE="dp1-ns"                 # Replace with your actual Data Plane namespace after registration


# =============================================================================
# SECTION 12: CROSSPLANE CONFIGURATION
# =============================================================================
# Crossplane enables Kubernetes-native provisioning of AWS resources.
# The Crossplane IAM role needs AdministratorAccess to create EFS, RDS, and IAM roles.
# CP_RESOURCE_PREFIX is used as a prefix for all AWS resources created by Crossplane claims.
# Reference: https://docs.crossplane.io/latest/

export CP_RESOURCE_PREFIX="platform"         # Prefix for AWS resources created by Crossplane (max 10 alphanumeric chars)
# export TP_CROSSPLANE_ROLE=""               # Custom Crossplane IAM role name; defaults to ${TP_CLUSTER_NAME}-crossplane-${TP_CLUSTER_REGION}


# =============================================================================
# SECTION 13: OBSERVABILITY / LOG SERVER CONFIGURATION
# =============================================================================
# TIBCO Control Plane can forward its own service logs to an external log server.
# If you are using the Elastic Stack installed in this workshop, set the endpoint
# to the Elasticsearch internal service URL after the stack is deployed.
# Leave empty to disable log forwarding (logging is optional).
# Reference: https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm#UserGuide/observability.htm

export TP_LOGSERVER_ENDPOINT=""              # Log server endpoint (e.g., Elasticsearch URL)
export TP_LOGSERVER_INDEX=""                 # Log index name in the log server
export TP_LOGSERVER_USERNAME=""              # Log server username
export TP_LOGSERVER_PASSWORD=""              # Log server password

# Observability chart release name (dp-config-es deploys Elasticsearch, Kibana, APM)
export TP_ES_RELEASE_NAME="dp-config-es"    # Helm release name for the Elastic stack


# =============================================================================
# SECTION 14: CLEANUP CONFIGURATION
# =============================================================================
# TP_DELETE_CLUSTER controls whether clean-up scripts delete the EKS cluster
# itself or only the Helm charts and AWS resources (EFS, RDS, etc.).
# Set to "false" to preserve the cluster when testing repeated installs.

export TP_DELETE_CLUSTER="true"              # "true" = delete EKS cluster; "false" = delete only charts and AWS resources


# =============================================================================
# SECTION 15: CONTROL PLANE DATABASE CONFIGURATION
# =============================================================================
# These variables populate the tibco-cp-base chart's database section.
# Set them after the RDS instance is created (via CLI script or Crossplane claim).
#
# For CLI-provisioned RDS: retrieve the endpoint from the AWS Console or CLI:
#   aws rds describe-db-clusters --query "DBClusters[?DBClusterIdentifier=='${TP_CLUSTER_NAME}-db'].Endpoint"
#
# For Crossplane-provisioned RDS: retrieve from the secret in the CP namespace:
#   kubectl get secret -n ${CP_INSTANCE_ID}-ns ${CP_INSTANCE_ID}-aurora-details -o yaml
#
# TP_DB_SSL_MODE: "disable" for dev/test (CLI-provisioned RDS without SSL enforcement)
#                 "require" or "verify-full" for Crossplane-provisioned RDS (SSL enforced)
# For production Aurora PostgreSQL, prefer "require" or "verify-full".
# Reference: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html

export TP_DB_HOST=""                          # RDS cluster writer endpoint (set after RDS is created)
export TP_DB_NAME="postgres"                  # Database name — REQUIRED by tibco-cp-base; must match the
                                              # databaseName used when creating the RDS cluster (Aurora default: "postgres")
export TP_DB_PORT="${TP_RDS_PORT}"            # Database port (inherited from Section 10)
export TP_DB_USERNAME="${TP_RDS_USERNAME}"    # Database master username (inherited from Section 10)
export TP_DB_PASSWORD="${TP_RDS_MASTER_PASSWORD}"  # Database master password (inherited from Section 10)

# SSL mode controls how the CP orchestrator connects to Aurora PostgreSQL:
#   "disable"     — no TLS (only safe when RDS is in a private subnet with no internet exposure)
#   "require"     — TLS required; connection encrypted but server cert is NOT verified (recommended for most EKS setups)
#   "verify-full" — TLS required AND the server certificate is verified against the CA bundle (most secure)
# For Crossplane-provisioned Aurora (rds.force_ssl=1 enforced), use "require" or "verify-full".
# Reference: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html
export TP_DB_SSL_MODE="disable"               # SSL mode: "disable" | "require" | "verify-full"

# --- Optional: SSL certificate verification (used when TP_DB_SSL_MODE="verify-full") ---
# AWS provides regional CA bundles for Aurora. Download the bundle for your region:
#   curl -o rds-ca-bundle.pem \
#     https://truststore.pki.rds.amazonaws.com/${TP_CLUSTER_REGION}/${TP_CLUSTER_REGION}-bundle.pem
# Then store it as a Kubernetes secret:
#   kubectl create secret generic rds-ca-cert -n ${CP_INSTANCE_ID}-ns \
#     --from-file=rds-ca-bundle.pem
# Reference: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html
export TP_DB_SSL_CERT_SECRET="rds-ca-cert"    # Name of the K8s secret holding the RDS CA bundle
export TP_DB_SSL_CERT_KEY="rds-ca-bundle.pem" # Key (filename) inside the secret
# db_ssl_root_cert in the tibco-cp-base values must match the mount path configured in the chart.
# Default mount path used by tibco-cp-base: /etc/ssl/certs/rds-ca-bundle.pem
export TP_DB_SSL_ROOT_CERT_PATH="/etc/ssl/certs/rds-ca-bundle.pem"


# =============================================================================
# SECTION 16: CONTROL PLANE EMAIL CONFIGURATION
# =============================================================================
# TIBCO Control Plane sends transactional emails for:
#   - User registration and invitation
#   - Password reset
#   - License expiration alerts
#   - Scheduled report delivery
#
# In TIBCO Platform 1.18.0, email server settings are configured in the
# Platform Console after installation or upgrade. Keep these variables as a
# place to record SES/SMTP/SendGrid settings, but do not pass the deprecated
# global.external.emailServer* values to tibco-cp-base 1.18.0 Helm installs.
#
# Supported email server types:
#   "ses"      — AWS Simple Email Service (recommended for AWS deployments)
#   "smtp"     — Standard SMTP relay (e.g., Office 365, Gmail, corporate mail)
#   "sendgrid" — SendGrid API (third-party email delivery)
#
# For SES: The CP service account must have AmazonSESFullAccess policy via IRSA.
#           The SES identity ARN must be in the same region as the cluster.
#           Reference: https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html
#
# For SMTP: Ensure your corporate SMTP relay allows connections from the EKS VPC.
# For SendGrid: Create an API key at https://app.sendgrid.com/settings/api_keys

export TP_EMAIL_SERVER_TYPE=""                # "ses", "smtp", or "sendgrid" (leave empty to disable email)
export TP_FROM_EMAIL=""                       # From address for all CP notifications (e.g., noreply@aws.example.com)
export TP_EMAIL_CC_ADDRESSES=""               # Optional: CC addresses for platform notifications (comma-separated)
export TP_REPORTS_EMAIL_ALIAS=""              # Optional: Email alias for scheduled report delivery

# AWS SES configuration (used when TP_EMAIL_SERVER_TYPE="ses")
export TP_SES_ARN=""                          # SES identity ARN (e.g., arn:aws:ses:us-east-1:123456789012:identity/user@example.com)

# SMTP configuration (used when TP_EMAIL_SERVER_TYPE="smtp")
export TP_SMTP_SERVER=""                      # SMTP relay hostname
export TP_SMTP_PORT="587"                     # SMTP port (587 for TLS, 465 for SSL, 25 for plain)
export TP_SMTP_USERNAME=""                    # SMTP authentication username
export TP_SMTP_PASSWORD=""                    # SMTP authentication password

# SendGrid configuration (used when TP_EMAIL_SERVER_TYPE="sendgrid")
export TP_SENDGRID_API_KEY=""                 # SendGrid API key


# =============================================================================
# SECTION 17: CONTROL PLANE ADMIN USER CONFIGURATION
# =============================================================================
# The initial admin user is created during the first CP deployment.
# This account is the bootstrap administrator — subsequent users are managed
# through the CP UI.
# Reference: https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm#Installation/deploying-control-plane-in-kubernetes.htm

export TP_ADMIN_EMAIL=""                      # Admin user email address (used as login username)
export TP_ADMIN_FIRSTNAME=""                  # Admin user first name
export TP_ADMIN_LASTNAME=""                   # Admin user last name
export TP_ADMIN_INITIAL_PASSWORD=""           # Admin initial password (min 8 chars, must contain upper/lower/digit/special)
export TP_ADMIN_CUSTOMER_ID=""                # Optional: Customer ID for license association


# =============================================================================
# SECTION 18: CONTROL PLANE PROXY CONFIGURATION
# =============================================================================
# Configure HTTP/HTTPS proxy if the EKS cluster requires egress through a
# corporate proxy. The noProxy list must include cluster-internal addresses
# to prevent proxy routing for in-cluster traffic.
# Leave empty if no proxy is required (typical for direct internet access from EKS).

export TP_HTTP_PROXY=""                       # HTTP proxy URL (e.g., http://proxy.corp.com:3128)
export TP_HTTPS_PROXY=""                      # HTTPS proxy URL (e.g., http://proxy.corp.com:3128)
export TP_NO_PROXY=""                         # Comma-separated no-proxy list (e.g., ".cluster.local,10.0.0.0/8,172.20.0.0/16")


# =============================================================================
# DERIVED VARIABLES (do not edit — computed from above)
# =============================================================================
# These are computed after the above values are set.
# Uncomment and run manually if needed.

# export KUBECONFIG="$(pwd)/${TP_CLUSTER_NAME}.yaml"

echo "Environment variables loaded."
echo "  Cluster      : ${TP_CLUSTER_NAME} (${TP_CLUSTER_REGION})"
echo "  DNS approach : ${TP_BASE_DNS_DOMAIN:+Simplified — base: ${TP_BASE_DNS_DOMAIN}}${TP_MY_DOMAIN:+Legacy — my: ${TP_MY_DOMAIN}}"
echo "  DP Domain    : ${TP_DOMAIN}"
echo "  Registry     : ${TP_CONTAINER_REGISTRY_URL}"
echo ""
echo "Review and update empty values before proceeding:"
[ -z "$TP_CONTAINER_REGISTRY_USER" ]     && echo "  ⚠ TP_CONTAINER_REGISTRY_USER is not set"
[ -z "$TP_CONTAINER_REGISTRY_PASSWORD" ] && echo "  ⚠ TP_CONTAINER_REGISTRY_PASSWORD is not set"
# Simplified DNS cert check
[ -n "${TP_BASE_DNS_DOMAIN:-}" ] && [ -z "${TP_BASE_DOMAIN_CERT_ARN:-}" ] \
                                           && echo "  ⚠ TP_BASE_DOMAIN_CERT_ARN is not set (required for simplified DNS)"
# Legacy DNS cert checks (only warn when legacy vars are set)
[ -n "${TP_MY_DOMAIN:-}" ] && [ -z "${TP_MY_DOMAIN_CERT_ARN:-}" ] \
                                           && echo "  ⚠ TP_MY_DOMAIN_CERT_ARN is not set (required for legacy DNS)"
[ -n "${TP_TUNNEL_DOMAIN:-}" ] && [ -z "${TP_TUNNEL_DOMAIN_CERT_ARN:-}" ] \
                                           && echo "  ⚠ TP_TUNNEL_DOMAIN_CERT_ARN is not set (required for legacy DNS)"
[ -z "$TP_RDS_MASTER_PASSWORD" -o "$TP_RDS_MASTER_PASSWORD" = "TP_DBAdminPassword" ] \
                                           && echo "  ⚠ TP_RDS_MASTER_PASSWORD is using the default placeholder"
