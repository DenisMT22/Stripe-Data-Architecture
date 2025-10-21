/**
 * Azure Cosmos DB - SQL API Query Examples
 * Collection: Stripe NoSQL Database
 * 
 * Prerequisites:
 * npm install @azure/cosmos
 * 
 * Connection:
 * const { CosmosClient } = require("@azure/cosmos");
 * const client = new CosmosClient({
 *   endpoint: process.env.COSMOS_ENDPOINT,
 *   key: process.env.COSMOS_KEY
 * });
 * const database = client.database("stripe_nosql_db");
 */

// ============================================================================
// COLLECTION 1: api_logs
// ============================================================================

/**
 * Q1: Récupérer tous les logs API d'un marchand sur les dernières 24h
 * Use Case: Dashboard de monitoring marchand
 * Performance: Single partition query (optimal)
 */
const query1_api_logs_24h = {
  query: `
    SELECT 
      c.log_id,
      c.timestamp,
      c.endpoint,
      c.method,
      c.status_code,
      c.latency_ms,
      c.error_message
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.timestamp >= @since
    ORDER BY c.timestamp DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 24*60*60*1000).toISOString() }
  ]
};

/**
 * Q2: Analyser les erreurs 500 par endpoint pour un marchand
 * Use Case: Debugging incidents de production
 * Performance: Single partition query avec agrégation
 */
const query2_api_errors_by_endpoint = {
  query: `
    SELECT 
      c.endpoint,
      COUNT(1) as error_count,
      AVG(c.latency_ms) as avg_latency,
      MAX(c.latency_ms) as max_latency
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.status_code >= 500
      AND c.timestamp >= @since
    GROUP BY c.endpoint
    ORDER BY error_count DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 7*24*60*60*1000).toISOString() }
  ]
};

/**
 * Q3: Trouver les requêtes API les plus lentes (P99 latency)
 * Use Case: Optimisation performance API
 * Performance: Single partition query avec TOP
 */
const query3_slowest_api_calls = {
  query: `
    SELECT TOP 100
      c.log_id,
      c.timestamp,
      c.endpoint,
      c.latency_ms,
      c.method
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.timestamp >= @since
    ORDER BY c.latency_ms DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 24*60*60*1000).toISOString() }
  ]
};

/**
 * Q4: Calculer le taux de succès API par heure
 * Use Case: SLA monitoring et alerting
 * Performance: Single partition avec agrégation temporelle
 */
const query4_api_success_rate_hourly = {
  query: `
    SELECT 
      DateTimePart("hour", c.timestamp) as hour,
      COUNT(1) as total_requests,
      SUM(c.status_code >= 200 AND c.status_code < 300 ? 1 : 0) as success_count,
      (SUM(c.status_code >= 200 AND c.status_code < 300 ? 1 : 0) * 100.0 / COUNT(1)) as success_rate
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.timestamp >= @since
    GROUP BY DateTimePart("hour", c.timestamp)
    ORDER BY hour DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 24*60*60*1000).toISOString() }
  ]
};

// ============================================================================
// COLLECTION 2: user_sessions
// ============================================================================

/**
 * Q5: Récupérer les sessions actives d'un utilisateur
 * Use Case: Dashboard utilisateur, détection de sessions multiples
 * Performance: Single partition query (optimal)
 */
const query5_active_sessions = {
  query: `
    SELECT 
      c.session_id,
      c.session_start,
      c.last_activity,
      c.device_type,
      c.browser,
      c.country
    FROM c
    WHERE c.user_id = @userId
      AND NOT IS_DEFINED(c.session_end)
    ORDER BY c.last_activity DESC
  `,
  parameters: [
    { name: "@userId", value: "usr_acct_1MxY2kLkdIwHu0C9" }
  ]
};

/**
 * Q6: Analyser le comportement utilisateur (pages les plus consultées)
 * Use Case: Product analytics, A/B testing
 * Performance: Single partition avec ARRAY operations
 */
