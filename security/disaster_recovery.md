# Plan de Continuité d'Activité et Disaster Recovery

## Objectifs et Définitions

### Métriques Clés

| Métrique | Définition | Target | Industry Benchmark |
|----------|------------|--------|-------------------|
| **RTO** (Recovery Time Objective) | Temps max avant restauration service | 4 hours | 4-8 hours |
| **RPO** (Recovery Point Objective) | Perte de données max acceptable | 1 hour | 1-4 hours |
| **MTTR** (Mean Time To Recover) | Temps moyen de récupération | 2 hours | 2-6 hours |
| **RLO** (Recovery Level Objective) | % de capacité à restaurer | 80% | 70-90% |

**Criticité des services :**

| Service | Criticité | RTO | RPO | Justification |
|---------|-----------|-----|-----|---------------|
| **Payment Processing** | P0 | 15 min | 0 min | Revenus directs |
| **Fraud Detection** | P0 | 30 min | 5 min | Pertes fraude |
| **OLTP Database** | P0 | 1 hour | 5 min | Données transactionnelles |
| **OLAP Analytics** | P1 | 8 hours | 24 hours | Reporting non-critique |
| **NoSQL (Cosmos DB)** | P1 | 2 hours | 1 hour | Features ML |
| **ETL Pipelines** | P2 | 24 hours | 24 hours | Batch non temps-réel |

---

## Scénarios de Désastre

### Scénario 1 : Panne Azure Region (West Europe)

**Probabilité :** Faible (0.1% / an)  
**Impact :** Critique (perte complète service)

**Déclencheurs :**
- Azure Service Health alert (region-wide outage)
- Monitoring shows 100% unavailability > 15 minutes
- Azure Status confirms major incident

**Response Plan :**

```
T+0 min: DETECTION
├─ Azure Monitor alert: "Region West Europe unavailable"
├─ PagerDuty escalation to on-call SRE
└─ War room activated (#incident-region-outage)

T+5 min: ASSESSMENT
├─ Confirm scope (entire region vs specific services)
├─ Check secondary region (North Europe) status
├─ Estimate Azure ETA (if provided)
└─ Decision: Wait or Failover

T+15 min: FAILOVER DECISION (if Azure ETA > 1 hour)
├─ Activate DR plan
├─ CEO approval obtained
└─ Communication plan activated

T+20 min: DNS FAILOVER
├─ Update Azure Traffic Manager
│  Primary: westeurope (priority 1) → OFFLINE
│  Secondary: northeurope (priority 2) → ACTIVE
├─ TTL: 60 seconds (propagation < 2 min)
└─ Verify: curl -I https://api.stripe.com

T+30 min: DATABASE FAILOVER
├─ Azure SQL: Automatic failover to secondary
├─ Synapse: Manual restore from geo-backup
├─ Cosmos DB: Automatic multi-region routing
└─ Verify: Test transactions

T+45 min: APPLICATION RESTART
├─ Scale up secondary region capacity
│  AKS nodes: 10 → 50 (autoscale)
│  App Services: Standard → Premium tier
├─ Validate payment flow end-to-end
└─ Monitor error rates < 0.1%

T+60 min: FULL RECOVERY
├─ All services operational in secondary region
├─ RTO achieved: 60 minutes (target: 4 hours)
└─ Incident commander: "Service restored"

POST-INCIDENT
├─ Monitor stability (24 hours)
├─ Failback to primary (when Azure confirms recovery)
├─ Post-mortem (within 5 days)
└─ Update runbook with lessons learned
```

**Coût du Failover :**
- Inaction (1 hour downtime): ~$500K revenue loss
- Failover opex (24h secondary region): ~$15K
- **Decision : Failover is cost-effective**

---

### Scénario 2 : Ransomware Attack

**Probabilité :** Moyenne (2% / an)  
**Impact :** Critique (chiffrement données)

