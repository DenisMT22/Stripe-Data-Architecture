# Modèle OLAP - Stripe Analytique

## Objectif

Data Warehouse analytique pour :
- Analyses multi-dimensionnelles des revenus
- Segmentation clients avancée
- Reporting de conformité
- Business Intelligence et tableaux de bord
- Support des décisions stratégiques

## Architecture OLAP

### Choix technologique : **Azure Synapse Analytics**

**Justification** :
- Traitement massivement parallèle (MPP)
- Columnstore indexes natifs (compression 10x)
- Intégration native avec Power BI
- Scaling indépendant compute/storage
- Requêtes complexes sur pétabytes de données

### Configuration recommandée
- **Tier** : Gen2 DW500c (scalable jusqu'à DW30000c)
- **Distribution** : Hash sur clés métier
- **Partitionnement** : Par mois sur colonnes date
- **Indexes** : Clustered Columnstore (par défaut)
- **Backup** : Snapshots automatiques toutes les 8h

---

## Principes de conception

### Star Schema (Schéma en étoile)
```
                    ┌─────────────────┐
                    │  DIM_TIME       │
                    └────────┬────────┘
                             │
    ┌─────────────┐          │          ┌─────────────┐
    │ DIM_CUSTOMER├──────────┼──────────┤ DIM_MERCHANT│
    └─────────────┘          │          └─────────────┘
                             │
                    ┌────────▼────────┐
                    │                 │
                    │ FACT_TRANSACTION│ ← Table de faits centrale
                    │                 │
                    └────────┬────────┘
                             │
    ┌─────────────┐          │          ┌─────────────┐
    │DIM_PAYMENT  ├──────────┼──────────┤ DIM_GEOGRAPHY│
    │   METHOD    │          │          └─────────────┘
    └─────────────┘          │
                             │
                    ┌────────▼────────┐
                    │  DIM_PRODUCT    │
                    └─────────────────┘
```

**Avantages du Star Schema** :
- Requêtes simples et rapides (peu de joins)
- Compréhensible par les analystes métier
- Optimisé pour les agrégations
- Performance prévisible

**Snowflake Schema** :
- Plus de joins (sous-dimensions normalisées)
- Plus complexe
- Moins de redondance de données

**Choix : Star Schema** pour performance et simplicité.

---

## Modèle de Données Détaillé

### 1. FACT_TRANSACTIONS (Table de Faits)

**Description** : Faits granulaires - une ligne par transaction.

| Colonne | Type | Description | Clé/Index |
|---------|------|-------------|-----------|
| **transaction_key** | BIGINT | Surrogate key | PK |
| transaction_id | BIGINT | ID source OLTP | Business key |
| **time_key** | INT | FK → dim_time | FK, Partition |
| **customer_key** | INT | FK → dim_customer | FK, Distribution |
| **merchant_key** | INT | FK → dim_merchant | FK |
| **payment_method_key** | INT | FK → dim_payment_method | FK |
| **geography_key** | INT | FK → dim_geography | FK |
| **product_key** | INT | FK → dim_product | FK |
| **Mesures (Metrics)** | | | |
| amount | DECIMAL(18,2) | Montant transaction | |
| processing_fee | DECIMAL(18,2) | Frais Stripe | |
| net_amount | DECIMAL(18,2) | Montant net marchand | |
| refund_amount | DECIMAL(18,2) | Montant remboursé | |
| chargeback_amount | DECIMAL(18,2) | Montant contesté | |
| **Flags** | | | |
| is_successful | BIT | Transaction réussie | |
| is_refunded | BIT | Transaction remboursée | |
| is_disputed | BIT | Litige en cours | |
| is_fraudulent | BIT | Fraude détectée | |
| **Compteurs** | | | |
| transaction_count | INT | Toujours 1 (pour SUM) | |
| **Timestamps** | | | |
| transaction_datetime | DATETIME2 | Date/heure exacte | |
| inserted_at | DATETIME2 | Date insertion DWH | |
| updated_at | DATETIME2 | Dernière mise à jour | |

**Distribution** : HASH(customer_key) - répartir la charge
**Partitionnement** : RANGE(time_key) - par mois
**Index** : Clustered Columnstore

**Volumétrie annuelle** : ~100M lignes → ~30 GB compressé

---

### 2. DIM_TIME (Dimension Temps)

**Description** : Dimension calendaire pré-calculée.

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| **time_key** | INT | PK (YYYYMMDD) | 20251016 |
| full_date | DATE | Date complète | 2025-10-16 |
| year | SMALLINT | Année | 2025 |
| quarter | TINYINT | Trimestre (1-4) | 4 |
| month | TINYINT | Mois (1-12) | 10 |
| month_name | NVARCHAR(20) | Nom du mois | Octobre |
| week_of_year | TINYINT | Semaine (1-53) | 42 |
| day_of_month | TINYINT | Jour du mois (1-31) | 16 |
| day_of_week | TINYINT | Jour semaine (1-7) | 4 |
| day_name | NVARCHAR(20) | Nom du jour | Jeudi |
| is_weekend | BIT | Weekend ? | 0 |
| is_holiday | BIT | Jour férié ? | 0 |
| fiscal_year | SMALLINT | Année fiscale | 2025 |
| fiscal_quarter | TINYINT | Trimestre fiscal | 4 |
| fiscal_period | TINYINT | Période fiscale | 10 |

**Type** : Dimension conforme (shared)
**Granularité** : Jour
**Période** : 2010-2035 (25 ans) → ~9,000 lignes
**Distribution** : REPLICATE (petit volume)

**Usage** : Filtres temporels, agrégations par période

---

### 3. DIM_CUSTOMER (Dimension Client)

**Description** : Type 2 SCD (Slowly Changing Dimension) pour historisation.

| Colonne | Type | Description |
|---------|------|-------------|
| **customer_key** | INT | Surrogate key PK |
| customer_id | BIGINT | Business key (OLTP) |
| email | NVARCHAR(255) | Email client |
| first_name | NVARCHAR(100) | Prénom |
| last_name | NVARCHAR(100) | Nom |
| full_name | NVARCHAR(200) | Prénom + Nom |
| country_code | CHAR(2) | Pays |
| country_name | NVARCHAR(100) | Nom pays |
| risk_score | DECIMAL(5,2) | Score de risque |
| risk_category | NVARCHAR(20) | LOW, MEDIUM, HIGH |
| is_verified | BIT | Email vérifié |
| customer_segment | NVARCHAR(50) | VIP, Regular, New |
| lifetime_value | DECIMAL(18,2) | CLV |
| **SCD Type 2 fields** | | |
| effective_date | DATE | Date début validité |
| expiration_date | DATE | Date fin validité |
| is_current | BIT | Version actuelle |
| version | INT | Numéro de version |

**Distribution** : REPLICATE ou ROUND_ROBIN
**Volumétrie** : ~15M lignes (avec historique)

**Type 2 SCD** : Permet de tracker les changements (ex: client change de segment)

---

### 4. DIM_MERCHANT (Dimension Commerçant)

**Description** : Informations sur les marchands (Type 2 SCD).

| Colonne | Type | Description |
|---------|------|-------------|
| **merchant_key** | INT | Surrogate key PK |
| merchant_id | BIGINT | Business key |
| business_name | NVARCHAR(255) | Nom commercial |
| legal_name | NVARCHAR(255) | Raison sociale |
| email | NVARCHAR(255) | Email |
| country_code | CHAR(2) | Pays |
| country_name | NVARCHAR(100) | Nom pays |
| industry | NVARCHAR(100) | Secteur |
| industry_group | NVARCHAR(50) | Groupe sectoriel |
| mcc_code | CHAR(4) | Code catégorie |
| mcc_description | NVARCHAR(200) | Description MCC |
| is_active | BIT | Actif |
| kyc_status | NVARCHAR(20) | Statut KYC |
| merchant_tier | NVARCHAR(20) | STARTUP, SMB, ENTERPRISE |
| **SCD Type 2 fields** | | |
| effective_date | DATE | Date début validité |
| expiration_date | DATE | Date fin validité |
| is_current | BIT | Version actuelle |
| version | INT | Numéro de version |

**Distribution** : REPLICATE
**Volumétrie** : ~150K lignes

---

### 5. DIM_PAYMENT_METHOD (Dimension Moyen de Paiement)

**Description** : Types de paiement utilisés.

| Colonne | Type | Description |
|---------|------|-------------|
| **payment_method_key** | INT | Surrogate key PK |
| payment_method_id | BIGINT | Business key |
| type | NVARCHAR(20) | CARD, SEPA, WALLET |
| type_description | NVARCHAR(100) | Description complète |
| card_brand | NVARCHAR(20) | VISA, MASTERCARD, AMEX |
| card_brand_category | NVARCHAR(50) | Credit, Debit, Prepaid |
| card_type | NVARCHAR(20) | Credit, Debit |
| issuing_bank | NVARCHAR(100) | Banque émettrice |
| issuing_country | CHAR(2) | Pays émetteur |
| is_digital_wallet | BIT | Apple Pay, Google Pay |
| processing_cost_pct | DECIMAL(5,4) | % coût traitement |

**Distribution** : REPLICATE
**Volumétrie** : ~20M lignes

---

### 6. DIM_GEOGRAPHY (Dimension Géographique)

**Description** : Hiérarchie géographique.

| Colonne | Type | Description |
|---------|------|-------------|
| **geography_key** | INT | Surrogate key PK |
| country_code | CHAR(2) | Code pays ISO |
| country_name | NVARCHAR(100) | Nom pays |
| region | NVARCHAR(50) | Europe, Americas, Asia |
| sub_region | NVARCHAR(50) | Western Europe, etc. |
| continent | NVARCHAR(50) | Europe, Asia, etc. |
| currency_code | CHAR(3) | EUR, USD, GBP |
| currency_name | NVARCHAR(50) | Euro, Dollar |
| timezone | NVARCHAR(50) | UTC+1, UTC-5 |
| gdp_per_capita | DECIMAL(18,2) | PIB par habitant |
| population | BIGINT | Population |
| internet_penetration | DECIMAL(5,2) | % accès internet |
| is_gdpr_country | BIT | Sous GDPR |
| is_high_risk | BIT | Pays à risque fraude |

**Distribution** : REPLICATE
**Volumétrie** : ~250 lignes (pays)

---

### 7. DIM_PRODUCT (Dimension Produit)

**Description** : Produits/services Stripe.

| Colonne | Type | Description |
|---------|------|-------------|
| **product_key** | INT | Surrogate key PK |
| product_code | NVARCHAR(50) | Code produit |
| product_name | NVARCHAR(100) | Nom produit |
| product_category | NVARCHAR(50) | Payment, Subscription, etc. |
| product_family | NVARCHAR(50) | Core, Premium |
| pricing_model | NVARCHAR(20) | Fixed, Percentage |
| base_fee | DECIMAL(18,2) | Frais de base |
| percentage_fee | DECIMAL(5,4) | % frais |
| is_active | BIT | Produit actif |

**Distribution** : REPLICATE
**Volumétrie** : ~100 lignes

---

## Tables Agrégées (Pre-computed)

### AGG_DAILY_REVENUE (Agrégation Quotidienne)

**Description** : Revenus agrégés par jour pour performance.

| Colonne | Type | Description |
|---------|------|-------------|
| **agg_key** | BIGINT | PK |
| date_key | INT | FK → dim_time |
| merchant_key | INT | FK → dim_merchant |
| geography_key | INT | FK → dim_geography |
| payment_method_key | INT | FK → dim_payment_method |
| **Metrics** | | |
| transaction_count | INT | Nombre transactions |
| successful_count | INT | Réussies |
| failed_count | INT | Échouées |
| refunded_count | INT | Remboursées |
| total_amount | DECIMAL(18,2) | Montant total |
| total_fees | DECIMAL(18,2) | Frais totaux |
| total_net | DECIMAL(18,2) | Net total |
| avg_transaction_amount | DECIMAL(18,2) | Montant moyen |
| max_transaction_amount | DECIMAL(18,2) | Montant max |
| unique_customers | INT | Clients uniques |

**Distribution** : HASH(merchant_key)
**Partitionnement** : RANGE(date_key)
**Refresh** : Incrémental quotidien (via ETL)

**Volumétrie** : ~50M lignes/an

---

### AGG_MONTHLY_METRICS (Agrégation Mensuelle)

**Description** : Métriques mensuelles pour reporting exécutif.

| Colonne | Type | Description |
|---------|------|-------------|
| **agg_key** | BIGINT | PK |
| year_month | INT | YYYYMM |
| merchant_key | INT | FK |
| **KPIs** | | |
| gross_revenue | DECIMAL(18,2) | Revenus bruts |
| net_revenue | DECIMAL(18,2) | Revenus nets |
| transaction_count | INT | Nb transactions |
| unique_customers | INT | Clients uniques |
| new_customers | INT | Nouveaux clients |
| returning_customers | INT | Clients récurrents |
| avg_order_value | DECIMAL(18,2) | Panier moyen |
| customer_lifetime_value | DECIMAL(18,2) | CLV moyen |
| churn_rate | DECIMAL(5,2) | % désabonnements |
| refund_rate | DECIMAL(5,2) | % remboursements |
| chargeback_rate | DECIMAL(5,2) | % litiges |
| fraud_rate | DECIMAL(5,2) | % fraude |

**Distribution** : HASH(merchant_key)
**Refresh** : Mensuel (fin de mois)

**Volumétrie** : ~1M lignes

---

## Stratégies ETL

### Pipeline ETL : OLTP → OLAP
```
┌─────────────┐
│  OLTP       │
│  Azure SQL  │
└──────┬──────┘
       │
       │ Azure Data Factory / Airflow
       │ CDC (Change Data Capture)
       │
       ▼
┌─────────────┐
│  STAGING    │
│  (Blob)     │
└──────┬──────┘
       │
       │ Transformations
       │ - Lookup dimensions
       │ - Calculate metrics
       │ - Data quality checks
       │
       ▼
┌─────────────┐
│  OLAP       │
│  Synapse    │
└─────────────┘
```

### Fréquences de chargement

| Table | Fréquence | Méthode |
|-------|-----------|---------|
| FACT_TRANSACTIONS | Temps réel (5 min) | Incremental (CDC) |
| DIM_CUSTOMER | Quotidien | Full + SCD Type 2 |
| DIM_MERCHANT | Quotidien | Full + SCD Type 2 |
| DIM_TIME | Une fois | Pre-load |
| DIM_GEOGRAPHY | Mensuel | Full |
| AGG_DAILY_REVENUE | Quotidien | Incremental |
| AGG_MONTHLY_METRICS | Mensuel | Full recompute |

### Transformations clés

**1. Surrogate Keys** :
```sql
-- Lookup customer_key from customer_id
SELECT customer_key 
FROM dim_customer 
WHERE customer_id = @source_customer_id 
  AND is_current = 1
```

**2. SCD Type 2** :
```sql
-- Si client change de segment
UPDATE dim_customer 
SET expiration_date = GETDATE(), is_current = 0
WHERE customer_id = @id AND is_current = 1;

INSERT INTO dim_customer (customer_id, segment, effective_date, is_current, version)
VALUES (@id, @new_segment, GETDATE(), 1, @version + 1);
```

**3. Agrégations** :
```sql
-- Calculer daily revenue
INSERT INTO agg_daily_revenue
SELECT 
    date_key,
    merchant_key,
    COUNT(*) as transaction_count,
    SUM(amount) as total_amount,
    AVG(amount) as avg_amount
FROM fact_transactions
WHERE date_key = @yesterday
GROUP BY date_key, merchant_key;
```

---

## Optimisations de Performance

### 1. Distribution Strategy

**HASH Distribution** :
- `fact_transactions` : HASH(customer_key)
  - Répartit uniformément les données
  - Optimise les joins sur customer_key

**REPLICATE Distribution** :
- Toutes les dimensions (petites tables < 2 GB)
  - Copie sur tous les nœuds
  - Élimine data movement sur les joins

### 2. Partitionnement
```sql
-- Partitionnement mensuel de fact_transactions
CREATE TABLE fact_transactions
(...) 
WITH (
    DISTRIBUTION = HASH(customer_key),
    CLUSTERED COLUMNSTORE INDEX,
    PARTITION (time_key RANGE RIGHT 
        FOR VALUES (20250101, 20250201, 20250301, ...))
);
```

**Avantages** :
- Partition elimination (skip partitions)
- Archivage facile (switch partition)
- Maintenance parallèle

### 3. Indexes

**Clustered Columnstore** (par défaut) :
- Compression 10x
- Scan ultra-rapide
- Parfait pour agrégations

**Nonclustered Indexes** (si nécessaire) :
- Sur colonnes de filtres fréquents
- Exemple : `CREATE INDEX idx_merchant ON fact_transactions(merchant_key)`

### 4. Materialized Views
```sql
-- Vue matérialisée pour métriques fréquentes
CREATE MATERIALIZED VIEW mv_merchant_daily_summary
WITH (DISTRIBUTION = HASH(merchant_key))
AS
SELECT 
    merchant_key,
    date_key,
    SUM(amount) as total_revenue,
    COUNT(*) as transaction_count
FROM fact_transactions
GROUP BY merchant_key, date_key;
```

**Refresh** : Automatique ou manuel

---

## Volumétrie et Dimensionnement

### Estimation sur 3 ans

| Table | Lignes | Taille (GB) |
|-------|--------|-------------|
| FACT_TRANSACTIONS | 300M | 90 |
| AGG_DAILY_REVENUE | 150M | 30 |
| AGG_MONTHLY_METRICS | 3M | 1 |
| DIM_CUSTOMER | 15M | 5 |
| DIM_MERCHANT | 150K | 0.1 |
| DIM_TIME | 9K | 0.001 |
| DIM_GEOGRAPHY | 250 | 0.001 |
| DIM_PAYMENT_METHOD | 20M | 3 |
| DIM_PRODUCT | 100 | 0.001 |
| **TOTAL** | | **~130 GB** |

**Avec compression Columnstore** : ~13 GB réels

---

## Sécurité et Conformité

### Row-Level Security (RLS)
```sql
-- Exemple : Merchant voit uniquement ses données
CREATE FUNCTION fn_merchant_predicate(@merchant_key INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result
WHERE @merchant_key = CAST(SESSION_CONTEXT(N'merchant_key') AS INT);

CREATE SECURITY POLICY merchant_filter
ADD FILTER PREDICATE dbo.fn_merchant_predicate(merchant_key)
ON dbo.fact_transactions
WITH (STATE = ON);
```

### Column-Level Security
```sql
-- Masquer emails pour certains rôles
GRANT SELECT ON dim_customer(customer_key, full_name, country_code) TO analyst_role;
-- PAS accès à email
```

### Dynamic Data Masking
```sql
ALTER TABLE dim_customer
ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()');
-- Analystes voient : jXXX@XXXX.com
```

---

## Cas d'Usage Principaux

### 1. Executive Dashboard

- Revenue trends (MoM, YoY)
- Customer acquisition & retention
- Geographic expansion
- Product performance

### 2. Merchant Analytics

- Transaction volume
- Success rates
- Customer behavior
- Refund analysis

### 3. Fraud Analytics

- Fraud patterns by geography
- High-risk customer segments
- Suspicious transaction patterns

### 4. Compliance Reporting

- PCI-DSS audit trails
- GDPR data access logs
- AML transaction monitoring

