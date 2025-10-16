# Modèle OLTP - Stripe Transactionnel

## Objectif

Base de données transactionnelle hautement performante pour gérer :
- Traitement des paiements en temps réel
- Gestion des clients et marchands
- Traçabilité complète des transactions
- Détection de fraude

## Architecture OLTP

### Choix technologique : **Azure SQL Database**

**Justification** :
- Support ACID complet
- Haute disponibilité (99.99% SLA)
- Scaling vertical et horizontal
- Geo-replication intégrée
- Conformité PCI-DSS certifiée

### Configuration recommandée
- **Tier** : Business Critical (HA)
- **vCores** : 8 (scalable jusqu'à 80)
- **Stockage** : 1 TB (auto-grow)
- **Backup** : Point-in-time restore (35 jours)
- **Réplication** : Active geo-replication (3 régions)

---

## Modèle de données

### Principes de conception

1. **Normalisation** : 3NF (Troisième Forme Normale)
2. **Intégrité référentielle** : Toutes FK avec contraintes
3. **Indexation stratégique** : Performance sur requêtes fréquentes
4. **Audit trail** : Colonnes created_at, updated_at partout
5. **Soft delete** : Colonne is_deleted (conformité GDPR)

### Entités principales
```
┌─────────────────┐
│    CUSTOMERS    │ ← Clients finaux
└─────────────────┘
│
├── 1:N ──→ PAYMENT_METHODS
│
└── 1:N ──→ TRANSACTIONS
                │
                ├── 1:N ──→ REFUNDS
                │
                └── 1:1 ──→ FRAUD_CHECKS

┌─────────────────┐
│    MERCHANTS    │ ← Commerçants
└─────────────────┘
│
├── 1:N ──→ TRANSACTIONS
│
└── 1:N ──→ SUBSCRIPTIONS
                 │
                 └── 1:N ──→ SUBSCRIPTION_PAYMENTS

```

---

## Définition des Tables

### 1. CUSTOMERS (Clients)

**Description** : Informations des clients finaux qui effectuent des paiements.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| customer_id | BIGINT | PK, IDENTITY | Identifiant unique |
| email | NVARCHAR(255) | UNIQUE, NOT NULL | Email du client |
| first_name | NVARCHAR(100) | NOT NULL | Prénom |
| last_name | NVARCHAR(100) | NOT NULL | Nom |
| phone | NVARCHAR(20) | NULL | Téléphone |
| country_code | CHAR(2) | NOT NULL | Code pays ISO (ex: FR, US) |
| is_verified | BIT | DEFAULT 0 | Email vérifié |
| risk_score | DECIMAL(5,2) | DEFAULT 0 | Score de risque (0-100) |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date création |
| updated_at | DATETIME2 | DEFAULT GETUTCDATE() | Date modification |
| is_deleted | BIT | DEFAULT 0 | Soft delete |

**Index** :
- PK : customer_id
- UNIQUE : email
- INDEX : country_code, risk_score

---

### 2. MERCHANTS (Commerçants)

**Description** : Entreprises qui acceptent les paiements via Stripe.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| merchant_id | BIGINT | PK, IDENTITY | Identifiant unique |
| business_name | NVARCHAR(255) | NOT NULL | Nom commercial |
| legal_name | NVARCHAR(255) | NOT NULL | Raison sociale |
| email | NVARCHAR(255) | UNIQUE, NOT NULL | Email professionnel |
| phone | NVARCHAR(20) | NOT NULL | Téléphone |
| country_code | CHAR(2) | NOT NULL | Pays d'enregistrement |
| industry | NVARCHAR(100) | NOT NULL | Secteur d'activité |
| mcc_code | CHAR(4) | NOT NULL | Merchant Category Code |
| is_active | BIT | DEFAULT 1 | Compte actif |
| kyc_status | NVARCHAR(20) | NOT NULL | Know Your Customer (PENDING, VERIFIED, REJECTED) |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date création |
| updated_at | DATETIME2 | DEFAULT GETUTCDATE() | Date modification |
| is_deleted | BIT | DEFAULT 0 | Soft delete |

**Index** :
- PK : merchant_id
- UNIQUE : email
- INDEX : country_code, is_active, kyc_status

---

### 3. PAYMENT_METHODS (Moyens de paiement)

**Description** : Moyens de paiement enregistrés par les clients.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| payment_method_id | BIGINT | PK, IDENTITY | Identifiant unique |
| customer_id | BIGINT | FK, NOT NULL | Référence client |
| type | NVARCHAR(20) | NOT NULL | Type (CARD, SEPA, WALLET) |
| card_brand | NVARCHAR(20) | NULL | Marque (VISA, MASTERCARD, AMEX) |
| last4 | CHAR(4) | NULL | 4 derniers chiffres |
| exp_month | TINYINT | NULL | Mois expiration |
| exp_year | SMALLINT | NULL | Année expiration |
| token | NVARCHAR(255) | UNIQUE, NOT NULL | Token sécurisé (PCI-DSS) |
| is_default | BIT | DEFAULT 0 | Moyen par défaut |
| is_active | BIT | DEFAULT 1 | Actif |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date création |
| updated_at | DATETIME2 | DEFAULT GETUTCDATE() | Date modification |
| is_deleted | BIT | DEFAULT 0 | Soft delete |

**Index** :
- PK : payment_method_id
- FK : customer_id → customers(customer_id)
- INDEX : customer_id, is_active

**Sécurité PCI-DSS** : Jamais de numéro de carte complet ou CVV !

---

### 4. TRANSACTIONS (Transactions)

**Description** : Table centrale - toutes les transactions de paiement.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| transaction_id | BIGINT | PK, IDENTITY | Identifiant unique |
| merchant_id | BIGINT | FK, NOT NULL | Référence marchand |
| customer_id | BIGINT | FK, NOT NULL | Référence client |
| payment_method_id | BIGINT | FK, NOT NULL | Moyen de paiement |
| amount | DECIMAL(18,2) | NOT NULL | Montant |
| currency | CHAR(3) | NOT NULL | Devise ISO (EUR, USD) |
| status | NVARCHAR(20) | NOT NULL | PENDING, SUCCEEDED, FAILED, REFUNDED |
| payment_intent_id | NVARCHAR(100) | UNIQUE, NOT NULL | ID intention paiement |
| description | NVARCHAR(500) | NULL | Description |
| ip_address | NVARCHAR(45) | NULL | IP client (IPv4/IPv6) |
| user_agent | NVARCHAR(500) | NULL | User agent navigateur |
| device_type | NVARCHAR(20) | NULL | MOBILE, DESKTOP, TABLET |
| country_code | CHAR(2) | NULL | Pays transaction |
| failure_code | NVARCHAR(50) | NULL | Code erreur si échec |
| failure_message | NVARCHAR(500) | NULL | Message erreur |
| processing_fee | DECIMAL(18,2) | NULL | Frais Stripe |
| net_amount | DECIMAL(18,2) | NULL | Montant net marchand |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date transaction |
| updated_at | DATETIME2 | DEFAULT GETUTCDATE() | Date modification |
| is_deleted | BIT | DEFAULT 0 | Soft delete |

**Index** :
- PK : transaction_id
- FK : merchant_id, customer_id, payment_method_id
- UNIQUE : payment_intent_id
- INDEX : status, created_at, merchant_id, customer_id
- INDEX COMPOSITE : (merchant_id, created_at, status)

---

### 5. REFUNDS (Remboursements)

**Description** : Remboursements partiels ou totaux de transactions.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| refund_id | BIGINT | PK, IDENTITY | Identifiant unique |
| transaction_id | BIGINT | FK, NOT NULL | Transaction d'origine |
| amount | DECIMAL(18,2) | NOT NULL | Montant remboursé |
| currency | CHAR(3) | NOT NULL | Devise |
| reason | NVARCHAR(50) | NOT NULL | REQUESTED_BY_CUSTOMER, FRAUDULENT, DUPLICATE |
| status | NVARCHAR(20) | NOT NULL | PENDING, SUCCEEDED, FAILED |
| description | NVARCHAR(500) | NULL | Description |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date demande |
| processed_at | DATETIME2 | NULL | Date traitement |
| is_deleted | BIT | DEFAULT 0 | Soft delete |

**Index** :
- PK : refund_id
- FK : transaction_id → transactions(transaction_id)
- INDEX : transaction_id, status

**Contrainte** : Le total des remboursements ne peut excéder le montant de la transaction.

---

### 6. CHARGEBACKS (Litiges)

**Description** : Contestations de paiement initiées par la banque du client.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| chargeback_id | BIGINT | PK, IDENTITY | Identifiant unique |
| transaction_id | BIGINT | FK, NOT NULL | Transaction contestée |
| amount | DECIMAL(18,2) | NOT NULL | Montant contesté |
| currency | CHAR(3) | NOT NULL | Devise |
| reason_code | NVARCHAR(20) | NOT NULL | Code raison (ex: 10.4 fraud) |
| reason_description | NVARCHAR(500) | NOT NULL | Description |
| status | NVARCHAR(20) | NOT NULL | OPEN, WON, LOST |
| evidence_due_date | DATETIME2 | NULL | Date limite preuves |
| resolved_at | DATETIME2 | NULL | Date résolution |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date contestation |
| is_deleted | BIT | DEFAULT 0 | Soft delete |

**Index** :
- PK : chargeback_id
- FK : transaction_id
- INDEX : status, created_at

---

### 7. FRAUD_CHECKS (Vérifications fraude)

**Description** : Analyse de fraude pour chaque transaction.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| fraud_check_id | BIGINT | PK, IDENTITY | Identifiant unique |
| transaction_id | BIGINT | FK, UNIQUE, NOT NULL | Transaction analysée |
| risk_score | DECIMAL(5,2) | NOT NULL | Score 0-100 |
| risk_level | NVARCHAR(20) | NOT NULL | LOW, MEDIUM, HIGH, CRITICAL |
| is_flagged | BIT | DEFAULT 0 | Transaction suspecte |
| ml_model_version | NVARCHAR(50) | NOT NULL | Version modèle ML |
| factors | NVARCHAR(MAX) | NULL | JSON - facteurs de risque |
| action_taken | NVARCHAR(20) | NULL | APPROVED, BLOCKED, REVIEW |
| reviewed_by | NVARCHAR(100) | NULL | Analyste (si review) |
| reviewed_at | DATETIME2 | NULL | Date review |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date analyse |

**Index** :
- PK : fraud_check_id
- FK : transaction_id (relation 1:1)
- INDEX : risk_level, is_flagged

---

### 8. SUBSCRIPTIONS (Abonnements)

**Description** : Abonnements récurrents.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| subscription_id | BIGINT | PK, IDENTITY | Identifiant unique |
| merchant_id | BIGINT | FK, NOT NULL | Marchand |
| customer_id | BIGINT | FK, NOT NULL | Client |
| payment_method_id | BIGINT | FK, NOT NULL | Moyen paiement |
| plan_name | NVARCHAR(100) | NOT NULL | Nom du plan |
| amount | DECIMAL(18,2) | NOT NULL | Montant récurrent |
| currency | CHAR(3) | NOT NULL | Devise |
| interval | NVARCHAR(20) | NOT NULL | DAILY, WEEKLY, MONTHLY, YEARLY |
| interval_count | INT | DEFAULT 1 | Fréquence (ex: tous les 3 mois) |
| status | NVARCHAR(20) | NOT NULL | ACTIVE, PAUSED, CANCELED |
| current_period_start | DATETIME2 | NOT NULL | Début période |
| current_period_end | DATETIME2 | NOT NULL | Fin période |
| cancel_at_period_end | BIT | DEFAULT 0 | Annulation à échéance |
| canceled_at | DATETIME2 | NULL | Date annulation |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date création |
| updated_at | DATETIME2 | DEFAULT GETUTCDATE() | Date modification |
| is_deleted | BIT | DEFAULT 0 | Soft delete |

**Index** :
- PK : subscription_id
- FK : merchant_id, customer_id, payment_method_id
- INDEX : status, current_period_end

---

### 9. SUBSCRIPTION_PAYMENTS (Paiements abonnements)

**Description** : Historique des paiements récurrents.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| subscription_payment_id | BIGINT | PK, IDENTITY | Identifiant unique |
| subscription_id | BIGINT | FK, NOT NULL | Abonnement |
| transaction_id | BIGINT | FK, NULL | Transaction associée |
| amount | DECIMAL(18,2) | NOT NULL | Montant |
| currency | CHAR(3) | NOT NULL | Devise |
| status | NVARCHAR(20) | NOT NULL | PENDING, SUCCEEDED, FAILED |
| attempt_count | INT | DEFAULT 1 | Nombre tentatives |
| next_retry_at | DATETIME2 | NULL | Prochaine tentative |
| failure_reason | NVARCHAR(500) | NULL | Raison échec |
| period_start | DATETIME2 | NOT NULL | Début période facturée |
| period_end | DATETIME2 | NOT NULL | Fin période facturée |
| created_at | DATETIME2 | DEFAULT GETUTCDATE() | Date création |
| processed_at | DATETIME2 | NULL | Date traitement |

**Index** :
- PK : subscription_payment_id
- FK : subscription_id, transaction_id
- INDEX : status, next_retry_at

---

##  Relations et Cardinalités
```
CUSTOMERS 1───N PAYMENT_METHODS
CUSTOMERS 1───N TRANSACTIONS
CUSTOMERS 1───N SUBSCRIPTIONS

MERCHANTS 1───N TRANSACTIONS
MERCHANTS 1───N SUBSCRIPTIONS

PAYMENT_METHODS N───1 CUSTOMERS
PAYMENT_METHODS 1───N TRANSACTIONS
PAYMENT_METHODS 1───N SUBSCRIPTIONS

TRANSACTIONS N───1 CUSTOMERS
TRANSACTIONS N───1 MERCHANTS
TRANSACTIONS N───1 PAYMENT_METHODS
TRANSACTIONS 1───N REFUNDS
TRANSACTIONS 1───N CHARGEBACKS
TRANSACTIONS 1───1 FRAUD_CHECKS

SUBSCRIPTIONS N───1 CUSTOMERS
SUBSCRIPTIONS N───1 MERCHANTS
SUBSCRIPTIONS N───1 PAYMENT_METHODS
SUBSCRIPTIONS 1───N SUBSCRIPTION_PAYMENTS

SUBSCRIPTION_PAYMENTS N───1 SUBSCRIPTIONS
SUBSCRIPTION_PAYMENTS 1───1 TRANSACTIONS (optionnel)
```

## Stratégies d'optimisation

### 1. Partitionnement

**Table TRANSACTIONS** (la plus volumineuse) :

-- Partitionnement par mois sur created_at
-- Facilite l'archivage et les requêtes par période

### 2. Index

**Index composites critiques** :

-- (merchant_id, created_at, status) : Requêtes dashboard marchand
-- (customer_id, created_at) : Historique client
-- (status, created_at) : Monitoring transactions

### 3. Archivage

**Stratégie** :

-- Transactions > 2 ans → Table TRANSACTIONS_ARCHIVE
-- Logs > 90 jours → Suppression
-- Soft delete : purge après 7 ans (conformité)

## Sécurité

### Données sensibles

-- Numéros cartes : JAMAIS stockés (tokenisation)
-- CVV/CVC: JAMAIS stockés
-- Emails:  Chiffrés at rest
-- Tokens paiement: Chiffrés + rotation

### Audit trail

Toutes les tables ont :
- `created_at` : Traçabilité création
- `updated_at` : Traçabilité modification
- `is_deleted` : Soft delete (GDPR)

---

## Volumétrie estimée (1 an)

| Table | Lignes | Taille |
|-------|--------|--------|
| TRANSACTIONS | 100M | ~50 GB |
| CUSTOMERS | 10M | ~5 GB |
| MERCHANTS | 100K | ~500 MB |
| PAYMENT_METHODS | 15M | ~7 GB |
| REFUNDS | 5M | ~2 GB |
| FRAUD_CHECKS | 100M | ~30 GB |
| SUBSCRIPTIONS | 2M | ~1 GB |
| **TOTAL** | | **~95 GB** |

**Note** : Basé sur moyennes industrie FinTech moyenne échelle.