**Indicateurs d'attaque :**
- Azure Sentinel: "Unusual file encryption activity"
- SQL Database: "Suspicious TRUNCATE commands"
- Storage: "Mass deletion of blobs detected"

**Response Plan :**

```
T+0: DETECTION
├─ Sentinel alert: "Ransomware indicators"
├─ Automated isolation: NSG rules block all traffic
└─ Snapshots triggered (before further damage)

T+5: CONTAINMENT
├─ Disable compromised accounts
├─ Rotate all secrets (Key Vault)
├─ Forensic image of affected VMs
└─ Contact cyber insurance (policy #XXX)

T+15: ASSESSMENT
├─ Identify patient zero (entry point)
├─ List affected systems
│  • SQL Database: Encrypted
│  • Synapse: Encrypted 
│  • Cosmos DB: Not affected (read-only attack)
│  • Storage: 30% files encrypted 
└─ Ransom note: "Pay 50 BTC or lose data"

T+30: DECISION (No Ransom Payment - Company Policy)
├─ CEO decision: Restore from backups
├─ FBI notification (mandatory for financial institutions)
├─ CNIL notification (GDPR data breach < 72h)
└─ Customer communication prepared

T+1h: RECOVERY INITIATION
├─ SQL Database: Point-in-time restore (T-1h)
│  • RPO: 1 hour 
│  • Duration: 45 minutes (250GB database)
├─ Synapse: Restore from geo-backup (T-24h)
│  • RPO: 24 hours (acceptable for analytics)
│  • Duration: 2 hours (5TB warehouse)
├─ Storage: Restore from immutable backups
│  • Duration: 4 hours (10TB data)
└─ Cosmos DB: No action needed

T+4h: VALIDATION
├─ Data integrity checks
│  SELECT COUNT(*) FROM Payment; -- Compare with pre-attack
├─ Transaction reconciliation
│  • Missing transactions: Re-process from Stripe API logs
├─ Customer impact assessment
│  • Transactions lost: 247 (during attack window)
│  • Action: Manual compensation
└─ Security hardening
   • Patch vulnerabilities
   • Update firewall rules
   • Enable MFA on all admin accounts

T+8h: RETURN TO NORMAL
├─ Services fully operational
├─ RTO: 8 hours (target: 4 hours) MISSED
├─ RPO: 1 hour ACHIEVED
└─ Post-incident review scheduled

FINANCIAL IMPACT
├─ Revenue loss (8h downtime): ~$4M
├─ Recovery costs: ~$500K
│  • Incident response team: $200K
│  • Data recovery services: $100K
│  • Legal/forensic: $150K
│  • Customer compensation: $50K
├─ Ransom NOT paid: $0 (50 BTC = $2.5M saved)
└─ Insurance claim: $3M recovered

LESSONS LEARNED
├─ Implement: Offline immutable backups (Azure Backup Vault)
├─ Improve: EDR on all endpoints (CrowdStrike)
├─ Reduce RTO: Automated failover scripts
└─ Training: Quarterly ransomware tabletop exercises
```

---

### Scénario 3 : Accidental Data Deletion

**Probabilité :** Haute (5% / an)  
**Impact :** Moyen à Critique

**Example Real Incident :**
```sql
-- Junior engineer accidentally runs in PROD:
DELETE FROM Payment;  -- OOPS! (instead of WHERE PaymentID = 123)

-- Result: 100M rows deleted in 2 seconds
```

**Prevention Layers :**

