# 🏢 Enterprise Wiki.js Knowledge Management Platform

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white) ![Google Cloud](https://img.shields.io/badge/GoogleCloud-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white) ![Security](https://img.shields.io/badge/Security-Enterprise_Grade-red?style=for-the-badge)

## 🏗️ Architecture Overview

```
                    🌐 Public Internet
                         │
                         ▼
              ┌─────────────────────────┐
              │      Load Balancer      │ (Auto-scaling)
              │    (Cloud Run HTTPS)    │
              └─────────┬───────────────┘
                        │
                        │ 🔐 VPC Access Connector
                        ▼
    ┌─────────────────────────────────────────────────────────┐
    │                  Private VPC Network                    │
    │  ┌─────────────────┐              ┌─────────────────┐   │
    │  │   Cloud Run     │              │   Cloud SQL     │   │
    │  │   (Wiki.js)     │ ◄────────────┤   (PostgreSQL)  │   │
    │  │   • Auto-scale  │   Private IP │   • Private IP  │   │
    │  │   • Container   │              │   • Encrypted   │   │
    │  └─────────────────┘              └─────────────────┘   │
    └─────────────────────────────────────────────────────────┘
              ▲                                    ▲
              │                                    │
    ┌─────────────────┐                 ┌─────────────────┐
    │ Secret Manager  │                 │   Monitoring    │
    │ • DB Credentials│                 │ • Dashboards    │
    │ • Auto-rotation │                 │ • Alerts        │
    │ • Encrypted     │                 │ • BigQuery Logs │
    └─────────────────┘                 └─────────────────┘
```

## 🔧 Solution Components

### **Compute** - Google Cloud Run
- **Auto-scaling**: 0-1000 instances based on demand
- **Serverless**: Pay only for actual usage
- **Container-based**: Easy deployment and updates
- **HTTPS**: Built-in SSL/TLS termination

### **Storage** - Cloud SQL PostgreSQL
- **Database**: Managed PostgreSQL for Wiki.js data
- **Private networking**: No public IP exposure
- **Automated backups**: Point-in-time recovery
- **High availability**: Optional multi-zone deployment

### **Networking** - Private VPC
- **Isolation**: Private network with no public database access
- **VPC Connector**: Secure Cloud Run to database communication
- **Firewall**: Implicit deny-all with specific allow rules

### **Scaling** - Automatic
- **Horizontal scaling**: Cloud Run auto-scales containers
- **Database scaling**: Vertical scaling available on-demand
- **CDN ready**: Cloud Run integrates with Google CDN

### **Monitoring** - Comprehensive Observability
- **Real-time dashboards**: Custom analytics and performance metrics
- **Email alerts**: Automated notifications for issues
- **Log analytics**: BigQuery integration for advanced querying
- **Performance tracking**: CPU, memory, response times, user activity

## 🚀 Quick Deployment

### Prerequisites
- Google Cloud Project with billing enabled
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed
- [Terraform](https://www.terraform.io/downloads) (>= 1.0) installed
- [Docker](https://docs.docker.com/get-docker/) installed

### Authentication Setup
```bash
# Authenticate with Google Cloud
gcloud auth application-default login

# Configure Docker for Artifact Registry
gcloud auth configure-docker
```

### One-Command Deployment
```bash
# Clone repository
git clone <your-repository-url>
cd <repository-name>

# Initialize and deploy
terraform init
terraform apply

# Enter when prompted:
# 1. Your GCP Project ID
# 2. Your email address for monitoring alerts 
```

**Deployment time**: Approximately 30 minutes

**Known Issue**: Wiki.js is crushing after initial setup, just wait to 5 minutes and browse again to the link.  

## 📊 Monitoring and Observability

### Real-time Analytics Dashboard
- **User Activity**: Page views, sessions, unique visitors
- **Performance Metrics**: Response times, request volume, error rates
- **Resource Monitoring**: CPU, memory utilization for both application and database
- **Security Events**: Login attempts, access patterns, failed authentications

### Automated Alerting (Email Notifications)
- **Performance Alerts**: CPU > 85%, Memory > 85%, Disk > 85%
- **Traffic Alerts**: High concurrent users (>100/min), login activity (>50/min)
- **Error Alerts**: Error rate > 5%, database connectivity issues
- **Security Alerts**: Unusual access patterns, failed authentication attempts

### Advanced Analytics
- **BigQuery Integration**: Store and analyze logs with SQL queries
- **Custom Metrics**: Track business-specific KPIs
- **Historical Analysis**: Trend analysis and capacity planning
- **Compliance Reporting**: Audit trails and access logs

## 🛡️ Security Implementation

### Network Security
- **Private VPC**: Isolated network environment with custom IP ranges
- **No Public Database**: Cloud SQL accessible only via private network
- **VPC Access Connector**: Encrypted communication between services
- **Firewall Rules**: Restrictive ingress/egress policies

### Data Protection
- **Secret Manager**: Database credentials stored encrypted and rotated
- **Random Password Generation**: 32-character secure passwords
- **Encryption at Rest**: All data encrypted using Google-managed keys
- **Encryption in Transit**: TLS 1.3 for all communications

### Access Control
- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Authentication**: Wiki.js handles user authentication and authorization
- **Audit Logging**: All access and configuration changes logged
- **Secret Access Tracking**: Monitor who accesses sensitive data

### Compliance Features
- **Data Residency**: Control where data is stored and processed
- **Audit Trails**: Complete logging of all system activities
- **Backup Encryption**: Automated encrypted backups with retention policies
- **Access Reviews**: Regular permission auditing capabilities

## 🔄 Scalability Architecture

### Horizontal Scaling
- **Auto-scaling**: Cloud Run automatically scales 0-1000 instances
- **Load Distribution**: Built-in load balancing across instances
- **Regional Deployment**: Multi-zone availability within region
- **Global Expansion**: Easy deployment to multiple regions

### Vertical Scaling
- **Database Scaling**: Upgrade Cloud SQL instance types on-demand
- **Memory Allocation**: Adjust Cloud Run memory limits per instance
- **Storage Scaling**: Automatic disk size increases

### Performance Optimization
- **Connection Pooling**: Efficient database connection management
- **Caching**: Built-in Cloud Run caching mechanisms
- **CDN Integration**: Optional Cloud CDN for static assets
- **Image Optimization**: Container image size optimization

## 📋 Deployment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP Project ID | - | ✅ Yes |
| `alert_email` | Email for monitoring alerts | - | ✅ Yes |
| `region` | GCP Region for deployment | `us-central1` | No |
| `zone` | GCP Zone for resources | `us-central1-a` | No |

### Production Configuration Example
```hcl
# terraform.tfvars
project_id  = "company-wiki-prod"
alert_email = "devops-team@company.com"
region      = "us-east1"        # Closer to users
zone        = "us-east1-b"
```

## 🧪 Testing and Validation

### Infrastructure Validation
```bash
# Validate Terraform configuration
terraform validate

# Check resource planning
terraform plan

# Verify deployment
terraform apply
```

### Application Testing
```bash
# Test Wiki.js accessibility
curl -I $(terraform output -raw wiki_js_url)

# Verify database connectivity
gcloud sql connect wiki-postgres-instance --user=wikijs

# Check monitoring metrics
gcloud monitoring metrics list --filter="metric.type:run.googleapis.com"
```

### Security Validation
```bash
# Verify no public IP on database
gcloud sql instances describe wiki-postgres-instance --format="value(ipAddresses.ipAddress)"

# Check secret accessibility
gcloud secrets versions access latest --secret=wiki-js-db-password
```

## 📈 Capacity Planning

### Expected Performance
- **Users**: Supports 100+ concurrent users with default configuration
- **Storage**: 10GB database storage (expandable to 30TB+)
- **Traffic**: Handles 1000+ requests/minute with auto-scaling
- **Availability**: 99.9% uptime SLA with Google Cloud Run

### Scaling Recommendations
- **Small Team** (10-50 users): Default configuration sufficient
- **Medium Team** (50-200 users): Increase Cloud Run max instances to 50
- **Large Team** (200+ users): Upgrade to Cloud SQL Standard tier
- **Enterprise** (1000+ users): Consider multi-region deployment

## 🗂️ File Structure

```
.
├── main.tf                     # Complete Terraform configuration
├── README.md                   # This documentation  
├── .gitignore                  # Git ignore patterns
└── terraform.tfvars.example   # Example configuration
```

## 🚨 Troubleshooting

### Common Deployment Issues

**Issue**: API not enabled
```bash
# Solution: Enable required APIs
gcloud services enable run.googleapis.com cloudsql.googleapis.com
```

**Issue**: Insufficient permissions  
```bash
# Solution: Grant required roles
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:your-email@domain.com" \
  --role="roles/owner"
```

**Issue**: Docker authentication failure
```bash
# Solution: Re-authenticate Docker
gcloud auth configure-docker us-central1-docker.pkg.dev
```

**Issue**: wiki.js service unavilable
```
know issue - after initial setup, wait 5 minute and browse to link again

```

### Monitoring Access
- **Dashboards**: `https://console.cloud.google.com/monitoring/dashboards`
- **Logs**: `https://console.cloud.google.com/logs`
- **Alerts**: `https://console.cloud.google.com/monitoring/alerting`

## 📊 Cost Optimization

### Estimated Monthly Costs (Light Usage)
- **Cloud Run**: $2-5 (1M requests, auto-scaling)
- **Cloud SQL**: $7-15 (db-f1-micro instance)
- **Networking**: $1-3 (VPC, Load Balancer)
- **Monitoring**: $0.50 (basic metrics and logs)
- **Total**: ~$10-25/month

### Cost Reduction Strategies
- Use Cloud Run minimum instances = 0 for development
- Schedule database stop/start for non-production environments
- Implement log retention policies to reduce storage costs
- Monitor usage with billing alerts

## 🤝 Contributing

1. Fork this repository
2. Create feature branch: `git checkout -b feature/enhancement`
3. Commit changes: `git commit -am 'Add new feature'`
4. Push to branch: `git push origin feature/enhancement`
5. Submit Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Additional Resources

- **[Wiki.js Official Documentation](https://docs.js.wiki/)**
- **[Wiki.js GitHub Repository](https://github.com/Requarks/wiki)**
- **[Google Cloud Architecture Center](https://cloud.google.com/architecture)**
- **[Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)**

