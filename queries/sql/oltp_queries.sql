-- STRIPE OLTP - EXAMPLE QUERIES

-- These queries demonstrate how to answer key business questions

-- 1. TRANSACTIONAL QUERIES (High-frequency, low-latency)

-- Query 1.1: Get transaction details by payment intent ID
-- Use case: API endpoint /v1/payment_intents/{id}
-- Expected latency: < 10ms

SELECT 
    t.transaction_id,
    t.payment_intent_id,
    t.amount,
    t.currency,
    t.status,
    t.created_at,
    c.email AS customer_email,
    m.business_name AS merchant_name,
    pm.card_brand,
    pm.last4,
    fc.risk_level
FROM transactions t
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
INNER JOIN payment_methods pm ON t.payment_method_id = pm.payment_method_id
LEFT JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE t.payment_intent_id = 'pi_1234567890abcdef'
    AND t.is_deleted = 0;

-- Query 1.2: Get customer's active payment methods
-- Use case: Display saved cards at checkout

SELECT 
    pm.payment_method_id,
    pm.type,
    pm.card_brand,
    pm.last4,
    pm.exp_month,
    pm.exp_year,
    pm.is_default
FROM payment_methods pm
WHERE pm.customer_id = 123
    AND pm.is_active = 1
    AND pm.is_deleted = 0
ORDER BY pm.is_default DESC, pm.created_at DESC;

-- Query 1.3: Check for duplicate transactions (fraud prevention)
-- Use case: Prevent double-charging

SELECT 
    t.transaction_id,
    t.payment_intent_id,
    t.amount,
    t.created_at
FROM transactions t
WHERE t.customer_id = 123
    AND t.merchant_id = 456
    AND t.amount = 99.99
    AND t.created_at >= DATEADD(MINUTE, -5, GETUTCDATE())
    AND t.status IN ('PENDING', 'SUCCEEDED')
    AND t.is_deleted = 0;

-- 2. MERCHANT DASHBOARD QUERIES

-- Query 2.1: Merchant daily revenue
-- Use case: Dashboard overview

SELECT 
    CAST(t.created_at AS DATE) AS transaction_date,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS successful_count,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE 0 END) AS gross_revenue,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.processing_fee ELSE 0 END) AS fees,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.net_amount ELSE 0 END) AS net_revenue,
    t.currency
FROM transactions t
WHERE t.merchant_id = 456
    AND t.created_at >= DATEADD(DAY, -30, GETUTCDATE())
    AND t.is_deleted = 0
GROUP BY CAST(t.created_at AS DATE), t.currency
ORDER BY transaction_date DESC;

-- Query 2.2: Top customers by transaction volume
-- Use case: VIP customer identification

SELECT TOP 10
    c.customer_id,
    c.email,
    c.first_name + ' ' + c.last_name AS customer_name,
    COUNT(t.transaction_id) AS transaction_count,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE 0 END) AS total_spent,
    MAX(t.created_at) AS last_transaction_date
FROM customers c
INNER JOIN transactions t ON c.customer_id = t.customer_id
WHERE t.merchant_id = 456
    AND t.created_at >= DATEADD(DAY, -90, GETUTCDATE())
    AND t.is_deleted = 0
    AND c.is_deleted = 0
GROUP BY c.customer_id, c.email, c.first_name, c.last_name
ORDER BY total_spent DESC;

-- Query 2.3: Failed transactions analysis
-- Use case: Identify payment issues

SELECT 
    t.failure_code,
    t.failure_message,
    COUNT(*) AS failure_count,
    SUM(t.amount) AS lost_revenue,
    AVG(t.amount) AS avg_failed_amount
FROM transactions t
WHERE t.merchant_id = 456
    AND t.status = 'FAILED'
    AND t.created_at >= DATEADD(DAY, -7, GETUTCDATE())
    AND t.is_deleted = 0
GROUP BY t.failure_code, t.failure_message
ORDER BY failure_count DESC;

-- 3. FRAUD DETECTION QUERIES

-- Query 3.1: High-risk transactions requiring review
-- Use case: Fraud analyst dashboard

SELECT 
    t.transaction_id,
    t.payment_intent_id,
    t.amount,
    t.currency,
    t.created_at,
    c.email AS customer_email,
    c.risk_score AS customer_risk_score,
    m.business_name AS merchant_name,
    fc.risk_score AS transaction_risk_score,
    fc.risk_level,
    fc.factors,
    t.ip_address,
    t.country_code,
    c.country_code AS customer_country