const query6_user_page_views = {
  query: `
    SELECT 
      c.session_id,
      c.session_start,
      c.duration_seconds,
      page_view.page,
      page_view.count,
      page_view.total_time_seconds
    FROM c
    JOIN page_view IN c.page_views
    WHERE c.user_id = @userId
      AND c.session_start >= @since
    ORDER BY c.session_start DESC
  `,
  parameters: [
    { name: "@userId", value: "usr_acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 30*24*60*60*1000).toISOString() }
  ]
};

/**
 * Q7: Détecter les sessions suspectes (durée anormale, trop d'actions)
 * Use Case: Détection de bots, anomaly detection
 * Performance: Single partition avec filtres complexes
 */
const query7_suspicious_sessions = {
  query: `
    SELECT 
      c.session_id,
      c.session_start,
      c.duration_seconds,
      c.actions_count,
      c.device_type,
      c.ip_address
    FROM c
    WHERE c.user_id = @userId
      AND (
        c.duration_seconds < 10 AND c.actions_count > 50  -- Bot pattern
        OR c.duration_seconds > 28800  -- Session > 8h
      )
      AND c.session_start >= @since
    ORDER BY c.session_start DESC
  `,
  parameters: [
    { name: "@userId", value: "usr_acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 7*24*60*60*1000).toISOString() }
  ]
};

/**
 * Q8: Calculer l'engagement utilisateur moyen par appareil
 * Use Case: Mobile vs Desktop analytics
 * Performance: Single partition avec GROUP BY
 */
const query8_engagement_by_device = {
  query: `
    SELECT 
      c.device_type,
      COUNT(1) as session_count,
      AVG(c.duration_seconds) as avg_duration,
      AVG(c.actions_count) as avg_actions,
      SUM(c.duration_seconds) as total_time
    FROM c
    WHERE c.user_id = @userId
      AND c.session_start >= @since
      AND IS_DEFINED(c.session_end)
    GROUP BY c.device_type
    ORDER BY session_count DESC
  `,
  parameters: [
    { name: "@userId", value: "usr_acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 90*24*60*60*1000).toISOString() }
  ]
};

// ============================================================================
// COLLECTION 3: fraud_features
// ============================================================================

/**
 * Q9: Récupérer les features ML d'un paiement spécifique (temps réel)
 * Use Case: Scoring de fraude lors du paiement
 * Performance: Point read (< 10ms) - OPTIMAL
 */
const query9_fraud_features_by_payment = {
  query: `
    SELECT *
    FROM c
    WHERE c.payment_id = @paymentId
  `,
  parameters: [
    { name: "@paymentId", value: "pi_3O9P8qLkdIwHu0C91rXyZmQY" }
  ]
};

/**
 * Q10: Identifier les paiements à haut risque pour un marchand
 * Use Case: Revue manuelle des transactions suspectes
 * Performance: Cross-partition query (acceptable pour batch)
 */
const query10_high_risk_payments = {
  query: `
    SELECT 
      c.payment_id,
      c.customer_id,
      c.fraud_score,
      c.risk_level,
      c.computed_at,
      c.features.transaction_velocity_1h,
      c.features.card_country_mismatch,
      c.features.ip_country_mismatch
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.fraud_score >= 0.7
      AND c.computed_at >= @since
    ORDER BY c.fraud_score DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 24*60*60*1000).toISOString() }
  ]
};

/**
 * Q11: Analyser les patterns de fraude par feature
 * Use Case: Feature importance analysis pour ML
 * Performance: Cross-partition avec agrégation
 */
const query11_fraud_patterns_analysis = {
  query: `
    SELECT 
      c.risk_level,
      COUNT(1) as count,
      AVG(c.fraud_score) as avg_score,
      AVG(c.features.transaction_velocity_1h) as avg_velocity_1h,
      AVG(c.features.transaction_velocity_24h) as avg_velocity_24h,
      SUM(c.features.card_country_mismatch ? 1 : 0) as card_mismatch_count,
      SUM(c.features.ip_country_mismatch ? 1 : 0) as ip_mismatch_count
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.computed_at >= @since
    GROUP BY c.risk_level
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 7*24*60*60*1000).toISOString() }
  ]
};

/**
 * Q12: Trouver les customers avec historique de disputes
 * Use Case: Blocklist automatique, enhanced verification
 * Performance: Cross-partition avec filtre
 */
const query12_customers_with_disputes = {
  query: `
    SELECT DISTINCT
      c.customer_id,
      c.features.customer_dispute_history,
      COUNT(1) as payment_count,
      AVG(c.fraud_score) as avg_fraud_score
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.features.customer_dispute_history > 0
      AND c.computed_at >= @since
    GROUP BY c.customer_id, c.features.customer_dispute_history
    ORDER BY c.features.customer_dispute_history DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 90*24*60*60*1000).toISOString() }
  ]
};

// ============================================================================
// COLLECTION 4: webhook_events
// ============================================================================

/**
 * Q13: Récupérer les webhooks en échec pour retry
 * Use Case: Background job de retry automatique
 * Performance: Single partition avec composite index
 */
const query13_failed_webhooks_for_retry = {
  query: `
    SELECT 
      c.webhook_id,
      c.event_type,
      c.event_id,
      c.webhook_url,
      c.retry_count,
      c.next_retry_at,
      c.error_message
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.status = 'failed'
      AND c.retry_count < 5
      AND c.next_retry_at <= @now
    ORDER BY c.next_retry_at ASC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@now", value: new Date().toISOString() }
  ]
};

/**
 * Q14: Statistiques de delivery des webhooks par type d'événement
 * Use Case: Monitoring santé des webhooks, alerting
 * Performance: Single partition avec GROUP BY
 */
