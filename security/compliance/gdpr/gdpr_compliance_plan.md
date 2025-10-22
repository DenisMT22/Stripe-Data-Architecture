# Plan de Conformité GDPR - Stripe Data Architecture

## Vue d'Ensemble

Le Règlement Général sur la Protection des Données (GDPR) est applicable depuis le 25 mai 2018 pour toutes les entreprises traitant des données de citoyens européens.

**Scope de conformité :**
- Stripe traite ~500M transactions/an en Europe
- Stockage de données dans West Europe (Paris)
- Sujets concernés : Customers, Merchants

---

## Les 7 Principes du GDPR

### 1. Lawfulness, Fairness and Transparency (Article 5)

**Implementation :**
```
Consentement explicite des utilisateurs
   - Cookie consent banner
   - Terms of Service acceptés
   - Privacy Policy accessible

Transparence du traitement
   - Documentation publique : stripe.com/privacy
   - Notification des modifications (30 jours avant)
   - Registre des activités de traitement

Base légale : Contrat (Article 6.1.b)
   - Nécessaire pour exécuter le service de paiement
```

**Preuves de conformité :**
- Registre des consentements dans `Customer` table
- Logs d'acceptation des T&C (horodatés)
- Historique des versions de Privacy Policy

---

### 2. Purpose Limitation (Article 5.1.b)

**Finalités déclarées :**

| Finalité | Base Légale | Données Collectées | Durée Conservation |
|----------|-------------|-------------------|-------------------|
| **Traitement des paiements** | Contrat | PAN, nom, adresse | 7 ans (obligation légale) |
| **Détection de fraude** | Intérêt légitime | IP, device fingerprint | 180 jours |
| **Analytics business** | Intérêt légitime | Transactions agrégées | Illimité (anonymisé) |
| **Marketing** | Consentement | Email | Jusqu'au retrait |

**Garanties :**
```sql
-- Interdiction d'utiliser les données pour d'autres finalités
-- Exemple : Les données de paiement ne peuvent PAS être vendues à des tiers

ALTER TABLE Customer
ADD CONSTRAINT chk_marketing_consent 
CHECK (MarketingConsent IN (0, 1));  -- Opt-in explicite
```

---

### 3. Data Minimisation (Article 5.1.c)

**Principe : Collecter uniquement le strict nécessaire**

#### Données NÉCESSAIRES (collectées)
```
Payment:
  CustomerID        → Identification du payeur
  Amount, Currency  → Montant de la transaction
  PaymentMethod     → Type de paiement (card, bank)
  Status            → État de la transaction
  CreatedAt         → Horodatage (obligation PCI-DSS)

Customer:
  Email             → Communication transactionnelle
  Country           → Conformité fiscale
  IsActive          → Gestion du compte
```

#### Données NON NÉCESSAIRES (exclues)
```
Date de naissance   → Non requis pour paiements
Genre               → Discrimination potentielle
Numéro de téléphone → Sauf si 2FA activé
Adresse physique    → Sauf si livraison physique
```

**Validation automatique :**
```python
# Script de validation GDPR
def validate_data_minimization(table_schema):
    required_fields = ['CustomerID', 'Email', 'Country']
    forbidden_fields = ['DateOfBirth', 'Gender', 'Race']
    
    for field in table_schema:
        if field in forbidden_fields:
            raise GDPRViolation(f"Field {field} violates data minimization")
```

---

### 4. Accuracy (Article 5.1.d)

**Mesures d'exactitude :**

```sql
-- Validation email en temps réel
CREATE TRIGGER trg_validate_email
ON Customer
AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM inserted 
        WHERE Email NOT LIKE '%_@__%.__%'
    )
    BEGIN
        RAISERROR('Invalid email format', 16, 1)
        ROLLBACK TRANSACTION
    END
END;

-- Mise à jour automatique des données obsolètes
CREATE PROCEDURE sp_Update_Customer_Data
AS
BEGIN
    -- Marquer les comptes inactifs > 2 ans
    UPDATE Customer
    SET IsActive = 0
    WHERE LastLoginDate < DATEADD(YEAR, -2, GETDATE());
    
    -- Notifier les utilisateurs pour mise à jour des données
    INSERT INTO NotificationQueue (CustomerID, Type, Message)
    SELECT CustomerID, 'DataUpdate', 'Please verify your account information'
    FROM Customer
    WHERE UpdatedAt < DATEADD(MONTH, -6, GETDATE());
END;
```

