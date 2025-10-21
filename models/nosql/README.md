# Modèle NoSQL - Azure Cosmos DB

## Vue d'ensemble

Ce modèle NoSQL complète l'architecture OLTP/OLAP en gérant les données non structurées et semi-structurées avec Azure Cosmos DB (API Core SQL).

### Pourquoi Cosmos DB pour Stripe ?

**Avantages clés :**
- **Latence ultra-faible** : < 10ms en P99 (crucial pour API payments)
- **Scalabilité élastique** : Adapté aux pics de transactions Black Friday
- **Distribution globale** : Multi-région pour conformité réglementaire
- **Schéma flexible** : Idéal pour métadonnées clients évolutives

**Sources :**
- [Azure Cosmos DB Documentation](https://learn.microsoft.com/en-us/azure/cosmos-db/)
- [Stripe Engineering Blog - Data Architecture](https://stripe.com/blog/engineering)

---

## Collections Principales

### 1. **api_logs** - Logs d'API
**Usage :** Traçabilité complète des appels API (audit, debugging, analytics)

**Partition Key :** `/merchant_id`
- **Justification :** 80% des requêtes filtrent par marchand (pattern d'accès typique)
- **Cardinalité :** ~500K marchands actifs (source : Stripe Atlas statistics)

**TTL :** 90 jours (rétention légale minimale)

**Indexation :**
```json
{
  "indexingMode": "consistent",
  "automatic": true,
  "includedPaths": [
    {"path": "/merchant_id/?"},
    {"path": "/timestamp/?"},
    {"path": "/status_code/?"},
    {"path": "/endpoint/?"}
  ],
  "excludedPaths": [
    {"path": "/request_body/*"},
    {"path": "/response_body/*"}
  ]
}
```

**Volume estimé :** 
- 10M requêtes API/jour (référence : Stripe gère 1 milliard API calls/semaine)
- ~900M documents avec TTL de 90 jours
- Taille moyenne : 2KB par document
- **Stockage total :** ~1.8TB

---

### 2. **user_sessions** - Sessions Utilisateurs
**Usage :** Tracking des sessions dashboard Stripe (analytics temps réel)

**Partition Key :** `/user_id`
- **Justification :** Requêtes isolées par utilisateur (pas de cross-user queries)
- **Cardinalité :** ~2M utilisateurs actifs/mois

**TTL :** 30 jours (données éphémères)

**Indexation :**
```json
{
  "indexingMode": "consistent",
  "automatic": true,
  "includedPaths": [
    {"path": "/user_id/?"},
    {"path": "/session_start/?"},
    {"path": "/last_activity/?"}
  ],
  "excludedPaths": [
    {"path": "/events/*"},
    {"path": "/page_views/*"}
  ]
}
```

**Volume estimé :**
- 50M sessions/mois
- Taille moyenne : 5KB par session
- **Stockage total :** ~250GB

---

### 3. **fraud_features** - Features Machine Learning
**Usage :** Stockage des features calculées pour modèles de détection de fraude

**Partition Key :** `/payment_id`
- **Justification :** Requêtes en temps réel lors du scoring de transaction
- **Cardinalité :** ~100M paiements/mois

**TTL :** 180 jours (historique pour réentraînement modèles)

**Indexation :**
```json
{
  "indexingMode": "consistent",
  "automatic": true,
  "includedPaths": [
    {"path": "/payment_id/?"},
    {"path": "/fraud_score/?"},
    {"path": "/computed_at/?"}
  ],
  "excludedPaths": [
    {"path": "/raw_features/*"}
  ]
}
```

**Volume estimé :**
- 100M paiements/mois × 6 mois = 600M documents
- Taille moyenne : 3KB par document
- **Stockage total :** ~1.8TB

---

### 4. **webhook_events** - Événements Webhooks
**Usage :** File d'attente pour webhooks sortants (retry logic, debugging)

**Partition Key :** `/merchant_id`
- **Justification :** Isolation des webhooks par marchand pour retry indépendant
- **Cardinalité :** ~500K marchands

**TTL :** 60 jours (conformité PCI-DSS)

**Indexation :**
```json
{
  "indexingMode": "consistent",
  "automatic": true,
  "includedPaths": [
    {"path": "/merchant_id/?"},
    {"path": "/event_type/?"},
    {"path": "/status/?"},
    {"path": "/created_at/?"}
  ],
  "excludedPaths": [
    {"path": "/payload/*"}
  ]
}
```

**Volume estimé :**
- 5M événements/jour (moyenne industrie FinTech)
- ~300M documents avec TTL de 60 jours
- Taille moyenne : 4KB par événement
- **Stockage total :** ~1.2TB

---

## Configuration Azure Cosmos DB

### Recommandations Production

**Throughput (RU/s) :**
- **api_logs :** 50,000 RU/s (autoscale 10K-50K)
- **user_sessions :** 10,000 RU/s (autoscale 2K-10K)
- **fraud_features :** 30,000 RU/s (autoscale 5K-30K)
- **webhook_events :** 20,000 RU/s (autoscale 4K-20K)

**Multi-région :**
```
Primary: West Europe (Paris proximity)
Secondary: East US (failover + read replica)
```

**Consistency Level :** Session (optimal pour applications web)

**Backup :** Continuous (7 jours de point-in-time restore)

---

## Intégration avec OLTP/OLAP

### Pipeline ETL NoSQL → OLAP

**Change Feed Cosmos DB :**
```
api_logs → Azure Stream Analytics → Synapse Analytics
         ↓
      (Agrégation temps réel)
         ↓
   Fact_API_Performance (OLAP)
```

**Fréquence :** Near real-time (latence < 5 minutes)

### Synchronisation OLTP ↔ NoSQL

**Exemple : Nouvelle transaction**
```
1. Insert dans Payment (OLTP)
2. Trigger Azure Function
3. Calcul features fraud_features (NoSQL)
4. Enrichissement webhook_events (NoSQL)
```

---

## Cas d'Usage Métier

### 1. Détection de Fraude Temps Réel
```
Incoming Payment → Lookup fraud_features (< 10ms)
                 → ML Model Scoring
                 → Approve/Decline
```

### 2. Analytics API Performance
```
api_logs (24h) → Agrégation par endpoint
               → Dashboard temps réel
               → Alerting si latence > threshold
```

### 3. Retry Logic Webhooks
```
webhook_events (status = 'failed')
  → Exponential backoff retry
  → Update status in Cosmos DB
  → Notification si échec définitif
```

---

## Sécurité et Conformité

### Encryption
- **At rest :** Azure-managed keys (automatique)
- **In transit :** TLS 1.2+ (forcé)

### Access Control
```
Merchant API → Managed Identity → Cosmos DB
             ↓
       Row-level filtering via partition key
```

### Audit
- **Diagnostic Logs :** Activés sur toutes collections
- **Rétention :** 90 jours dans Log Analytics

---

## Monitoring Clés

**Métriques critiques :**
- **Latence P99 :** < 10ms (SLA Stripe)
- **RU Consumption :** < 80% du provisionné
- **Storage Growth :** Vérifier TTL effectif
- **Throttling Rate :** < 1% des requêtes

**Alertes :**
- Latence > 50ms pendant 5 minutes
- RU consumption > 90% pendant 10 minutes
- Failed requests > 5% du total

---

## Références Techniques

- [Cosmos DB Partitioning Best Practices](https://learn.microsoft.com/en-us/azure/cosmos-db/partitioning-overview)
- [Stripe API Design Principles](https://stripe.com/docs/api)
- [Change Feed Pattern](https://learn.microsoft.com/en-us/azure/cosmos-db/change-feed)
- [Cost Optimization Guide](https://learn.microsoft.com/en-us/azure/cosmos-db/optimize-cost-throughput)