const query14_webhook_stats_by_event_type = {
  query: `
    SELECT 
      c.event_type,
      COUNT(1) as total_events,
      SUM(c.status = 'sent' ? 1 : 0) as sent_count,
      SUM(c.status = 'failed' ? 1 : 0) as failed_count,
      (SUM(c.status = 'sent' ? 1 : 0) * 100.0 / COUNT(1)) as success_rate,
      AVG(c.response_time_ms) as avg_response_time,
      AVG(c.retry_count) as avg_retry_count
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.created_at >= @since
    GROUP BY c.event_type
    ORDER BY total_events DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 7*24*60*60*1000).toISOString() }
  ]
};

/**
 * Q15: Identifier les webhooks avec latence élevée
 * Use Case: Optimisation endpoints marchands
 * Performance: Single partition avec ORDER BY latence
 */
const query15_slow_webhook_endpoints = {
  query: `
    SELECT TOP 50
      c.webhook_id,
      c.event_type,
      c.webhook_url,
      c.response_time_ms,
      c.created_at
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.status = 'sent'
      AND c.response_time_ms > 5000  -- > 5 secondes
      AND c.created_at >= @since
    ORDER BY c.response_time_ms DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 24*60*60*1000).toISOString() }
  ]
};

/**
 * Q16: Calculer le temps moyen entre création et delivery
 * Use Case: SLA monitoring webhooks
 * Performance: Single partition avec calcul de différence temporelle
 */
const query16_webhook_delivery_time = {
  query: `
    SELECT 
      c.webhook_id,
      c.event_type,
      c.created_at,
      c.delivered_at,
      DateTimeDiff('second', c.created_at, c.delivered_at) as delivery_time_seconds,
      c.retry_count
    FROM c
    WHERE c.merchant_id = @merchantId
      AND c.status = 'sent'
      AND IS_DEFINED(c.delivered_at)
      AND c.created_at >= @since
    ORDER BY delivery_time_seconds DESC
  `,
  parameters: [
    { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
    { name: "@since", value: new Date(Date.now() - 24*60*60*1000).toISOString() }
  ]
};

// ============================================================================
// REQUÊTES CROSS-COLLECTION (via Change Feed + enrichissement)
// ============================================================================

/**
 * Q17: Corrélation entre logs API et features de fraude
 * Use Case: Audit trail complet d'une transaction
 * Note: Nécessite enrichissement applicatif (pas query directe)
 */
const query17_transaction_audit_trail = {
  // Étape 1: Récupérer features de fraude
  step1: {
    query: `SELECT * FROM c WHERE c.payment_id = @paymentId`,
    parameters: [{ name: "@paymentId", value: "pi_3O9P8qLkdIwHu0C91rXyZmQY" }]
  },
  // Étape 2: Avec merchant_id récupéré, chercher logs API
  step2: {
    query: `
      SELECT * FROM c 
      WHERE c.merchant_id = @merchantId
        AND c.timestamp BETWEEN @startTime AND @endTime
        AND CONTAINS(c.request_body, @paymentId)
    `,
    parameters: [
      { name: "@merchantId", value: "acct_1MxY2kLkdIwHu0C9" },
      { name: "@startTime", value: "2025-10-19T14:23:00Z" },
      { name: "@endTime", value: "2025-10-19T14:24:00Z" },
      { name: "@paymentId", value: "pi_3O9P8qLkdIwHu0C91rXyZmQY" }
    ]
  }
};

// ============================================================================
// EXEMPLE D'EXÉCUTION (Node.js)
// ============================================================================

async function executeQuery(container, querySpec) {
  const { resources: items } = await container.items
    .query(querySpec)
    .fetchAll();
  
  return items;
}

// Exemple d'utilisation
async function example() {
  const { CosmosClient } = require("@azure/cosmos");
  
  const client = new CosmosClient({
    endpoint: process.env.COSMOS_ENDPOINT,
    key: process.env.COSMOS_KEY
  });
  
  const database = client.database("stripe_nosql_db");
  const container = database.container("api_logs");
  
  // Exécuter Q1
  const logs = await executeQuery(container, query1_api_logs_24h);
  console.log(`Found ${logs.length} API logs in last 24h`);
  
  // Exécuter avec pagination (recommandé pour gros volumes)
  const iterator = container.items.query(query1_api_logs_24h, {
    maxItemCount: 100  // 100 items par page
  });
  
  while (iterator.hasMoreResults()) {
    const { resources: page } = await iterator.fetchNext();
    console.log(`Processing page with ${page.length} items`);
    // Traiter page...
  }
}

// Export pour utilisation dans d'autres modules
module.exports = {
  // API Logs
  query1_api_logs_24h,
  query2_api_errors_by_endpoint,
  query3_slowest_api_calls,
  query4_api_success_rate_hourly,
  
  // User Sessions
  query5_active_sessions,
  query6_user_page_views,
  query7_suspicious_sessions,
  query8_engagement_by_device,
  
  // Fraud Features
  query9_fraud_features_by_payment,
  query10_high_risk_payments,
  query11_fraud_patterns_analysis,
  query12_customers_with_disputes,
  
  // Webhook Events
  query13_failed_webhooks_for_retry,
  query14_webhook_stats_by_event_type,
  query15_slow_webhook_endpoints,
  query16_webhook_delivery_time,
  
  // Cross-collection
  query17_transaction_audit_trail,
  
  // Helper function
  executeQuery
};