---

### 5. Storage Limitation (Article 5.1.e)

**Durées de conservation :**

| Type de Données | Durée | Justification | Après Expiration |
|-----------------|-------|---------------|-------------------|
| **Transaction history** | 7 ans | Obligation légale fiscale | Suppression automatique |
| **Fraud features** | 180 jours | Durée raisonnable ML | Suppression Cosmos DB (TTL) |
| **API logs** | 90 jours | Audit et debugging | Suppression Cosmos DB (TTL) |
| **User sessions** | 30 jours | Analytics court terme | Suppression Cosmos DB (TTL) |
| **Backup data** | 35 jours | Disaster recovery | Rotation automatique |

**Implémentation :**

```sql
-- Job de purge automatique (SQL Agent)
CREATE PROCEDURE sp_GDPR_Data_Retention
AS
BEGIN
    -- Supprimer transactions > 7 ans
    DELETE FROM Payment
    WHERE CreatedAt < DATEADD(YEAR, -7, GETDATE());
    
    -- Anonymiser données après 7 ans (alternative à suppression)
    UPDATE Payment
    SET 
        CustomerID = NULL,
        CardLastFour = 'XXXX',
        BillingAddress = 'REDACTED'
    WHERE CreatedAt BETWEEN DATEADD(YEAR, -7, GETDATE()) 
                        AND DATEADD(YEAR, -8, GETDATE());
    
    -- Supprimer comptes inactifs > 3 ans (avec notification préalable)
    DELETE FROM Customer
    WHERE IsActive = 0
      AND LastLoginDate < DATEADD(YEAR, -3, GETDATE())
      AND DeletionNotificationSent = 1
      AND DeletionNotificationDate < DATEADD(DAY, -30, GETDATE());
END;
```

---

### 6. Integrity and Confidentiality (Article 5.1.f)

**Mesures techniques :**

#### Encryption
```
At Rest:
  • Azure SQL: Transparent Data Encryption (TDE)
  • Synapse: Customer-managed keys (CMK)
  • Cosmos DB: Service-managed encryption (AES-256)
  • Storage: Storage Service Encryption (SSE)

In Transit:
  • TLS 1.3 enforced
  • Perfect Forward Secrecy
  • Certificate pinning on mobile apps
```

#### Access Controls
```
RBAC:
  • Principe du moindre privilège
  • Review trimestriel des permissions
  • Logs d'accès conservés 1 an

Authentication:
  • MFA obligatoire (production)
  • Rotation des clés (30 jours)
  • Session timeout (15 minutes inactivité)
```

#### Monitoring
```
Alerts:
  • Accès suspect aux données PII (> 1000 lignes)
  • Tentatives de connexion échouées (> 5)
  • Export massif de données
  • Modifications de schéma (hors maintenance)
```

---

### 7. Accountability (Article 5.2)

**Documentation obligatoire :**

#### Registre des Activités de Traitement (Article 30)

```yaml
Treatment:
  Name: "Payment Processing"
  Controller: Stripe, Inc.
  DPO: dpo@stripe.com
  Purpose: Execute payment transactions
  Legal Basis: Contract (Article 6.1.b)
  Categories of Data:
    - Personal identification (name, email)
    - Financial data (payment method, amount)
    - Transaction metadata (timestamp, IP)
  Categories of Recipients:
    - Payment processors (Visa, Mastercard)
    - Banking partners
    - Fraud detection services
  International Transfers: No (EU only)
  Retention Period: 7 years
  Security Measures:
    - Encryption (TDE, TLS 1.3)
    - Access control (RBAC)
    - Audit logging
  Last Updated: 2025-10-20
```

---

## Droits des Personnes (Chapitre III)

### Right of Access (Article 15)

**Implémentation :**

```sql
-- API endpoint: GET /api/gdpr/data-export
CREATE PROCEDURE sp_GDPR_Data_Export
    @CustomerID INT
AS
BEGIN
    -- Exporter toutes les données du client (format JSON)
    SELECT 
        'Customer' AS DataType,
        CustomerID,
        Email,
        Country,
        CreatedAt,
        UpdatedAt
    FROM Customer
    WHERE CustomerID = @CustomerID
    
    UNION ALL
    
    SELECT 
        'Payments' AS DataType,
        PaymentID,
        Amount,
        Currency,
        Status,
        CreatedAt
    FROM Payment
    WHERE CustomerID = @CustomerID
    
    UNION ALL
    
    SELECT 
        'Subscriptions' AS DataType,
        SubscriptionID,
        PlanID,
        Status,
        StartDate,
        EndDate
    FROM Subscription
    WHERE CustomerID = @CustomerID;
    
    -- Log de la demande (obligation GDPR)
    INSERT INTO GDPR_Request_Log (CustomerID, RequestType, ProcessedAt)
    VALUES (@CustomerID, 'DataExport', GETDATE());
END;
```

