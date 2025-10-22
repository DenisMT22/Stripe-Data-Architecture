# Architecture de Données Stripe - Infrastructure Complète

## Vue d'Ensemble

Cette architecture implémente une plateforme de données moderne pour Stripe, combinant :
- **OLTP** : Transactions opérationnelles temps réel (Azure SQL Database)
- **OLAP** : Analytics et reporting (Azure Synapse Analytics)
- **NoSQL** : Données non structurées et cache (Azure Cosmos DB)
- **ETL** : Pipelines automatisés (Azure Data Factory)
- **ML** : Détection de fraude (Azure Machine Learning)

---

## Architecture Globale

```
┌─────────────────────────────────────────────────────────────────┐
│                        INGESTION LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │ Stripe API   │    │ Webhooks     │    │ Dashboard    │    │
│  │ Payments     │───▶│ Events       │───▶│ Sessions     │    │
│  └──────────────┘    └──────────────┘    └──────────────┘    │
│         │                    │                    │            │
└─────────┼────────────────────┼────────────────────┼────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OPERATIONAL LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           Azure SQL Database (OLTP)                      │  │
│  │  • 9 tables normalized (3NF)                            │  │
│  │  • Transactions < 100ms P99                             │  │
│  │  • Change Data Capture enabled                          │  │
│  └────────────┬─────────────────────────────────────────────┘  │
│               │                                                 │
│  ┌────────────▼─────────────────────────────────────────────┐  │
│  │           Azure Cosmos DB (NoSQL)                        │  │
│  │  • 4 collections (api_logs, sessions, fraud, webhooks)  │  │
│  │  • Latency < 10ms P99                                   │  │
│  │  • Change Feed streaming                                │  │
│  └────────────┬─────────────────────────────────────────────┘  │
│               │                                                 │
└───────────────┼─────────────────────────────────────────────────┘
                │
                │ CDC + Change Feed
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      INTEGRATION LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           Azure Data Factory (ETL)                       │  │
│  │  • Batch ETL: OLTP → OLAP (nightly)                     │  │
│  │  • Stream: Cosmos DB → Synapse (real-time)             │  │
│  │  • Orchestration: 15+ pipelines                         │  │
│  └────────────┬─────────────────────────────────────────────┘  │
│               │                                                 │
└───────────────┼─────────────────────────────────────────────────┘
                │
                │ Transformed Data
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ANALYTICAL LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │       Azure Synapse Analytics (OLAP)                     │  │
│  │  • Star Schema (6 dims + 1 fact)                        │  │
│  │  • Columnstore indexes                                  │  │
│  │  • Query response < 5s                                  │  │
│  └────────────┬─────────────────────────────────────────────┘  │
│               │                                                 │
└───────────────┼─────────────────────────────────────────────────┘
                │
                │ Business Intelligence
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ Power BI     │  │ Looker       │  │ Custom API   │        │
│  │ Dashboards   │  │ Reports      │  │ Exports      │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Flux de Données Critiques

### Flux 1 : Transaction Payment (Temps Réel)
```
1. API Request → Azure App Gateway
2. Insert Payment → Azure SQL Database (OLTP)
3. Trigger → Azure Function
4. Compute Fraud Score → Cosmos DB (fraud_features)
5. Log API → Cosmos DB (api_logs)
6. Send Webhook → Cosmos DB (webhook_events)

Latency totale : < 200ms P99
```

### Flux 2 : ETL Batch (Nightly)
```
1. CDC capture changes → SQL Database (cdc.dbo_Payment_CT)
2. Azure Data Factory → Extract (02:00 UTC)
3. Transform → Staging tables
4. Load → Synapse (Fact_Payment + Dim_*)
5. Refresh → Aggregate tables
6. Validate → Data quality checks

Durée : ~45 minutes pour 1M transactions/jour
```

### Flux 3 : Analytics Streaming (Near Real-Time)
```
1. Change Feed → Cosmos DB (api_logs)
2. Azure Stream Analytics → Filter + Aggregate
3. Sink → Synapse Analytics (Fact_API_Performance)
4. Update → Materialized views

