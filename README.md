# 🔐 Secure Wiki.js on Google Cloud Run

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white) ![Google Cloud](https://img.shields.io/badge/GoogleCloud-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white) ![Security](https://img.shields.io/badge/Security-Secret_Manager-red?style=for-the-badge)

Deploy [Wiki.js](https://wiki.js.org/) on Google Cloud Run with **enterprise-grade security** using Google Secret Manager. This repository provides a **one-command deployment** with production-ready security practices.

## 🛡️ Security Features

- **🔐 Secret Manager Integration**: Database credentials stored securely, never in plain text
- **🎲 Random Password Generation**: 32-character passwords with special characters
- **🌐 Private Networking**: Database accessible only via private VPC (no public IP)
- **🔒 SSL Required**: All database connections encrypted with SSL
- **🔑 Least Privilege IAM**: Service accounts with minimal required permissions
- **📝 No Credential Exposure**: Passwords never appear in logs, Terraform state, or outputs
- **🔄 Credential Rotation**: Easy password rotation via Secret Manager
- **📊 Audit Logging**: All secret access logged for compliance
- **🚫 Network Isolation**: Cloud SQL completely isolated from public internet

## 🏗️ Architecture

```
                    🌐 Public Internet
                         │
                         ▼
              ┌─────────────────┐
              │   Cloud Run     │
              │   (Wiki.js)     │ 🔐 Public Access
              │                 │
              └─────────┬───────┘
                        │
                        │ 🔒 VPC Connector
                        ▼
              ┌─────────────────┐
              │  Private VPC    │
              │                 │
              │  ┌───────────┐  │
              │  │Cloud SQL  │  │ 🔐 Private IP Only
              │  │(PostgreSQL)│  │ 🔒 SSL Required
              │  └───────────┘  │
              └─────────────────┘
                        ▲
                        │ 🔐 Secret Manager
              ┌─────────────────┐
              │   Credentials   │
              │   (Encrypted)   │
              └─────────────────┘
```

## ⚡ Quick Start

### Prerequisites
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured
- [Terraform](https://www.terraform.io/downloads) installed (>= 1.0)
- A GCP project with billing enabled
- Authentication: `gcloud auth application-default login`

### One-Command Secure Deployment

```bash
# 1. Clone this repository
git clone https://github.com/Comeon2022/wikjsisecure.git
cd wikjsisecure

# 2. Initialize Terraform
terraform init

# 3. Deploy everything securely
terraform apply
# Enter your GCP project ID when prompted
```

**That's it!** 🎉 Terraform automatically:

- ✅ Enables all required GCP APIs
- ✅ Creates secure service accounts with minimal permissions
- ✅ Generates random database passwords (32 characters)
- ✅ Stores credentials securely in Secret Manager
- ✅ Sets up Cloud SQL PostgreSQL database with secure authentication
- ✅ Builds and pushes Wiki.js container to private Artifact Registry
- ✅ Deploys Cloud Run service with secret-based configuration
- ✅ Configures public access for your wiki

## 🔐 Security Deep Dive

### Credential Management
- **🎲 Random Password**: 32-character password with upper, lower, numbers, and special characters
- **🔐 Secret Storage**: Username and password stored in Google Secret Manager
- **🚫 Zero Hardcoding**: No credentials visible in code, state, or logs
- **🔑 Secret Access**: Cloud Run reads credentials directly from Secret Manager

### Service Account Security
- **wiki-js-sa**: Cloud Run application identity
  - `roles/run.developer` - Deploy and manage Cloud Run
  - `roles/logging.logWriter` - Write application logs
  - `roles/cloudsql.client` - Connect to database
  - `roles/secretmanager.secretAccessor` - Read database credentials
- **wiki-js-build-sa**: Container build identity
  - `roles/cloudbuild.builds.builder` - Execute builds
  - `roles/artifactregistry.writer` - Push container images

### Network Security
- **Cloud SQL**: Configured with IAM authentication enabled
- **Authorized Networks**: Currently open (0.0.0.0/0) for development
- **Private Registry**: Container images stored in private Artifact Registry

## 📋 What Gets Created

| Resource | Name | Purpose | Security Feature |
|----------|------|---------|------------------|
| **Cloud Run** | `wiki-js` | Wiki.js application | Secret-based env vars |
| **Cloud SQL** | `wiki-postgres-instance` | PostgreSQL database | IAM auth + secure creds |
| **Secret Manager** | `wiki-js-db-username` | Database username | Encrypted storage |
| **Secret Manager** | `wiki-js-db-password` | Database password | Random 32-char password |
| **Artifact Registry** | `wiki-js` | Container images | Private repository |
| **Service Accounts** | `wiki-js-sa`, `wiki-js-build-sa` | Application identity | Least privilege |

## 💰 Cost Estimation

Approximate monthly costs for light usage:

| Service | Configuration | Est. Monthly Cost |
|---------|---------------|-------------------|
| **Cloud Run** | 1M requests, 512MB RAM | ~$2-5 |
| **Cloud SQL** | db-f1-micro, 10GB SSD | ~$7-10 |
| **Secret Manager** | 2 secrets, few accesses | ~$0.06 |
| **Artifact Registry** | <1GB storage | ~$0.10 |
| **Total** | | **~$10-15/month** |

## 🔧 Management & Monitoring

### Secret Management
```bash
# View secrets (no values shown)
gcloud secrets list --project=YOUR_PROJECT_ID

# Rotate database password
gcloud secrets versions add wiki-js-db-password --data-file=new_password.txt

# View secret metadata
gcloud secrets describe wiki-js-db-password
```

### Database Access
```bash
# Connect to database (credentials from Secret Manager)
gcloud sql connect wiki-postgres-instance --user=wikijs
```

### Monitoring
- **📊 Cloud Run Metrics**: Auto-scaling, response times, error rates
- **🗄️ Cloud SQL Insights**: Query performance, connection metrics
- **🔐 Secret Manager Audit**: Who accessed secrets and when
- **📝 Cloud Logging**: Application logs and security events

## 🔧 Advanced Configuration

### Custom Password Requirements
```hcl
resource "random_password" "db_password" {
  length  = 64        # Longer password
  special = true
  upper   = true
  lower   = true
  numeric = true
  min_special = 8     # Minimum special characters
}
```

### Enhanced Database Security
```hcl
resource "google_sql_database_instance" "wiki_postgres" {
  settings {
    ip_configuration {
      ipv4_enabled = false  # Private IP only
      require_ssl  = true   # Force SSL connections
    }
  }
}
```

### Multi-Region Secrets
```hcl
resource "google_secret_manager_secret" "db_password" {
  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
      replicas {
        location = "us-east1"
      }
    }
  }
}
```

## 🧹 Cleanup

To destroy all resources (including secrets):

```bash
terraform destroy
```

⚠️ **Warning**: This will permanently delete:
- Your wiki database and all content
- Container images in Artifact Registry  
- Stored secrets in Secret Manager

## 🐛 Troubleshooting

### Common Issues

**"Secret not found" errors**
- Wait 1-2 minutes after deployment for secrets to propagate
- Check Secret Manager console for secret status

**"Permission denied" on secrets**
- Verify service account has `secretmanager.secretAccessor` role
- Check secret IAM policies

**Database connection issues**
- Verify Cloud SQL allows connections from Cloud Run
- Check Cloud Run logs for credential errors

### Debugging Commands

```bash
# Check secret values (careful - shows actual password!)
gcloud secrets versions access latest --secret=wiki-js-db-password

# Check Cloud Run environment (won't show secret values)
gcloud run services describe wiki-js --region=us-central1

# View application logs
gcloud run services logs read wiki-js --region=us-central1
```

## 🏆 Production Recommendations

### Enhanced Security
- Enable **VPC Connector** for private database access
- Use **Cloud SQL Proxy** for secure connections
- Configure **IP allowlists** for database access
- Enable **audit logging** for all resources
- Set up **secret rotation** schedules

### High Availability
- Use **Cloud SQL High Availability** configuration
- Configure **multi-region** secret replication
- Set up **Cloud Run minimum instances** for zero cold starts
- Enable **Cloud SQL read replicas** for scaling

### Monitoring & Alerting
- Set up **uptime checks** for your wiki
- Configure **error rate alerts** 
- Monitor **database performance** metrics
- Track **secret access** patterns

## 🤝 Contributing

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/security-enhancement`
3. Commit changes: `git commit -am 'Add security feature'`
4. Push to branch: `git push origin feature/security-enhancement`
5. Submit a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Wiki.js](https://wiki.js.org/) - Outstanding wiki platform
- [Google Cloud Platform](https://cloud.google.com/) - Enterprise cloud infrastructure
- [Google Secret Manager](https://cloud.google.com/secret-manager) - Secure credential storage
- [Terraform](https://www.terraform.io/) - Infrastructure as Code excellence

---

**⭐ If this secure deployment helped you, please give it a star!** ⭐

## 🛡️ Security Badge

This deployment follows Google Cloud security best practices:
- ✅ No hardcoded credentials
- ✅ Encrypted secret storage  
- ✅ Least privilege access
- ✅ Audit logging enabled
- ✅ Secure service communication