**SLA : Réponse sous 30 jours (Article 12.3)**

---

### Right to Erasure ("Right to be Forgotten") (Article 17)

**Implémentation :**

```sql
CREATE PROCEDURE sp_GDPR_Right_To_Be_Forgotten
    @CustomerID INT,
    @Reason NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    
    -- Vérifier si suppression autorisée
    IF EXISTS (
        SELECT 1 FROM Payment
        WHERE CustomerID = @CustomerID
          AND CreatedAt > DATEADD(YEAR, -7, GETDATE())
    )
    BEGIN
        -- Impossible de supprimer (obligation légale fiscale)
        INSERT INTO GDPR_Request_Log 
            (CustomerID, RequestType, Status, Reason, ProcessedAt)
        VALUES 
            (@CustomerID, 'Erasure', 'Rejected', 
             'Legal obligation: tax retention 7 years', GETDATE());
        
        ROLLBACK TRANSACTION;
        RETURN;
    END;
    
    -- Suppression cascade
    DELETE FROM Subscription WHERE CustomerID = @CustomerID;
    DELETE FROM Payment WHERE CustomerID = @CustomerID;
    DELETE FROM Dispute WHERE PaymentID IN (
        SELECT PaymentID FROM Payment WHERE CustomerID = @CustomerID
    );
    DELETE FROM Customer WHERE CustomerID = @CustomerID;
    
    -- Log de la suppression
    INSERT INTO GDPR_Request_Log 
        (CustomerID, RequestType, Status, Reason, ProcessedAt)
    VALUES 
        (@CustomerID, 'Erasure', 'Completed', @Reason, GETDATE());
    
    COMMIT TRANSACTION;
END;
```

**Exceptions légales :**
- Transactions < 7 ans : Obligation fiscale (Article 17.3.b)
- Litiges en cours : Établissement de droits (Article 17.3.e)
- Archives historiques : Intérêt public (Article 17.3.d)

---

### Right to Data Portability (Article 20)

**Format standard : JSON**

```json
{
  "customer": {
    "id": 12345,
    "email": "customer@example.com",
    "country": "FR",
    "created_at": "2023-01-15T10:30:00Z",
    "marketing_consent": false
  },
  "payments": [
    {
      "id": "pay_abc123",
      "amount": 5000,
      "currency": "EUR",
      "status": "succeeded",
      "created_at": "2024-06-20T14:23:45Z"
    }
  ],
  "subscriptions": [
    {
      "id": "sub_xyz789",
      "plan": "premium",
      "status": "active",
      "start_date": "2024-01-01",
      "billing_cycle": "monthly"
    }
  ],
  "export_metadata": {
    "exported_at": "2025-10-20T16:45:00Z",
    "format_version": "1.0",
    "data_controller": "Stripe, Inc."
  }
}
```

**API Implementation :**
```python
# Endpoint: POST /api/gdpr/data-portability
@app.route('/api/gdpr/data-portability', methods=['POST'])
@require_auth
def data_portability():
    customer_id = request.json['customer_id']
    
    # Récupérer toutes les données
    data = {
        "customer": get_customer_data(customer_id),
        "payments": get_payment_history(customer_id),
        "subscriptions": get_subscriptions(customer_id),
        "export_metadata": {
            "exported_at": datetime.utcnow().isoformat(),
            "format_version": "1.0",
            "data_controller": "Stripe, Inc."
        }
    }
    
    # Générer fichier téléchargeable
    filename = f"stripe_data_export_{customer_id}_{int(time.time())}.json"
    
    # Log GDPR
    log_gdpr_request(customer_id, "DataPortability", "Completed")
    
    return jsonify(data), 200, {
        'Content-Disposition': f'attachment; filename={filename}'
    }
```

---

## Transferts Internationaux de Données (Chapitre V)

### Situation Actuelle (Post-Schrems II)

**Stripe Data Architecture :**
- **Primary Region :** West Europe (Paris) - EU
- **Secondary Region :** East US - **PROBLÈME GDPR**