Latency : < 5 minutes
```

---

## Estimation des Coûts (Production)

### Coûts Mensuels par Service (Europe West)

| Service | SKU | Coût/Mois | Justification |
|---------|-----|-----------|---------------|
| **Azure SQL Database** | Business Critical Gen5 8vCore | $2,920 | High availability + Read replicas |
| **Azure Synapse Analytics** | DW500c (5000 DWU) | $5,840 | Columnstore performance |
| **Azure Cosmos DB** | 110K RU/s autoscale | $7,920 | Multi-region + low latency |
| **Azure Data Factory** | 100 pipeline runs/day | $350 | ETL orchestration |
| **Azure Storage** | 10TB hot + 50TB cool | $450 | Backups + archives |
| **Azure Monitor** | Logs + Metrics | $280 | Observability |
| **Networking** | VNet + Private Links | $240 | Security |
| **TOTAL** | | **~$18,000** | |

**Source : [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)**

### Optimisations Possibles

- **Dev/Test** : $4,500/mois (downsized SKUs)
- **Reserved Instances** : -30% sur SQL/Synapse (engagement 3 ans)
- **Autoscaling** : -40% sur Cosmos DB pendant heures creuses
- **Coût optimisé réel** : ~$12,000/mois en production

---

## Sécurité et Conformité

### Architecture Sécurité (Defense in Depth)

```
┌─────────────────────────────────────────────────────────────┐
│                    PERIMETER SECURITY                       │
│  • Azure Firewall                                          │
│  • DDoS Protection Standard                               │
│  • Web Application Firewall (WAF)                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    NETWORK SECURITY                         │
│  • Private Virtual Network (VNet)                          │
│  • Network Security Groups (NSGs)                          │
│  • Private Endpoints (no public IPs)                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    IDENTITY & ACCESS                        │
│  • Azure AD Authentication                                 │
│  • Managed Identities (no passwords)                       │
│  • RBAC (Role-Based Access Control)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    DATA PROTECTION                          │
│  • Encryption at rest (TDE + AES-256)                      │
│  • Encryption in transit (TLS 1.3)                         │
│  • Always Encrypted (column-level)                         │
│  • Dynamic Data Masking                                    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    COMPLIANCE & AUDIT                       │
│  • Azure Policy (governance)                               │
│  • Diagnostic Logs (90 days retention)                     │
│  • Azure Sentinel (SIEM)                                   │
│  • Compliance: PCI-DSS, GDPR, SOC 2                       │
└─────────────────────────────────────────────────────────────┘
```

### Certifications Stripe
- **PCI-DSS Level 1** : Stockage données cartes bancaires
- **GDPR** : Données personnelles UE (droit à l'oubli)
- **SOC 2 Type II** : Sécurité processus
- **ISO 27001** : Gestion sécurité information

---

## Monitoring et Observabilité

### Métriques Clés (SLA)

| Métrique | Seuil | Action |
|----------|-------|--------|
| **OLTP Latency P99** | < 100ms | Alert si > 200ms pendant 5min |
| **OLAP Query Time** | < 5s | Alert si > 10s pendant 3 queries |
| **Cosmos DB Latency** | < 10ms | Alert si > 50ms pendant 5min |
| **ETL Success Rate** | > 99.9% | Alert + rollback si échec |
| **API Availability** | > 99.95% | Incident majeur si < 99.9% |
| **Data Freshness** | < 15min | Alert si OLAP data > 1h old |

### Dashboards Azure Monitor

1. **Infrastructure Health**
   - CPU/Memory utilisation
   - Storage IOPS
   - Network throughput

2. **Application Performance**
   - Request rate & latency
   - Error rate (4xx, 5xx)
   - Dependency failures

3. **Business Metrics**
   - Transactions per second
   - Revenue tracking
   - Fraud detection rate

4. **Cost Management**
   - Daily spend by service
   - Budget alerts
   - Reserved instance utilization

---

## Déploiement

### Prérequis

```bash
# Azure CLI
az --version  # >= 2.50.0

# Terraform
terraform --version  # >= 1.5.0

# Authentification Azure
az login
az account set --subscription "SUBSCRIPTION_ID"
```

### Déploiement Infrastructure (Terraform)

```bash
cd architecture/terraform