```
Layer 1: Soft Delete (Application Level)
  ALTER TABLE Payment ADD IsDeleted BIT DEFAULT 0;
  
  -- "DELETE" becomes UPDATE
  UPDATE Payment SET IsDeleted = 1, DeletedAt = GETDATE()
  WHERE PaymentID = 123;
  
  -- Queries filter automatically
  CREATE VIEW vw_Payment AS
  SELECT * FROM Payment WHERE IsDeleted = 0;

Layer 2: Database Permissions (Least Privilege)
  -- Engineers have read-only in PROD
  DENY DELETE ON Payment TO [data-engineers-group];
  
  -- Only DBAs can delete (and they use transactions)
  GRANT DELETE ON Payment TO [dba-group];

Layer 3: Transaction Wrapper (Mandatory)
  BEGIN TRANSACTION;
    DELETE FROM Payment WHERE PaymentID = 123;
    
    -- Manual validation before commit
    SELECT @@ROWCOUNT AS RowsAffected;
    -- Expected: 1 row. If > 100, something is wrong!
    
    -- ROLLBACK; or COMMIT;
  -- Auto-rollback if not committed within 5 minutes

Layer 4: Delayed Commit (10-second window)
  -- SQL Server 2019+ feature
  SET DELAYED_DURABILITY = FORCED;
  
  -- Gives 10 seconds to realize mistake and kill session
  KILL SESSION <SPID>;

Layer 5: Point-in-Time Restore (Last Resort)
  -- Azure SQL Database: Restore to 5 minutes before mistake
  az sql db restore \
    --resource-group stripe-rg-prod \
    --server stripe-prod-sql \
    --name stripe_oltp_db \
    --dest-name stripe_oltp_db_restored \
    --time "2025-10-20T14:55:00Z"
  
  -- Duration: ~30 minutes
  -- RPO: 5 minutes
```

**Recovery Metrics :**
- Detection: < 1 minute (monitoring query counts)
- Decision: < 5 minutes (incident commander approval)
- Restore: 30 minutes (PITR)
- Total RTO: 36 minutes

---

## Stratégie de Backup

### Backup Tiers (3-2-1 Rule)

```
3 Copies:
  1. Production data (West Europe)
  2. Local backup (West Europe, separate storage account)
  3. Geo-redundant backup (North Europe)

2 Different Media:
  1. Azure Managed Disks (online)
  2. Azure Blob Archive (offline, immutable)

1 Offsite:
  North Europe region (700 km from Paris)
```

### Backup Schedule

| Resource | Frequency | Retention | Type | RPO |
|----------|-----------|-----------|------|-----|
| **Azure SQL (OLTP)** | Continuous | 35 days | Automated | 5 min |
| **Synapse (OLAP)** | Daily | 7 days | Snapshot | 24 hours |
| **Cosmos DB** | Continuous | 7 days | Change Feed | 5 min |
| **Storage (ADLS)** | Hourly | 30 days | Incremental | 1 hour |
| **Configuration** | On change | 90 days | Git | 0 min |

### Backup Costs (Monthly)

```
Azure SQL Backup:
  • 250GB × 35 days = 8.75TB
  • LRS: $0.05/GB = $437.50
  • GRS: $0.10/GB = $875.00
  Total: $875/month

Synapse Backup:
  • 5TB × 7 days = 35TB (snapshots incremental)
  • Effective: 10TB
  • GRS: $0.10/GB = $1,000/month

Cosmos DB Backup:
  • Included in RU/s pricing (continuous backup mode)
  • $0 additional

Storage Backup:
  • 10TB × 30 days = 300TB (incremental)
  • Effective: 50TB
  • Archive tier: $0.002/GB = $100/month

Total Backup Costs: ~$2,000/month
  vs
Cost of Data Loss: $10M+ (unacceptable)

ROI: Infinite 
```

---

## Testing et Validation

### Disaster Recovery Drills

**Quarterly DR Test (Mandatory):**