**Solutions de conformité :**

#### Option 1 : Standard Contractual Clauses (SCC) - Recommandé

```
Implementation:
  1. Signer les SCC 2021 avec l'entité US
  2. Évaluation d'impact (Transfer Impact Assessment)
  3. Mesures supplémentaires :
     • Encryption with EU-controlled keys
     • Pseudonymization before transfer
     • Access controls (US entity read-only)
  4. Documentation accessible aux autorités
```

#### Option 2 : Binding Corporate Rules (BCR)

```
Implementation (Long terme):
  • Stripe déjà certifié BCR
  • Applicable automatiquement aux transferts intra-groupe
  • Audit annuel par CNIL
```

#### Option 3 : Garder données 100% EU (Idéal)

```
Architecture modifiée:
  Primary: West Europe (Paris)
  Secondary: North Europe (Ireland) EU
  
Terraform change:
  cosmos_db_failover_locations = ["northeurope"]  # Au lieu de "eastus"
```

**Recommandation : Option 3** (modifier Terraform prod.tfvars)

---

## Data Protection Impact Assessment (DPIA) - Article 35

**Quand obligatoire :**
- Traitement à grande échelle de données sensibles 
- Scoring/profilage automatisé (fraude) 
- Surveillance systématique 

### DPIA - Payment Processing

**1. Description du traitement**
```yaml
Purpose: Process online payments for merchants
Data Processed:
  - Personal: Name, email, phone
  - Financial: Payment card data (PAN, CVV)
  - Technical: IP address, device fingerprint
Volume: 100M transactions/month
Automated Decisions: Fraud detection (decline payments)
```

**2. Necessity and Proportionality**
```
Necessary: Cannot process payments without payment data
Proportional: Minimum data collected
Alternatives considered: Tokenization (implemented)
```

**3. Risks to Rights and Freedoms**

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| **Data breach** | High (financial loss) | Low | Encryption, monitoring |
| **Unauthorized access** | High (identity theft) | Low | RBAC, MFA |
| **Discriminatory profiling** | Medium (unfair denial) | Medium | Human review for high scores |
| **Data retention abuse** | Low | Very Low | Automated deletion (TTL) |

**4. Measures to Address Risks**
```
Technical:
  • Encryption at rest and in transit
  • Tokenization of PAN (Stripe Vault)
  • Automated data deletion
  • Anomaly detection (Azure Sentinel)

Organizational:
  • DPO appointed (dpo@stripe.com)
  • Staff training (annual GDPR course)
  • Privacy by design principles
  • Regular audits (quarterly)
```

**5. Stakeholder Consultation**
```
DPO consulted: 2025-01-15
CNIL notified: Not required (mitigations sufficient)
Customer representatives: Privacy advisory board
```

**Conclusion : Risques acceptables avec mitigations**

---

## Data Breach Response (Articles 33-34)

### Notification Obligations

**Timeline :**
```
Discovery → 72 hours → Notify CNIL (Supervisory Authority)
          → Immediately → Notify affected individuals (if high risk)
```

### Breach Response Procedure

**Phase 1 : Detection (< 1 hour)**
```
1. Azure Sentinel alert triggered
2. Security team convened
3. Assess severity:
   • Low: < 100 records, non-sensitive
   • Medium: 100-10K records, or PII
   • High: > 10K records, or payment data
```

**Phase 2 : Containment (< 24 hours)**
```
1. Isolate affected systems
2. Revoke compromised credentials
3. Preserve forensic evidence
4. Stop data exfiltration
```

**Phase 3 : Notification (< 72 hours)**

```python
# Automated breach notification
def notify_gdpr_breach(breach_details):
    # Notification CNIL (obligatoire)
    if breach_details['severity'] in ['Medium', 'High']:
        send_to_cnil({
            'controller': 'Stripe, Inc.',
            'dpo_contact': 'dpo@stripe.com',
            'nature_of_breach': breach_details['type'],
            'categories_of_data': breach_details['data_types'],
            'approximate_number': breach_details['records_affected'],
            'likely_consequences': breach_details['impact'],
            'measures_taken': breach_details['mitigations'],
            'notification_time': datetime.utcnow()
        })
    
    # Notification individus (si risque élevé)
    if breach_details['severity'] == 'High':
        for customer in breach_details['affected_customers']:
            send_email(
                to=customer['email'],
                subject='Important Security Notice - Stripe',
                body=f"""
                Dear {customer['name']},
                
                We are writing to inform you of a data security incident
                that may have affected your personal information.
                
                What happened: {breach_details['description']}
                What data was affected: {breach_details['data_types']}
                What we're doing: {breach_details['mitigations']}
                What you should do: {breach_details['recommendations']}
                
                For more information: security.stripe.com/incident-{breach_details['id']}
                
                Sincerely,
                Stripe Security Team
                """
            )
```