# Initialiser Terraform
terraform init

# Plan (environnement dev)
terraform plan -var-file="environments/dev.tfvars"

# Apply
terraform apply -var-file="environments/dev.tfvars" -auto-approve

# Durée estimée : 25-30 minutes
```

### Déploiement Pipelines (Azure Data Factory)

```bash
cd architecture/pipelines

# Importer pipelines ADF
az datafactory pipeline create \
  --factory-name stripe-adf-prod \
  --resource-group stripe-rg-prod \
  --name etl_oltp_to_olap \
  --pipeline @adf/etl_oltp_to_olap.json
```

---

## Structure des Dossiers

```
architecture/
├── README.md                        # Ce fichier
├── diagrams/
│   ├── architecture.md              # Diagramme architecture globale
│   └── data_flow.md                 # Flux de données détaillés
├── terraform/
│   ├── main.tf                      # Configuration principale
│   ├── variables.tf                 # Variables d'entrée
│   ├── outputs.tf                   # Outputs Terraform
│   ├── providers.tf                 # Providers Azure
│   ├── modules/                     # Modules réutilisables
│   │   ├── sql_database.tf
│   │   ├── synapse_analytics.tf
│   │   ├── cosmos_db.tf
│   │   ├── data_factory.tf
│   │   ├── networking.tf
│   │   └── security.tf
│   └── environments/
│       ├── dev.tfvars               # Env développement
│       └── prod.tfvars              # Env production
└── pipelines/
    ├── adf/                         # Pipelines Data Factory
    │   ├── etl_oltp_to_olap.json
    │   └── change_feed_cosmos.json
    └── scripts/                     # Scripts utilitaires
        └── setup_cdc.sql            # Configuration CDC
```

---

## Tests et Validation

### Tests Unitaires (Infrastructure)

```bash
# Validation Terraform
terraform validate

# Linting
tflint

# Security scan
checkov --directory terraform/
```

### Tests d'Intégration (Pipelines)

```bash
# Test ETL pipeline
az datafactory pipeline create-run \
  --factory-name stripe-adf-dev \
  --name etl_oltp_to_olap \
  --parameters '{"runDate":"2025-10-20"}'

# Vérifier statut
az datafactory pipeline-run show \
  --factory-name stripe-adf-dev \
  --run-id <RUN_ID>
```

### Tests de Charge (Performance)

```bash
# Simuler 10K transactions/seconde
k6 run --vus 1000 --duration 5m load_tests/payment_flow.js

# Benchmark requêtes OLAP
sqlcmd -S synapse-endpoint.sql.azuresynapse.net \
       -d stripe_dw \
       -Q "EXEC sp_benchmark_queries"
```

---

## Documentation Technique

### Guides Détaillés

- [Terraform Modules](terraform/modules/README.md)
- [Azure Data Factory Pipelines](pipelines/adf/README.md)
- [Change Data Capture Setup](pipelines/scripts/README.md)
- [Disaster Recovery Plan](docs/disaster_recovery.md) (à créer)
- [Runbook Incidents](docs/runbook.md) (à créer)

### Références Externes

- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/)
- [Stripe API Documentation](https://stripe.com/docs/api)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Data Factory Best Practices](https://learn.microsoft.com/en-us/azure/data-factory/concepts-best-practices)

---

## Contribution

### Workflow Git

```bash
# Créer feature branch
git checkout -b feature/nom-feature

# Commits atomiques
git commit -m "feat(terraform): add cosmos db module"

# Push et Pull Request
git push origin feature/nom-feature
```

### Convention Commits

- `feat:` Nouvelle fonctionnalité
- `fix:` Correction bug
- `docs:` Documentation
- `refactor:` Refactoring code
- `test:` Ajout tests
- `chore:` Maintenance

---

## Support

**Équipe Data Engineering Stripe**
- Email: data-engineering@stripe.com
- Slack: #data-platform
- On-call: PagerDuty rotation

**Incidents Production**
- Severity 1 (P1): < 15min response time
- Severity 2 (P2): < 1h response time
- Severity 3 (P3): < 24h response time