FROM transactions t
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
INNER JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE fc.risk_level IN ('HIGH', 'CRITICAL')
    AND fc.action_taken = 'REVIEW'
    AND fc.reviewed_at IS NULL
    AND t.created_at >= DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY fc.risk_score DESC, t.created_at DESC;

-- Query 3.2: Customers with multiple failed attempts
-- Use case: Detect card testing attacks

SELECT 
    c.customer_id,
    c.email,
    COUNT(*) AS failed_attempts,
    COUNT(DISTINCT t.payment_method_id) AS different_cards_used,
    MIN(t.created_at) AS first_attempt,
    MAX(t.created_at) AS last_attempt
FROM customers c
INNER JOIN transactions t ON c.customer_id = t.customer_id
WHERE t.status = 'FAILED'
    AND t.created_at >= DATEADD(HOUR, -1, GETUTCDATE())
    AND t.is_deleted = 0
GROUP BY c.customer_id, c.email
HAVING COUNT(*) >= 3
ORDER BY failed_attempts DESC;

-- Query 3.3: Cross-border transactions analysis
-- Use case: Geographic anomaly detection

SELECT 
    t.transaction_id,
    t.amount,
    t.created_at,
    c.email,
    c.country_code AS customer_country,
    t.country_code AS transaction_country,
    t.ip_address,
    fc.risk_score
FROM transactions t
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE c.country_code <> t.country_code
    AND t.amount > 500
    AND t.created_at >= DATEADD(DAY, -1, GETUTCDATE())
    AND t.is_deleted = 0
ORDER BY fc.risk_score DESC;

-- 4. SUBSCRIPTION MANAGEMENT QUERIES

-- Query 4.1: Subscriptions expiring soon
-- Use case: Renewal reminders

SELECT 
    s.subscription_id,
    s.plan_name,
    s.amount,
    s.currency,
    s.current_period_end,
    c.email AS customer_email,
    c.first_name,
    c.last_name,
    m.business_name AS merchant_name,
    pm.card_brand,
    pm.last4,
    pm.exp_month,
    pm.exp_year
FROM subscriptions s
INNER JOIN customers c ON s.customer_id = c.customer_id
INNER JOIN merchants m ON s.merchant_id = m.merchant_id
INNER JOIN payment_methods pm ON s.payment_method_id = pm.payment_method_id
WHERE s.status = 'ACTIVE'
    AND s.current_period_end BETWEEN GETUTCDATE() AND DATEADD(DAY, 7, GETUTCDATE())
    AND s.cancel_at_period_end = 0
    AND s.is_deleted = 0
ORDER BY s.current_period_end ASC;

-- Query 4.2: Failed subscription payments needing retry
-- Use case: Dunning management

SELECT 
    sp.subscription_payment_id,
    s.subscription_id,
    s.plan_name,
    sp.amount,
    sp.currency,
    sp.attempt_count,
    sp.next_retry_at,
    sp.failure_reason,
    c.email AS customer_email,
    m.business_name AS merchant_name
FROM subscription_payments sp
INNER JOIN subscriptions s ON sp.subscription_id = s.subscription_id
INNER JOIN customers c ON s.customer_id = c.customer_id
INNER JOIN merchants m ON s.merchant_id = m.merchant_id
WHERE sp.status = 'FAILED'
    AND sp.next_retry_at <= GETUTCDATE()
    AND sp.attempt_count < 4
    AND s.status = 'ACTIVE'
ORDER BY sp.next_retry_at ASC;

-- Query 4.3: Subscription churn analysis
-- Use case: Identify cancellation patterns

SELECT 
    DATEPART(YEAR, s.canceled_at) AS cancel_year,
    DATEPART(MONTH, s.canceled_at) AS cancel_month,
    COUNT(*) AS canceled_count,
    AVG(DATEDIFF(DAY, s.created_at, s.canceled_at)) AS avg_lifetime_days,
    SUM(s.amount) AS lost_mrr
FROM subscriptions s
WHERE s.status = 'CANCELED'
    AND s.canceled_at >= DATEADD(MONTH, -12, GETUTCDATE())
    AND s.is_deleted = 0
GROUP BY DATEPART(YEAR, s.canceled_at), DATEPART(MONTH, s.canceled_at)
ORDER BY cancel_year DESC, cancel_month DESC;