```
Q1 2025 - Completed
  Scenario: SQL Database failover
  Result: RTO 2h15m (target: 4h)
  Issues: 
    - Documentation outdated (fixed)
    - Monitoring gaps (2 missing alerts added)

Q2 2025 - Scheduled June 15
  Scenario: Full region failover
  Participants: SRE, Eng, Product, Exec
  Duration: 4 hours
  Success Criteria:
    ✓ Payment processing restored < 1h
    ✓ All data integrity checks pass
    ✓ Zero data loss

Q3 2025 - Planned Sept 20
  Scenario: Ransomware attack simulation
  Red Team: External security firm
  Budget: $50K

Q4 2025 - Planned Dec 10
  Scenario: Accidental deletion + restore
  Focus: Human error scenarios
```

### Monitoring & Alerts

**Real-Time Health Checks:**

```
Azure Monitor Workbook: "DR Readiness"

Metrics:
  Backup Success Rate: 100% (last 30 days)
  Geo-Replication Lag: 12 seconds (target < 60s)
  Failover Test Age: 45 days (target < 90 days)
  Documentation Last Updated: 120 days (target < 90 days)

Alerts:
  CRITICAL: Backup failed 2 consecutive times
  WARNING: Geo-replication lag > 5 minutes
  INFO: DR test due in 14 days
```

---

## Runbooks

### Runbook 1: SQL Database Failover

```bash
#!/bin/bash
# File: runbooks/sql-failover.sh

# Step 1: Verify issue
echo "Checking SQL primary health..."
az sql db show --resource-group stripe-rg-prod \
               --server stripe-prod-sql-primary \
               --name stripe_oltp_db \
               --query "status"

# Step 2: Initiate failover
echo "Initiating failover to secondary..."
az sql failover-group failover \
  --resource-group stripe-rg-prod \
  --server stripe-prod-sql-primary \
  --name stripe-failover-group

# Step 3: Update DNS (if manual)
echo "Updating DNS records..."
az network traffic-manager endpoint update \
  --resource-group stripe-rg-prod \
  --profile-name stripe-tm-prod \
  --name sql-secondary \
  --type azureEndpoints \
  --priority 1

# Step 4: Validate
echo "Testing connectivity..."
sqlcmd -S stripe-prod-sql-secondary.database.windows.net \
       -d stripe_oltp_db \
       -Q "SELECT TOP 1 * FROM Payment ORDER BY CreatedAt DESC;"

# Step 5: Notify
curl -X POST https://hooks.slack.com/... \
  -d '{"text": "SQL failover completed successfully"}'

echo "Failover complete. Monitor for 15 minutes."
```

### Runbook 2: Restore from Backup

```sql
-- File: runbooks/restore-from-backup.sql

-- Step 1: Identify restore point
DECLARE @RestoreTime DATETIME2 = '2025-10-20T14:55:00';

-- Step 2: Create restore (Azure Portal or CLI)
-- az sql db restore (see Layer 5 above)

-- Step 3: Validate restored data
USE stripe_oltp_db_restored;
GO

SELECT 
    'Payment' AS TableName,
    COUNT(*) AS RowCount,
    MAX(CreatedAt) AS LatestRecord
FROM Payment
UNION ALL
SELECT 
    'Customer',
    COUNT(*),
    MAX(CreatedAt)
FROM Customer;

-- Step 4: Compare with production (before incident)
-- Expected: Restored DB has data up to @RestoreTime

-- Step 5: Swap databases (if validation OK)
ALTER DATABASE stripe_oltp_db MODIFY NAME = stripe_oltp_db_old;
ALTER DATABASE stripe_oltp_db_restored MODIFY NAME = stripe_oltp_db;

-- Step 6: Archive old database (keep for 7 days)
-- Manual cleanup after incident review
```

---

## Escalation & Communication

### Incident Severity Matrix

| Severity | Definition | Response Time | Escalation Path |
|----------|------------|---------------|-----------------|
| **P0** | Complete outage | < 5 min | On-call SRE → VP Eng → CEO |
| **P1** | Partial degradation | < 15 min | On-call SRE → Eng Manager |
| **P2** | Minor issues | < 1 hour | On-call SRE |
| **P3** | Planned maintenance | N/A | Email notification |

