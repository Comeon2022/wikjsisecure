# 🔐 Secure Wiki.js on Google Cloud Run - IaC Assessment

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white) ![Google Cloud](https://img.shields.io/badge/GoogleCloud-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white) ![Security](https://img.shields.io/badge/Security-Secret_Manager-red?style=for-the-badge)

A secure Infrastructure as Code (IaC) solution to deploy [Wiki.js](https://wiki.js.org/) on Google Cloud Run with enterprise-grade security using Google Secret Manager and private networking.

## 📋 Solution Overview

This Terraform solution provides a **production-ready, secure deployment** of Wiki.js with:

- **🔐 Private Database**: Cloud SQL PostgreSQL with private IP only (no public access)
- **🌐 Secure Networking**: VPC with private service connection and VPC Access Connector
- **🛡️ Secret Management**: Database credentials stored in Google Secret Manager
- **🔒 Security Best Practices**: Least privilege IAM, encrypted storage, audit logging
- **⚡ One-Command Deployment**: Fully automated infrastructure provisioning

## 🏗️ Architecture

```
                    🌐 Public Internet
                         │
                         ▼
              ┌─────────────────┐
              │   Cloud Run     │
              │   (Wiki.js)     │ 🌐 Public Access
              │                 │
              └─────────┬───────┘
                        │
                        │ 🔐 VPC Access Connector
                        ▼
              ┌─────────────────┐
              │  Private VPC    │
              │                 │
              │  ┌───────────┐  │
              │  │Cloud SQL  │  │ 🔐 Private IP Only
              │  │(PostgreSQL)│  │ 🔒 No Public Access
              │  └───────────┘  │
              └─────────────────┘
                        ▲
                        │ 🔐 Secret Manager
              ┌─────────────────┐
              │   Credentials   │
              │   (Encrypted)   │
              └─────────────────┘
```

## 📦 Prerequisites

Before running this solution, ensure you have the following installed and configured:

### Required Tools
- **[Google Cloud SDK](https://cloud.google.com/sdk/docs/install)** (>= 400.0.0)
- **[Terraform](https://www.terraform.io/downloads)** (>= 1.0)
- **[Docker](https://docs.docker.com/get-docker/)** (>= 20.0.0)
- **Git** for version control

### Google Cloud Setup
1. **GCP Project**: An active Google Cloud Project with billing enabled
2. **Authentication**: Configure application default credentials
   ```bash
   gcloud auth application-default login
   ```
3. **Docker Authentication**: Configure Docker for Artifact Registry
   ```bash
   gcloud auth configure-docker
   ```

### Required Permissions
Your Google Cloud user/service account needs the following roles:
- `roles/owner` OR the combination of:
  - `roles/compute.admin`
  - `roles/cloudsql.admin`
  - `roles/run.admin`
  - `roles/secretmanager.admin`
  - `roles/artifactregistry.admin`
  - `roles/serviceusage.serviceUsageAdmin`

## 🚀 Setup Instructions

### Step 1: Clone Repository
```bash
git clone <your-repository-url>
cd <repository-name>
```

### Step 2: Initialize Terraform
```bash
terraform init
```

### Step 3: Review Configuration (Optional)
```bash
# Review the planned infrastructure changes
terraform plan
```

### Step 4: Deploy Infrastructure
```bash
# Deploy the complete solution
terraform apply

# When prompted, enter your GCP Project ID
# Example: my-gcp-project-123456
```

### Step 5: Access Your Wiki
After successful deployment (approximately 5-10 minutes), access your Wiki.js instance using the URL provided in the output.

## 💻 Command Examples

### Basic Operations
```bash
# Initialize Terraform
terraform init

# Plan deployment (review changes)
terraform plan -var="project_id=YOUR_PROJECT_ID"

# Apply configuration
terraform apply -var="project_id=YOUR_PROJECT_ID"

# View outputs
terraform output

# Destroy infrastructure (cleanup)
terraform destroy
```

### Advanced Operations
```bash
# Format Terraform files
terraform fmt

# Validate configuration
terraform validate

# Show current state
terraform show

# Import existing resources (if needed)
terraform import google_project.my_project YOUR_PROJECT_ID
```

### Monitoring and Debugging
```bash
# Check Cloud Run service status
gcloud run services list --region=us-central1

# View Cloud Run logs
gcloud run services logs read wiki-js --region=us-central1

# Check Cloud SQL instance
gcloud sql instances list

# View secrets (metadata only)
gcloud secrets list

# Check VPC Access Connector
gcloud compute networks vpc-access connectors list --region=us-central1
```

## 🔧 Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP Project ID | - | ✅ Yes |
| `region` | GCP Region for resources | `us-central1` | No |
| `zone` | GCP Zone for resources | `us-central1-a` | No |

### Custom Configuration Example
```hcl
# terraform.tfvars
project_id = "my-production-project"
region     = "europe-west1"
zone       = "europe-west1-b"
```

## 📊 What Gets Created

| Resource Type | Name | Purpose |
|---------------|------|---------|
| **VPC Network** | `wiki-js-vpc` | Private networking foundation |
| **Subnet** | `wiki-js-subnet` | Network segment for resources |
| **Private Connection** | `wiki-js-private-ip` | Cloud SQL private peering |
| **VPC Connector** | `wiki-js-connector` | Cloud Run ↔ VPC bridge |
| **Cloud SQL** | `wiki-postgres-instance` | PostgreSQL database (private) |
| **Cloud Run** | `wiki-js` | Wiki.js application |
| **Secret Manager** | `wiki-js-db-*` | Encrypted credentials |
| **Service Accounts** | `wiki-js-sa`, `wiki-js-build-sa` | Secure identities |
| **Artifact Registry** | `wiki-js` | Private container repository |

## 🛡️ Security Features

### Network Security
- **Private VPC**: Isolated network environment
- **Private IP Only**: Cloud SQL accessible only via private network
- **VPC Access Connector**: Secure Cloud Run to database communication
- **No Public Database Access**: Complete isolation from public internet

### Credential Security
- **Secret Manager**: Encrypted credential storage
- **Random Password Generation**: 32-character secure passwords
- **Zero Hardcoding**: No credentials in code or state files
- **Least Privilege IAM**: Minimal required permissions

### Audit and Monitoring
- **Cloud Logging**: All operations logged
- **Secret Access Tracking**: Audit trail for credential access
- **VPC Flow Logs**: Network traffic monitoring
- **IAM Audit**: Permission changes tracked

## 🔍 Validation and Testing

### Syntax Validation
```bash
# Validate Terraform syntax
terraform validate

# Format code
terraform fmt -check

# Security scanning (if tfsec installed)
tfsec .
```

### Functional Testing
```bash
# Test database connectivity
gcloud sql connect wiki-postgres-instance --user=wikijs

# Test Cloud Run service
curl -I $(terraform output -raw wiki_js_url)

# Test secret access
gcloud secrets versions access latest --secret=wiki-js-db-username
```

## 🚨 Troubleshooting

### Common Issues and Solutions

**Issue: "Private service connection failed"**
```bash
# Solution: Check Service Networking API
gcloud services enable servicenetworking.googleapis.com
terraform apply
```

**Issue: "VPC Access Connector creation timeout"**
```bash
# Solution: Verify VPC and wait for completion
gcloud compute networks vpc-access connectors list --region=us-central1
```

**Issue: "Secret not found"**
```bash
# Solution: Wait for Secret Manager propagation
sleep 60
gcloud secrets list
```

**Issue: "Docker authentication failed"**
```bash
# Solution: Re-authenticate Docker
gcloud auth configure-docker us-central1-docker.pkg.dev
```

### Debug Commands
```bash
# Check all created resources
gcloud projects get-iam-policy $PROJECT_ID
gcloud compute networks list
gcloud sql instances list
gcloud run services list
gcloud secrets list

# Check logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=wiki-js" --limit=50
```

## 🧹 Cleanup

To destroy all created resources:

```bash
terraform destroy
```

**⚠️ Warning**: This permanently deletes all infrastructure and data.

## 📁 Repository Structure

```
.
├── main.tf              # Main Terraform configuration
├── README.md           # This documentation
├── .gitignore          # Git ignore patterns
└── terraform.tfvars.example  # Example variables file
```

## 📝 Notes

- **Deployment Time**: Expect 5-10 minutes for complete deployment
- **Resource Cleanup**: Use `terraform destroy` to avoid ongoing costs
- **Security**: All credentials are auto-generated and stored securely
- **Scalability**: Cloud Run auto-scales based on demand
- **Monitoring**: Access logs via Google Cloud Console

## 🔗 Useful Links

- [Google Cloud Console](https://console.cloud.google.com/)
- [Cloud Run Dashboard](https://console.cloud.google.com/run)
- [Cloud SQL Dashboard](https://console.cloud.google.com/sql)
- [Secret Manager Dashboard](https://console.cloud.google.com/security/secret-manager)
- [Terraform Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

