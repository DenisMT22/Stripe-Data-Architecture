# Sécurité et Conformité - Stripe Data Architecture

## Vue d'Ensemble

Ce dossier contient la documentation complète de sécurité et conformité pour la plateforme de données Stripe, incluant :

- **Framework de sécurité** : Architecture défense en profondeur
- **Conformité réglementaire** : GDPR, PCI-DSS, CCPA, SOC 2
- **Monitoring et audit** : Azure Sentinel, Policy, alertes
- **Disaster Recovery** : Plan de continuité d'activité

---

## Principes de Sécurité Fondamentaux

### Defense in Depth (7 Couches)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. PERIMETER SECURITY                                       │
│    • Azure Firewall                                         │
│    • DDoS Protection Standard                               │
│    • Web Application Firewall (WAF)                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. NETWORK SECURITY                                         │
│    • Private Virtual Network (VNet isolation)               │
│    • Network Security Groups (NSGs)                         │
│    • Private Endpoints (no public IPs)                      │
│    • Service Endpoints                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. IDENTITY & ACCESS MANAGEMENT                             │
│    • Azure AD Authentication (MFA enforced)                 │
│    • Managed Identities (passwordless)                      │
│    • RBAC (least privilege principle)                       │
│    • Conditional Access Policies                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. APPLICATION SECURITY                                     │
│    • API Gateway (rate limiting, throttling)                │
│    • OAuth 2.0 / OpenID Connect                             │
│    • Secret Management (Key Vault)                          │
│    • Secure coding practices (OWASP Top 10)                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. DATA PROTECTION                                          │
│    • Encryption at rest (AES-256, TDE)                      │
│    • Encryption in transit (TLS 1.3)                        │
│    • Always Encrypted (column-level)                        │
│    • Dynamic Data Masking                                   │
│    • Data Loss Prevention (DLP)                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. MONITORING & DETECTION                                   │
│    • Azure Sentinel (SIEM)                                  │
│    • Security Center (threat detection)                     │
│    • Log Analytics (centralized logging)                    │
│    • Advanced Threat Protection                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. GOVERNANCE & COMPLIANCE                                  │
│    • Azure Policy (automated compliance)                    │
│    • Blueprints (governance templates)                      │
│    • Compliance Manager                                     │
│    • Regular audits (SOC 2, PCI-DSS)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Certifications et Conformité

### Certifications Actuelles (Stripe)

| Certification | Status | Audit Frequency | Next Audit |
|---------------|--------|-----------------|------------|
| **PCI-DSS Level 1** | Active | Annual | 2025-12-15 |
| **SOC 2 Type II** | Active | Annual | 2025-11-30 |
| **ISO 27001** | Active | Annual | 2026-01-20 |
| **GDPR** | Compliant | Continuous | N/A |
| **CCPA** | Compliant | Continuous | N/A |
| **HIPAA** | In Progress | N/A | 2026-06-30 |

