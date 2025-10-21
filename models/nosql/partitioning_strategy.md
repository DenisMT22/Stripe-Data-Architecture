# Stratégie de Partitionnement - Azure Cosmos DB

## Principes Fondamentaux

### Règles d'Or du Partitionnement Cosmos DB

1. **Haute cardinalité** : Minimum 1000+ valeurs uniques
2. **Distribution uniforme** : Éviter les "hot partitions" (> 20% du trafic)
3. **Requêtes efficaces** : 80% des requêtes incluent la partition key
4. **Immuabilité** : La partition key ne peut pas être modifiée après création

**Sources :**
- [Cosmos DB Partitioning Best Practices](https://learn.microsoft.com/en-us/azure/cosmos-db/partitioning-overview)
- [Choosing a Partition Key](https://learn.microsoft.com/en-us/azure/cosmos-db/partition-data)

---

## Analyse par Collection

### 1. Collection `api_logs`

#### Partition Key : `/merchant_id`

**Justification :**
- **Cardinalité élevée** : ~500,000 marchands actifs (source : Stripe Atlas)
- **Pattern d'accès** : 95% des requêtes filtrent par marchand
- **Distribution** : Loi de Pareto (20% marchands = 80% volume) mais acceptable

**Métriques de Performance :**
```
Requêtes typiques :
- "Logs des 24h pour merchant X" → 1 partition (optimal)
- "Top 10 erreurs 500 tous marchands" → Fan-out (acceptable, requête rare)

Taille partition (P99) : ~3.6GB
- Top merchant : 20,000 requêtes/jour × 2KB × 90 jours = 3.6GB
- Limite Cosmos DB : 50GB/partition → Marge de 13x 
```

**Alternative évaluée et rejetée :**
- `/timestamp` : Créerait des hot partitions (toutes les écritures récentes sur même partition)
- `/endpoint` : Faible cardinalité (~50 endpoints), déséquilibre majeur

---

### 2. Collection `user_sessions`

#### Partition Key : `/user_id`

**Justification :**
- **Cardinalité très élevée** : ~2,000,000 utilisateurs actifs
- **Isolation parfaite** : Zéro requête cross-user (RGPD compliance)
- **Distribution** : Très uniforme (B2B SaaS pattern)

**Métriques de Performance :**
```
Requêtes typiques :
- "Sessions actives user X" → 1 partition (optimal)
- "Durée moyenne sessions globale" → Nécessite agrégation OLAP (pas Cosmos DB)

Taille partition (P99) : ~750KB
- User actif : 50 sessions/mois × 5KB × 30 jours TTL = 750KB
- Limite Cosmos DB : 50GB/partition → Marge de 66,000x 
```

**Optimisation supplémentaire :**
- **Composite key envisagé** : `/user_id` + `/session_start` → Rejeté (over-engineering)
- Raison : TTL de 30 jours garde les partitions petites naturellement

---

### 3. Collection `fraud_features`

#### Partition Key : `/payment_id`

**Justification :**
- **Cardinalité extrême** : ~600,000,000 paiements sur 180 jours
- **Accès transactionnel** : 100% des requêtes par payment_id (scoring temps réel)
- **Write-heavy** : 1 write par paiement, très peu de reads après calcul

**Métriques de Performance :**
```
Requêtes typiques :
- "Features pour payment X" → 1 partition, < 5ms (critique)
- "Réentraînement modèle ML" → Export bulk vers Azure ML (pas via Cosmos DB)

Taille partition : 3KB fixe
- 1 document par payment_id (relation 1:1)
- Limite Cosmos DB : 50GB/partition → N/A (1 doc/partition) 
```

**Trade-off assumé :**
- **Contre** : Impossible de requêter "tous les paiements frauduleux" efficacement
- **Pour** : Latence ultra-faible (< 10ms) sur cas d'usage critique (scoring)
- **Solution** : Requêtes analytiques via Change Feed → Synapse Analytics

---

### 4. Collection `webhook_events`

#### Partition Key : `/merchant_id`

**Justification :**
- **Cardinalité élevée** : ~500,000 marchands
- **Isolation retry logic** : Chaque marchand a sa propre file d'attente
- **Pattern FIFO** : Webhooks processés par marchand (évite race conditions)

**Métriques de Performance :**
```
Requêtes typiques :
- "Webhooks failed pour merchant X" → 1 partition (optimal)
- "Retry webhook Y" → Update sur 1 partition (optimal)
- "Stats globales webhooks" → Agrégation OLAP (pas Cosmos DB)

Taille partition (P99) : ~1.2GB
- Top merchant : 10,000 événements/jour × 4KB × 60 jours = 2.4GB
- Limite Cosmos DB : 50GB/partition → Marge de 20x 
```

**🔧 Stratégie de retry :**
```javascript
// Exponential backoff calculé via partition key
function calculateNextRetry(merchant_id, retry_count) {
  // Tous les retries d'un marchand restent dans même partition
  const baseDelay = 60; // 1 minute
  return baseDelay * Math.pow(2, retry_count); // 1min, 2min, 4min, 8min...
}
```

---

## Anti-Patterns à Éviter

### Anti-Pattern #1 : Partition Key de faible cardinalité
```json
// MAUVAIS : Seulement ~200 pays
"partitionKey": "/country"

// Résultat : Hot partition sur US (~40% du trafic Stripe)
```

### Anti-Pattern #2 : Partition Key temporelle
```json
// MAUVAIS : Toutes les écritures récentes sur même partition
"partitionKey": "/date"

// Résultat : Throttling (429 errors) sur partition du jour courant
```

### Anti-Pattern #3 : Partition Key mutable
```json
// MAUVAIS : Le statut change souvent
"partitionKey": "/status"

// Résultat : Impossible de modifier (recréation document nécessaire)
```

---

## Simulation de Charge

### Test de Stress : Black Friday Scenario

**Hypothèses :**
- Volume normal : 100M transactions/jour
- Peak Black Friday : 500M transactions/jour (5x)
- Durée peak : 6 heures

**Impact par collection :**

#### `api_logs` (criticalité : moyenne)
```
Normal : 10M API calls/jour = 115 RPS
Peak   : 50M API calls/6h   = 2,300 RPS

RU consumption : 2,300 RPS × 10 RU/write = 23,000 RU/s
Provisioned    : 50,000 RU/s (autoscale)
Headroom       : 117% 
```

#### `fraud_features` (criticalité : HAUTE)
```
Normal : 100M paiements/jour = 1,157 RPS
Peak   : 500M paiements/6h   = 23,148 RPS

RU consumption : 23,148 RPS × 15 RU/write = 347,220 RU/s
Provisioned    : 30,000 RU/s (autoscale)
INSUFFISANT → Augmenter à 400,000 RU/s pour Black Friday
```

**Estimation coût Black Friday :**
```
400,000 RU/s × 6 heures × $0.008/RU-hour = $19,200
vs Perte d'un paiement frauduleux = $50,000 moyenne

ROI : Positif 
```

---

## Stratégies de Repartitionnement

### Scénario : Croissance déséquilibrée d'un marchand

**Problème :**
```
Marchand "MegaCorp" dépasse 40GB sur partition
→ Approche limite de 50GB
→ Risque de throttling
```

**Solution 1 : Hierarchical Partition Key (Cosmos DB v3+)**
```json
{
  "partitionKey": ["/merchant_id", "/date"],
  "data": {
    "merchant_id": "acct_megacorp",
    "date": "2025-10-19"
  }
}
```
- ✅ Distribue charge sur plusieurs partitions physiques
- ❌ Complexifie requêtes (doivent inclure date)

**Solution 2 : Sharding applicatif**
```javascript
// Hash merchant_id vers N shards
function getShardedPartitionKey(merchant_id) {
  const hash = murmurhash(merchant_id);
  const shard = hash % 10; // 10 shards
  return `${merchant_id}_shard${shard}`;
}
```
- ✅ Transparent pour Cosmos DB
- ❌ Logique custom dans application

**Recommandation Stripe :**
- < 1TB total : Aucune action nécessaire
- 1-10TB : Monitorer top 10 marchands, préparer Solution 1
- \> 10TB : Implémenter Solution 2 + Consider Azure Synapse for analytics

---

## Checklist de Validation

### Avant Déploiement Production

- [ ] **Cardinalité** : Partition key a > 10,000 valeurs uniques
- [ ] **Distribution** : Aucune partition > 10% du trafic total
- [ ] **Requêtes** : 80%+ incluent partition key dans WHERE clause
- [ ] **Sizing** : P99 partition < 20GB (marge de 2.5x vs limite)
- [ ] **Monitoring** : Alertes configurées sur PartitionKeyRangeStatistics
- [ ] **Load testing** : Testé à 3x la charge anticipée
- [ ] **TTL configuré** : Évite croissance infinie des partitions
- [ ] **Backup strategy** : Continuous backup activé
- [ ] **Failover** : Multi-région testée en conditions réelles
- [ ] **Cost analysis** : Budget RU/s validé avec FinOps

---

## Références

- [Azure Cosmos DB Capacity Calculator](https://cosmos.azure.com/capacitycalculator/)
- [Partition Key Design Patterns](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/modeling-data)
- [Stripe Engineering: Scaling to Billions](https://stripe.com/blog/scaling-api)
- [Avoiding Hot Partitions](https://learn.microsoft.com/en-us/azure/cosmos-db/sql/troubleshoot-request-rate-too-large)