-- 5. COMPLIANCE AND AUDIT QUERIES

-- Query 5.1: PCI-DSS audit - Card data access log
-- Use case: Compliance reporting
-- Note: In production, this would query an audit log table

SELECT 
    pm.payment_method_id,
    pm.last4,
    pm.card_brand,
    c.email AS customer_email,
    pm.created_at AS card_stored_date,
    pm.updated_at AS last_modified_date,
    COUNT(t.transaction_id) AS times_used
FROM payment_methods pm
INNER JOIN customers c ON pm.customer_id = c.customer_id
LEFT JOIN transactions t ON pm.payment_method_id = t.payment_method_id
WHERE pm.created_at >= DATEADD(MONTH, -6, GETUTCDATE())
GROUP BY pm.payment_method_id, pm.last4, pm.card_brand, c.email, pm.created_at, pm.updated_at
ORDER BY pm.created_at DESC;

-- Query 5.2: GDPR - Customer data export
-- Use case: Data portability request

SELECT 
    'Customer Info' AS data_type,
    c.customer_id,
    c.email,
    c.first_name,
    c.last_name,
    c.phone,
    c.country_code,
    c.created_at
FROM customers c
WHERE c.email = 'customer@example.com'

UNION ALL

SELECT 
    'Payment Methods' AS data_type,
    pm.payment_method_id,
    pm.type,
    pm.card_brand,
    pm.last4,
    CAST(pm.exp_month AS NVARCHAR),
    CAST(pm.exp_year AS NVARCHAR),
    pm.created_at
FROM payment_methods pm
INNER JOIN customers c ON pm.customer_id = c.customer_id
WHERE c.email = 'customer@example.com'

UNION ALL

SELECT 
    'Transactions' AS data_type,
    t.transaction_id,
    t.amount,
    t.currency,
    t.status,
    m.business_name,
    NULL,
    t.created_at
FROM transactions t
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE c.email = 'customer@example.com'
ORDER BY created_at DESC;

-- Query 5.3: Large transaction monitoring (AML compliance)
-- Use case: Anti-Money Laundering detection

SELECT 
    t.transaction_id,
    t.payment_intent_id,
    t.amount,
    t.currency,
    t.created_at,
    c.email AS customer_email,
    c.country_code AS customer_country,
    m.business_name AS merchant_name,
    m.industry,
    t.description,
    fc.risk_score,
    fc.risk_level
FROM transactions t
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
INNER JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE t.amount >= 10000
    AND t.status = 'SUCCEEDED'
    AND t.created_at >= DATEADD(DAY, -30, GETUTCDATE())
    AND t.is_deleted = 0
ORDER BY t.amount DESC;

-- 6. REFUND AND CHARGEBACK QUERIES

-- Query 6.1: Pending refunds to process
-- Use case: Refund processing queue

SELECT 
    r.refund_id,
    r.amount,
    r.currency,
    r.reason,
    r.created_at,
    DATEDIFF(HOUR, r.created_at, GETUTCDATE()) AS hours_pending,
    t.transaction_id,
    t.payment_intent_id,
    c.email AS customer_email,
    m.business_name AS merchant_name
FROM refunds r
INNER JOIN transactions t ON r.transaction_id = t.transaction_id
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE r.status = 'PENDING'
    AND r.is_deleted = 0
ORDER BY r.created_at ASC;

-- Query 6.2: Chargeback rate by merchant
-- Use case: Identify high-risk merchants

SELECT 
    m.merchant_id,
    m.business_name,
    m.industry,
    COUNT(DISTINCT t.transaction_id) AS total_transactions,
    COUNT(DISTINCT cb.chargeback_id) AS chargeback_count,
    CAST(COUNT(DISTINCT cb.chargeback_id) AS FLOAT) / 
        NULLIF(COUNT(DISTINCT t.transaction_id), 0) * 100 AS chargeback_rate,
    SUM(cb.amount) AS total_disputed_amount
FROM merchants m
INNER JOIN transactions t ON m.merchant_id = t.merchant_id
LEFT JOIN chargebacks cb ON t.transaction_id = cb.transaction_id
WHERE t.created_at >= DATEADD(MONTH, -3, GETUTCDATE())
    AND t.is_deleted = 0
    AND m.is_deleted = 0
GROUP BY m.merchant_id, m.business_name, m.industry
HAVING COUNT(DISTINCT cb.chargeback_id) > 0
ORDER BY chargeback_rate DESC;