**Sanctions potentielles :**
- Non-notification : jusqu'à 10M€ ou 2% CA annuel mondial
- Violation grave : jusqu'à 20M€ ou 4% CA annuel mondial

---

## Audit et Conformité Continue

### Checklist Trimestrielle

**Q1 2025 - Completed**
- [x] Review RBAC permissions
- [x] Test data deletion procedures
- [x] Update privacy policy (cookie law changes)
- [x] DPO training on AI Act implications

**Q2 2025 - In Progress**
- [x] DPIA refresh (new ML models)
- [x] Vendor audit (AWS → Azure migration)
- [ ] Penetration testing (scheduled May 15)
- [ ] Employee GDPR awareness training

**Q3 2025 - Planned**
- [ ] Review data retention policies
- [ ] Update SCCs (if US transfers continue)
- [ ] Mock data breach exercise
- [ ] CNIL compliance check

**Q4 2025 - Planned**
- [ ] Annual external audit (SOC 2)
- [ ] Review international transfers
- [ ] Update DPIA for 2026
- [ ] Executive GDPR report

### KPIs de Conformité

| Métrique | Target | Q1 2025 | Status |
|----------|--------|---------|--------|
| **Data Subject Requests** | < 30 days response | 14 days avg | 
| **Breach Notifications** | 0 | 0 | 
| **GDPR Training Completion** | 100% staff | 98% | 
| **Privacy Policy Updates** | Communicated 30 days before | 45 days | 
| **Vendor Compliance** | 100% GDPR-compliant | 95% | 

---

## Coût de la Non-Conformité

**Amendes CNIL (France) :**
```
Exemples récents (2024):
  • Google: 90M€ (cookies non conformes)
  • Amazon: 746M€ (publicité ciblée sans consentement)
  • Meta: 1.2Md€ (transferts US illégaux)

Stripe exposure (hypothétique):
  • CA annuel: ~15Md$ (2024)
  • Amende max: 4% = 600M€
  • Coût réputationnel: Inestimable
```

**ROI de la Conformité :**
```
Investment:
  • DPO (1 FTE): 120K€/an
  • Tooling (Azure Policy, Sentinel): 50K€/an
  • Legal counsel: 80K€/an
  • Training: 30K€/an
  Total: 280K€/an

Avoided Costs:
  • Average GDPR fine (payment sector): 15M€
  • Customer churn (data breach): 20% = 50M€ revenue
  • Legal fees (litigation): 5M€
  Expected value: (15M + 50M + 5M) × P(incident) × (1 - P(compliance))
                = 70M × 0.05 × 0.5 = 1.75M€

ROI: (1.75M - 0.28M) / 0.28M = 525% 
```

---

## Ressources Complémentaires

### Textes Officiels
- [GDPR Full Text (EUR-Lex)](https://eur-lex.europa.eu/eli/reg/2016/679/oj)
- [CNIL Guidelines](https://www.cnil.fr/en/gdpr-developers-guide)
- [EDPB Guidelines](https://edpb.europa.eu/our-work-tools/general-guidance/gdpr-guidelines-recommendations-best-practices_en)

### Outils
- [GDPR Compliance Checker](https://gdpr.eu/checklist/)
- [Data Mapping Tool](https://www.privacytools.io/)
- [Consent Management Platform](https://www.cookiebot.com/)

### Formation
- [CNIL MOOC RGPD](https://atelier-rgpd.cnil.fr/)
- [IAPP Certification](https://iapp.org/certify/cippe/)

---

## Conclusion

**Status actuel : 95% compliant**

**Points d'amélioration :**
1. Éliminer transferts US (changer secondary region)
2. Former 100% du personnel (98% actuellement)
3. Auditer 100% des vendors (95% actuellement)

**Next Review : 2026-01-15** (annuel)

---

*Document maintenu par : Legal & Compliance Team*  
*Dernière mise à jour : 2025-10-20*  
*Version : 2.1*