**Sources :**
- [Stripe Trust Center](https://stripe.com/en-fr/trust-center/compliance)
- [Stripe Security Whitepaper](https://stripe.com/files/security/stripe-security-guide.pdf)

---

## Contrôles de Sécurité par Niveau

### Niveau 1 : Infrastructure (IaaS)

#### Azure SQL Database
```yaml
Security Controls:
  - Encryption at rest: Transparent Data Encryption (TDE) enabled
  - Encryption in transit: TLS 1.2+ enforced
  - Network: Private endpoint only (no public IP)
  - Authentication: Azure AD + Managed Identity
  - Auditing: Advanced Data Security enabled
  - Backup: Geo-redundant, 35-day retention
  - Threat Detection: Advanced Threat Protection enabled
  
Compliance Mappings:
  PCI-DSS: Requirement 3 (Protect stored cardholder data)
  GDPR: Article 32 (Security of processing)
  SOC 2: CC6.1 (Logical and physical access controls)
```

#### Azure Synapse Analytics
```yaml
Security Controls:
  - Encryption at rest: Customer-managed keys (CMK)
  - Encryption in transit: TLS 1.3
  - Network: VNet integration + Private Link
  - Authentication: Azure AD + Service Principal
  - Data Masking: Dynamic data masking on PII columns
  - Row-level security: Implemented on sensitive tables
  - Auditing: Synapse workspace auditing enabled
  
Compliance Mappings:
  PCI-DSS: Requirement 3.4 (Render PAN unreadable)
  GDPR: Article 25 (Data protection by design)
  SOC 2: CC6.7 (Restricted access to data)
```

#### Azure Cosmos DB
```yaml
Security Controls:
  - Encryption at rest: Azure-managed keys
  - Encryption in transit: TLS 1.2+
  - Network: Private endpoint + IP firewall
  - Authentication: Primary/Secondary keys rotated monthly
  - RBAC: Cosmos DB built-in roles
  - Backup: Continuous backup (7-day restore window)
  - Auditing: Diagnostic logs to Log Analytics
  
Compliance Mappings:
  PCI-DSS: Requirement 4 (Encrypt transmission of data)
  GDPR: Article 32 (Security measures)
  SOC 2: CC6.6 (Logical access controls)
```

### Niveau 2 : Données Sensibles

#### Classification des Données

| Niveau | Type de Données | Exemples | Protection |
|--------|-----------------|----------|------------|
| **P0 - Critique** | Payment Card Data | PAN, CVV, PIN | Always Encrypted + HSM |
| **P1 - Hautement Sensible** | PII | SSN, passport, biometric | Column encryption + masking |
| **P2 - Sensible** | Financial | Bank account, balance | Dynamic data masking |
| **P3 - Interne** | Business metrics | Revenue, volume | Access control only |
| **P4 - Public** | Product info | Pricing, features | No special protection |

#### Encryption Strategy

**At Rest (Storage):**
```
Azure SQL Database:
  - TDE with service-managed keys (default)
  - Always Encrypted for CardNumber column
  
Azure Synapse:
  - Customer-managed keys (CMK) via Key Vault
  - Transparent to applications
  
Azure Cosmos DB:
  - Automatic encryption (AES-256)
  - No performance impact

Azure Storage:
  - Storage Service Encryption (SSE)
  - Optional: Customer-provided keys
```

**In Transit (Network):**
```
All Services:
  - TLS 1.2 minimum (TLS 1.3 preferred)
  - Perfect Forward Secrecy (PFS) enabled
  - Strong cipher suites only:
    • TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
    • TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

---

## Identity & Access Management

### RBAC Role Assignments

#### Production Environment Roles

| Role | Azure AD Group | Permissions | Resources |
|------|----------------|-------------|-----------|
| **Data Engineer** | sg-data-engineers-prod | Read/Write on ADF, Synapse | All ETL resources |
| **Data Analyst** | sg-data-analysts-prod | Read-only on Synapse | OLAP tables only |
| **DBA** | sg-dba-prod | Admin on SQL Database | OLTP + backups |
| **Security Team** | sg-security-prod | Read all logs, manage policies | All resources |
| **ML Engineer** | sg-ml-engineers-prod | Read/Write on ML workspace | ML + Cosmos DB |
| **DevOps** | sg-devops-prod | Deploy infrastructure | Terraform state |

#### Managed Identities (Passwordless)

```
Azure Data Factory:
  → Managed Identity: stripe-data-prod-adf
  → Permissions:
    - SQL Database: db_datareader, db_datawriter
    - Synapse: db_owner on staging schema
    - Cosmos DB: Cosmos DB Data Contributor
    - Storage: Storage Blob Data Contributor

Azure Synapse:
  → Managed Identity: stripe-data-prod-synapse
  → Permissions:
    - Storage: Storage Blob Data Owner
    - Key Vault: Get secrets (for CMK)

Azure Functions (Fraud ML):
  → Managed Identity: stripe-data-prod-func
  → Permissions:
    - Cosmos DB: Cosmos DB Data Reader
    - ML Workspace: AzureML Data Scientist
```

---

## Monitoring & Alerting

### Azure Sentinel (SIEM)

**Detection Rules Critiques :**

1. **Suspicious SQL Activity**
   - Failed login attempts > 5 in 5 minutes
   - Unusual query patterns (e.g., SELECT * on large tables)
   - Schema modifications outside maintenance windows

2. **Anomalous Data Access**
   - Access to PII columns by non-authorized users
   - Bulk data exports (> 10,000 rows)
   - After-hours access by analysts

3. **Network Anomalies**
   - Traffic from blacklisted IPs
   - Unusual geo-locations (e.g., country change within 1 hour)
   - Port scanning attempts

4. **Compliance Violations**
   - TLS 1.0/1.1 connection attempts
   - Unencrypted data transmission detected
   - Failed MFA authentications

### Key Metrics (SLA)

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **Mean Time to Detect (MTTD)** | < 5 min | > 10 min |
| **Mean Time to Respond (MTTR)** | < 30 min | > 1 hour |
| **False Positive Rate** | < 5% | > 10% |
| **Security Incidents/Month** | 0 | > 1 |
| **Failed Access Attempts** | < 10/day | > 50/day |

---

## Incident Response Plan

### Severity Levels

| Severity | Definition | Response Time | Escalation |
|----------|------------|---------------|------------|
| **P0 - Critical** | Data breach, ransomware | < 15 min | CEO + CISO |
| **P1 - High** | Unauthorized access, DDoS | < 1 hour | VP Engineering |
| **P2 - Medium** | Policy violation, malware | < 4 hours | Security Lead |
| **P3 - Low** | Failed login spike, phishing | < 24 hours | Security Analyst |

### Incident Response Workflow

```
1. DETECTION (Automated)
   ├─ Azure Sentinel alert triggered
   ├─ PagerDuty notification sent
   └─ War room channel created (#incident-YYYYMMDD)

2. TRIAGE (< 15 minutes)
   ├─ Assess severity (P0-P3)
   ├─ Identify affected systems
   └─ Activate response team

3. CONTAINMENT (< 1 hour for P0)
   ├─ Isolate affected resources (NSG rules)
   ├─ Revoke compromised credentials
   ├─ Enable enhanced logging
   └─ Preserve evidence (snapshot VMs, export logs)

4. ERADICATION (< 4 hours)
   ├─ Remove malware/backdoors
   ├─ Patch vulnerabilities
   └─ Reset all potentially compromised passwords

5. RECOVERY (< 24 hours)
   ├─ Restore from clean backups
   ├─ Validate data integrity
   └─ Gradual service restoration

6. POST-MORTEM (< 7 days)
   ├─ Root cause analysis
   ├─ Document lessons learned
   ├─ Update runbooks
   └─ Communicate to stakeholders
```

---

## Structure des Dossiers

```
security/
├── README.md                          # Ce fichier
├── security_framework.md              # Framework détaillé
├── disaster_recovery.md               # Plan DR complet
├── compliance/
│   ├── compliance_matrix.md           # Matrice de conformité
│   ├── gdpr/
│   │   └── gdpr_compliance_plan.md
│   ├── pci-dss/
│   │   └── pci_dss_compliance_plan.md
│   └── ccpa/
│       └── ccpa_compliance_plan.md
├── policies/
│   ├── azure_policies.json            # Azure Policy definitions
│   ├── rbac_roles.json                # Custom RBAC roles
│   └── data_classification.md         # Data classification guide
└── monitoring/
    ├── sentinel_rules.json            # Sentinel detection rules
    ├── alert_rules.json               # Azure Monitor alerts
    └── audit_queries.kql              # KQL queries for auditing
```

---

## Références

### Documentation Officielle
- [Azure Security Best Practices](https://learn.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)
- [PCI-DSS v4.0](https://www.pcisecuritystandards.org/)
- [GDPR Official Text](https://gdpr-info.eu/)
- [CCPA Regulations](https://oag.ca.gov/privacy/ccpa)

### Stripe Security
- [Stripe Security Guide](https://stripe.com/files/security/stripe-security-guide.pdf)
- [Stripe Compliance Programs](https://stripe.com/docs/security/guide)
- [Stripe Data Protection Addendum](https://stripe.com/legal/dpa)

### Outils
- [Azure Policy Samples](https://github.com/Azure/azure-policy)
- [Sentinel Detection Rules](https://github.com/Azure/Azure-Sentinel)
- [CIS Azure Foundations Benchmark](https://www.cisecurity.org/benchmark/azure)

---

## Contacts Sécurité

**Security Operations Center (SOC)**
- Email: soc@stripe.com
- Slack: #security-incidents
- PagerDuty: security-oncall
- Phone: +1-XXX-XXX-XXXX (24/7)

**Data Protection Officer (DPO)**
- Email: dpo@stripe.com
- Pour questions GDPR uniquement

**Incident Commander (On-call)**
- Rotation: Weekly (Monday 00:00 UTC)
- Escalation path: SOC → Security Lead → CISO → CEO