-- Query 6.3: Open chargebacks requiring evidence
-- Use case: Dispute management

SELECT 
    cb.chargeback_id,
    cb.amount,
    cb.currency,
    cb.reason_code,
    cb.reason_description,
    cb.evidence_due_date,
    DATEDIFF(DAY, GETUTCDATE(), cb.evidence_due_date) AS days_remaining,
    t.transaction_id,
    t.payment_intent_id,
    t.created_at AS transaction_date,
    c.email AS customer_email,
    m.business_name AS merchant_name,
    m.email AS merchant_email
FROM chargebacks cb
INNER JOIN transactions t ON cb.transaction_id = t.transaction_id
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE cb.status = 'OPEN'
    AND cb.evidence_due_date IS NOT NULL
    AND cb.is_deleted = 0
ORDER BY cb.evidence_due_date ASC;

-- 7. PERFORMANCE ANALYTICS QUERIES

-- Query 7.1: Hourly transaction volume (last 24 hours)
-- Use case: Traffic pattern analysis

SELECT 
    DATEPART(HOUR, t.created_at) AS transaction_hour,
    COUNT(*) AS transaction_count,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS successful_count,
    AVG(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE NULL END) AS avg_transaction_amount,
    AVG(fc.risk_score) AS avg_risk_score
FROM transactions t
LEFT JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE t.created_at >= DATEADD(HOUR, -24, GETUTCDATE())
    AND t.is_deleted = 0
GROUP BY DATEPART(HOUR, t.created_at)
ORDER BY transaction_hour;

-- Query 7.2: Payment method performance
-- Use case: Optimize payment method options

SELECT 
    pm.type,
    pm.card_brand,
    COUNT(t.transaction_id) AS transaction_count,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS successful_count,
    SUM(CASE WHEN t.status = 'FAILED' THEN 1 ELSE 0 END) AS failed_count,
    CAST(SUM(CASE WHEN t.status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(t.transaction_id), 0) * 100 AS success_rate,
    AVG(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE NULL END) AS avg_successful_amount
FROM payment_methods pm
INNER JOIN transactions t ON pm.payment_method_id = t.payment_method_id
WHERE t.created_at >= DATEADD(MONTH, -1, GETUTCDATE())
    AND t.is_deleted = 0
    AND pm.is_deleted = 0
GROUP BY pm.type, pm.card_brand
ORDER BY transaction_count DESC;

-- Query 7.3: Geographic transaction distribution
-- Use case: Market analysis

SELECT 
    t.country_code,
    COUNT(*) AS transaction_count,
    COUNT(DISTINCT t.customer_id) AS unique_customers,
    COUNT(DISTINCT t.merchant_id) AS unique_merchants,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE 0 END) AS total_volume,
    AVG(t.amount) AS avg_transaction_amount,
    AVG(fc.risk_score) AS avg_risk_score
FROM transactions t
LEFT JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE t.created_at >= DATEADD(MONTH, -1, GETUTCDATE())
    AND t.is_deleted = 0
    AND t.country_code IS NOT NULL
GROUP BY t.country_code
ORDER BY total_volume DESC;

-- 8. CUSTOMER BEHAVIOR QUERIES

-- Query 8.1: Customer lifetime value (CLV)
-- Use case: Customer segmentation

SELECT 
    c.customer_id,
    c.email,
    c.country_code,
    c.created_at AS customer_since,
    DATEDIFF(DAY, c.created_at, GETUTCDATE()) AS customer_age_days,
    COUNT(DISTINCT t.transaction_id) AS total_transactions,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE 0 END) AS total_spent,
    AVG(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE NULL END) AS avg_transaction_value,
    MAX(t.created_at) AS last_transaction_date,
    DATEDIFF(DAY, MAX(t.created_at), GETUTCDATE()) AS days_since_last_transaction
FROM customers c
LEFT JOIN transactions t ON c.customer_id = t.customer_id AND t.is_deleted = 0
WHERE c.is_deleted = 0
GROUP BY c.customer_id, c.email, c.country_code, c.created_at
HAVING COUNT(DISTINCT t.transaction_id) > 0
ORDER BY total_spent DESC;

-- Query 8.2: Customer payment method diversity
-- Use case: Understanding payment preferences

SELECT 
    c.customer_id,
    c.email,
    COUNT(DISTINCT pm.payment_method_id) AS total_payment_methods,
    COUNT(DISTINCT pm.card_brand) AS different_brands,
    STRING_AGG(DISTINCT pm.type, ', ') AS payment_types_used,
    MAX(pm.created_at) AS last_method_added
FROM customers c
INNER JOIN payment_methods pm ON c.customer_id = pm.customer_id
WHERE c.is_deleted = 0
    AND pm.is_deleted = 0
GROUP BY c.customer_id, c.email
HAVING COUNT(DISTINCT pm.payment_method_id) > 1
ORDER BY total_payment_methods DESC;

-- Query 8.3: Repeat customer rate
-- Use case: Retention analysis

WITH customer_transaction_counts AS (
    SELECT 
        customer_id,
        COUNT(*) AS transaction_count
    FROM transactions
    WHERE status = 'SUCCEEDED'
        AND created_at >= DATEADD(MONTH, -6, GETUTCDATE())
        AND is_deleted = 0
    GROUP BY customer_id
)
SELECT 
    CASE 
        WHEN transaction_count = 1 THEN 'One-time'
        WHEN transaction_count BETWEEN 2 AND 5 THEN 'Occasional'
        WHEN transaction_count BETWEEN 6 AND 20 THEN 'Regular'
        ELSE 'Power User'
    END AS customer_segment,
    COUNT(*) AS customer_count,
    CAST(COUNT(*) AS FLOAT) / (SELECT COUNT(*) FROM customer_transaction_counts) * 100 AS percentage
FROM customer_transaction_counts
GROUP BY 
    CASE 
        WHEN transaction_count = 1 THEN 'One-time'
        WHEN transaction_count BETWEEN 2 AND 5 THEN 'Occasional'
        WHEN transaction_count BETWEEN 6 AND 20 THEN 'Regular'
        ELSE 'Power User'
    END
ORDER BY customer_count DESC;

-- 9. OPERATIONAL MONITORING QUERIES

-- Query 9.1: Transaction processing latency
-- Use case: System performance monitoring
-- Note: This assumes a separate audit/log table tracking processing times

SELECT 
    DATEPART(HOUR, created_at) AS hour_of_day,
    COUNT(*) AS transaction_count,
    AVG(DATEDIFF(MILLISECOND, created_at, updated_at)) AS avg_processing_ms,
    MAX(DATEDIFF(MILLISECOND, created_at, updated_at)) AS max_processing_ms,
    MIN(DATEDIFF(MILLISECOND, created_at, updated_at)) AS min_processing_ms
FROM transactions
WHERE created_at >= DATEADD(HOUR, -24, GETUTCDATE())
    AND status IN ('SUCCEEDED', 'FAILED')
    AND is_deleted = 0
GROUP BY DATEPART(HOUR, created_at)
ORDER BY hour_of_day;

-- Query 9.2: System health check
-- Use case: Real-time monitoring dashboard

SELECT 
    'Last Hour' AS time_period,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS succeeded,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) AS failed,
    SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) AS pending,
    CAST(SUM(CASE WHEN status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 AS success_rate,
    SUM(CASE WHEN status = 'SUCCEEDED' THEN amount ELSE 0 END) AS total_volume,
    AVG(fc.risk_score) AS avg_risk_score
FROM transactions t
LEFT JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE t.created_at >= DATEADD(HOUR, -1, GETUTCDATE())
    AND t.is_deleted = 0;

-- Query 9.3: Database table sizes (for capacity planning)
-- Use case: Infrastructure scaling decisions

SELECT 
    t.name AS table_name,
    p.rows AS row_count,
    SUM(a.total_pages) * 8 / 1024 AS total_space_mb,
    SUM(a.used_pages) * 8 / 1024 AS used_space_mb,
    (SUM(a.total_pages) - SUM(a.used_pages)) * 8 / 1024 AS unused_space_mb
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name IN ('transactions', 'customers', 'merchants', 'payment_methods', 
                 'refunds', 'chargebacks', 'fraud_checks', 'subscriptions', 'subscription_payments')
    AND i.object_id > 255
    AND i.index_id <= 1
GROUP BY t.name, p.rows
ORDER BY used_space_mb DESC;

-- END OF OLTP QUERIES

-- Note: All queries are optimized for Azure SQL Database
-- Indexes mentioned in schema.sql support these query patterns
-- Expected response times: < 50ms for transactional, < 2s for analytical