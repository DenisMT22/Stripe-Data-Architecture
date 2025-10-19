-- STRIPE OLAP - ANALYTICAL QUERIES

-- Platform: Azure Synapse Analytics
-- Query patterns: Aggregations, Time-series, Multi-dimensional analysis

-- 1. REVENUE ANALYSIS

-- Query 1.1: Monthly revenue trend (Year-over-Year comparison)
-- Use case: Executive dashboard - Revenue growth
SELECT 
    t.year,
    t.month,
    t.month_name,
    SUM(f.amount) AS gross_revenue,
    SUM(f.net_amount) AS net_revenue,
    COUNT(*) AS transaction_count,
    COUNT(DISTINCT f.customer_key) AS unique_customers,
    
    -- YoY comparison
    LAG(SUM(f.amount), 12) OVER (ORDER BY t.year, t.month) AS prev_year_revenue,
    
    -- Growth rate
    CASE 
        WHEN LAG(SUM(f.amount), 12) OVER (ORDER BY t.year, t.month) > 0
        THEN ((SUM(f.amount) / LAG(SUM(f.amount), 12) OVER (ORDER BY t.year, t.month)) - 1) * 100
        ELSE NULL
    END AS yoy_growth_rate
    
FROM fact_transactions f
INNER JOIN dim_time t ON f.time_key = t.time_key
WHERE f.is_successful = 1
    AND t.year >= 2024
GROUP BY t.year, t.month, t.month_name
ORDER BY t.year, t.month;

-- Query 1.2: Revenue by geography (multi-dimensional)
-- Use case: Geographic expansion analysis
SELECT 
    g.continent,
    g.region,
    g.country_name,
    g.currency_code,
    
    SUM(f.amount) AS total_revenue,
    COUNT(*) AS transaction_count,
    COUNT(DISTINCT f.customer_key) AS unique_customers,
    COUNT(DISTINCT f.merchant_key) AS unique_merchants,
    
    AVG(f.amount) AS avg_transaction_value,
    
    -- Percentage of total revenue
    SUM(f.amount) / SUM(SUM(f.amount)) OVER () * 100 AS pct_of_total_revenue,
    
    -- Rank by revenue
    RANK() OVER (ORDER BY SUM(f.amount) DESC) AS revenue_rank
    
FROM fact_transactions f
INNER JOIN dim_geography g ON f.geography_key = g.geography_key
WHERE f.is_successful = 1
    AND f.time_key >= 20250101
GROUP BY 
    g.continent,
    g.region,
    g.country_name,
    g.currency_code
ORDER BY total_revenue DESC;

-- Query 1.3: Revenue by merchant tier and industry
-- Use case: Identify high-value segments
SELECT 
    m.merchant_tier,
    m.industry,
    m.industry_group,
    
    COUNT(DISTINCT m.merchant_key) AS merchant_count,
    SUM(f.amount) AS total_revenue,
    AVG(f.amount) AS avg_transaction_value,
    
    -- Revenue per merchant
    SUM(f.amount) / COUNT(DISTINCT m.merchant_key) AS revenue_per_merchant,
    
    -- Market share
    SUM(f.amount) / SUM(SUM(f.amount)) OVER () * 100 AS market_share_pct
    
FROM fact_transactions f
INNER JOIN dim_merchant m ON f.merchant_key = m.merchant_key
WHERE f.is_successful = 1
    AND m.is_current = 1
    AND f.time_key >= 20250101
GROUP BY 
    m.merchant_tier,
    m.industry,
    m.industry_group
ORDER BY total_revenue DESC;

-- 2. CUSTOMER ANALYTICS

-- Query 2.1: Customer segmentation (RFM-like analysis)
-- Use case: Customer lifetime value and segmentation
WITH customer_metrics AS (
    SELECT 
        c.customer_key,
        c.full_name,
        c.email,
        c.customer_segment,
        c.country_name,
        
        COUNT(f.transaction_key) AS total_transactions,
        SUM(f.amount) AS total_spent,
        AVG(f.amount) AS avg_order_value,
        MAX(t.full_date) AS last_transaction_date,
        DATEDIFF(DAY, MAX(t.full_date), GETDATE()) AS days_since_last_purchase,
        
        -- First purchase date
        MIN(t.full_date) AS first_purchase_date,
        DATEDIFF(DAY, MIN(t.full_date), GETDATE()) AS customer_age_days
        
    FROM fact_transactions f
    INNER JOIN dim_customer c ON f.customer_key = c.customer_key
    INNER JOIN dim_time t ON f.time_key = t.time_key
    WHERE f.is_successful = 1
        AND c.is_current = 1
    GROUP BY 
        c.customer_key,
        c.full_name,
        c.email,
        c.customer_segment,
        c.country_name
)
SELECT 
    customer_segment,
    COUNT(*) AS customer_count,
    
    AVG(total_spent) AS avg_lifetime_value,
    AVG(total_transactions) AS avg_transaction_count,
    AVG(avg_order_value) AS avg_order_value,
    AVG(days_since_last_purchase) AS avg_days_since_purchase,
    
    -- Segmentation
    SUM(CASE WHEN total_spent > 10000 THEN 1 ELSE 0 END) AS high_value_customers,
    SUM(CASE WHEN days_since_last_purchase <= 30 THEN 1 ELSE 0 END) AS active_customers,
    SUM(CASE WHEN days_since_last_purchase > 90 THEN 1 ELSE 0 END) AS at_risk_customers
    
FROM customer_metrics
GROUP BY customer_segment
ORDER BY avg_lifetime_value DESC;

-- Query 2.2: Customer cohort analysis (retention)
-- Use case: Track customer retention over time
WITH customer_cohorts AS (
    SELECT 
        c.customer_key,
        MIN(t.year_month) AS cohort_month
    FROM fact_transactions f
    INNER JOIN dim_customer c ON f.customer_key = c.customer_key
    INNER JOIN (
        SELECT 
            time_key,
            year * 100 + month AS year_month
        FROM dim_time
    ) t ON f.time_key = t.time_key
    WHERE f.is_successful = 1
    GROUP BY c.customer_key
),
cohort_activity AS (
    SELECT 
        co.cohort_month,
        t.year_month AS activity_month,
        t.year_month - co.cohort_month AS months_since_cohort,
        COUNT(DISTINCT f.customer_key) AS active_customers
    FROM fact_transactions f
    INNER JOIN customer_cohorts co ON f.customer_key = co.customer_key
    INNER JOIN (
        SELECT 
            time_key,
            year * 100 + month AS year_month
        FROM dim_time
    ) t ON f.time_key = t.time_key
    WHERE f.is_successful = 1
    GROUP BY co.cohort_month, t.year_month
)
SELECT 
    cohort_month,
    months_since_cohort,
    active_customers,
    
    -- Retention rate (compared to cohort size at month 0)
    CAST(active_customers AS FLOAT) / 
        FIRST_VALUE(active_customers) OVER (
            PARTITION BY cohort_month 
            ORDER BY months_since_cohort
        ) * 100 AS retention_rate
    
FROM cohort_activity
WHERE months_since_cohort <= 12
ORDER BY cohort_month, months_since_cohort;

-- Query 2.3: Customer churn prediction indicators
-- Use case: Identify customers likely to churn
SELECT 
    c.customer_key,
    c.full_name,
    c.email,
    c.customer_segment,
    
    COUNT(f.transaction_key) AS total_transactions,
    SUM(f.amount) AS total_spent,
    MAX(t.full_date) AS last_transaction_date,
    DATEDIFF(DAY, MAX(t.full_date), GETDATE()) AS days_inactive,
    
    -- Average days between transactions
    AVG(DATEDIFF(DAY, 
        LAG(t.full_date) OVER (PARTITION BY c.customer_key ORDER BY t.full_date),
        t.full_date
    )) AS avg_days_between_purchases,
    
    -- Declining transaction trend
    SUM(CASE WHEN t.year = 2025 THEN f.amount ELSE 0 END) AS revenue_2025,
    SUM(CASE WHEN t.year = 2024 THEN f.amount ELSE 0 END) AS revenue_2024,
    
    CASE 
        WHEN SUM(CASE WHEN t.year = 2024 THEN f.amount ELSE 0 END) > 0
        THEN ((SUM(CASE WHEN t.year = 2025 THEN f.amount ELSE 0 END) / 
               SUM(CASE WHEN t.year = 2024 THEN f.amount ELSE 0 END)) - 1) * 100
        ELSE NULL
    END AS yoy_revenue_change,
    
    -- Churn risk score
    CASE 
        WHEN DATEDIFF(DAY, MAX(t.full_date), GETDATE()) > 180 THEN 'High Risk'
        WHEN DATEDIFF(DAY, MAX(t.full_date), GETDATE()) > 90 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS churn_risk
    
FROM fact_transactions f
INNER JOIN dim_customer c ON f.customer_key = c.customer_key
INNER JOIN dim_time t ON f.time_key = t.time_key
WHERE f.is_successful = 1
    AND c.is_current = 1
GROUP BY 
    c.customer_key,
    c.full_name,
    c.email,
    c.customer_segment
HAVING DATEDIFF(DAY, MAX(t.full_date), GETDATE()) > 60
ORDER BY days_inactive DESC, total_spent DESC;

-- 3. PAYMENT METHOD ANALYSIS

-- Query 3.1: Payment method performance by geography
-- Use case: Optimize payment options by region
SELECT 
    g.region,
    g.country_name,
    pm.type,
    pm.card_brand,
    
    COUNT(*) AS transaction_count,
    SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS successful_count,
    
    -- Success rate
    CAST(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 AS success_rate,
    
    SUM(f.amount) AS total_volume,
    AVG(f.amount) AS avg_transaction_amount,
    
    -- Market share
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY g.region) AS pct_of_region
    
FROM fact_transactions f
INNER JOIN dim_geography g ON f.geography_key = g.geography_key
INNER JOIN dim_payment_method pm ON f.payment_method_key = pm.payment_method_key
WHERE f.time_key >= 20250101
GROUP BY 
    g.region,
    g.country_name,
    pm.type,
    pm.card_brand
HAVING COUNT(*) > 100
ORDER BY g.region, transaction_count DESC;

-- Query 3.2: Digital wallet adoption trend
-- Use case: Track contactless payment growth
SELECT 
    t.year,
    t.quarter,
    
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN pm.is_digital_wallet = 1 THEN 1 ELSE 0 END) AS digital_wallet_count,
    
    -- Adoption rate
    CAST(SUM(CASE WHEN pm.is_digital_wallet = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 AS digital_wallet_adoption_rate,
    
    -- YoY comparison
    LAG(CAST(SUM(CASE WHEN pm.is_digital_wallet = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100, 4) OVER (ORDER BY t.year, t.quarter) AS prev_year_adoption_rate
    
FROM fact_transactions f
INNER JOIN dim_time t ON f.time_key = t.time_key
INNER JOIN dim_payment_method pm ON f.payment_method_key = pm.payment_method_key
WHERE f.is_successful = 1
GROUP BY t.year, t.quarter
ORDER BY t.year, t.quarter;

-- 4. FRAUD AND RISK ANALYSIS

-- Query 4.1: Fraud patterns by geography and payment method
-- Use case: Identify high-risk combinations
SELECT 
    g.country_name,
    g.region,
    pm.type,
    pm.card_brand,
    
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS fraud_count,
    
    -- Fraud rate
    CAST(SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 AS fraud_rate,
    
    SUM(CASE WHEN f.is_fraudulent = 1 THEN f.amount ELSE 0 END) AS fraud_amount,
    
    -- Compare to average
    CAST(SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 - 
    AVG(CAST(SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100) OVER () AS fraud_rate_vs_avg
    
FROM fact_transactions f
INNER JOIN dim_geography g ON f.geography_key = g.geography_key
INNER JOIN dim_payment_method pm ON f.payment_method_key = pm.payment_method_key
WHERE f.time_key >= 20250101
GROUP BY 
    g.country_name,
    g.region,
    pm.type,
    pm.card_brand
HAVING COUNT(*) > 50
ORDER BY fraud_rate DESC;

-- Query 4.2: Time-based fraud patterns
-- Use case: Detect temporal fraud trends
SELECT 
    t.day_name,
    t.hour_of_day,
    
    COUNT(*) AS transaction_count,
    SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS fraud_count,
    
    CAST(SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 AS fraud_rate,
    
    AVG(f.amount) AS avg_transaction_amount
    
FROM fact_transactions f
INNER JOIN (
    SELECT 
        time_key,
        day_name,
        DATEPART(HOUR, CAST(time_key AS VARCHAR(8)) + ' 00:00:00') AS hour_of_day
    FROM dim_time
) t ON f.time_key = t.time_key
WHERE f.time_key >= 20250901
GROUP BY t.day_name, t.hour_of_day
ORDER BY fraud_rate DESC;

-- 5. BUSINESS PERFORMANCE METRICS (KPIs)

-- Query 5.1: Executive dashboard - Key metrics
-- Use case: C-level monthly report
SELECT 
    t.year,
    t.month,
    t.month_name,
    
    -- Revenue metrics
    SUM(f.amount) AS gross_revenue,
    SUM(f.net_amount) AS net_revenue,
    SUM(f.processing_fee) AS total_fees,
    
    -- Volume metrics
    COUNT(*) AS total_transactions,
    COUNT(DISTINCT f.customer_key) AS unique_customers,
    COUNT(DISTINCT f.merchant_key) AS active_merchants,
    
    -- Averages
    AVG(f.amount) AS avg_transaction_value,
    SUM(f.amount) / NULLIF(COUNT(DISTINCT f.customer_key), 0) AS revenue_per_customer,
    
    -- Success metrics
    CAST(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 AS success_rate,
    
    -- Problem metrics
    CAST(SUM(CASE WHEN f.is_refunded = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END), 0) * 100 AS refund_rate,
    
    CAST(SUM(CASE WHEN f.is_disputed = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END), 0) * 100 AS chargeback_rate,
    
    CAST(SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(*), 0) * 100 AS fraud_rate,
    
    -- Growth (MoM)
    (SUM(f.amount) - LAG(SUM(f.amount)) OVER (ORDER BY t.year, t.month)) / 
        NULLIF(LAG(SUM(f.amount)) OVER (ORDER BY t.year, t.month), 0) * 100 AS mom_revenue_growth
    
FROM fact_transactions f
INNER JOIN dim_time t ON f.time_key = t.time_key
WHERE t.year >= 2024
GROUP BY t.year, t.month, t.month_name
ORDER BY t.year, t.month;

-- Query 5.2: Merchant performance leaderboard
-- Use case: Identify top and bottom performers
WITH merchant_metrics AS (
    SELECT 
        m.merchant_key,
        m.business_name,
        m.industry,
        m.country_name,
        m.merchant_tier,
        
        COUNT(f.transaction_key) AS transaction_count,
        SUM(f.amount) AS total_revenue,
        AVG(f.amount) AS avg_transaction_value,
        COUNT(DISTINCT f.customer_key) AS unique_customers,
        
        CAST(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(COUNT(*), 0) * 100 AS success_rate,
        
        CAST(SUM(CASE WHEN f.is_refunded = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END), 0) * 100 AS refund_rate
        
    FROM fact_transactions f
    INNER JOIN dim_merchant m ON f.merchant_key = m.merchant_key
    WHERE m.is_current = 1
        AND f.time_key >= 20250101
    GROUP BY 
        m.merchant_key,
        m.business_name,
        m.industry,
        m.country_name,
        m.merchant_tier
)
SELECT 
    business_name,
    industry,
    country_name,
    merchant_tier,
    
    transaction_count,
    total_revenue,
    avg_transaction_value,
    unique_customers,
    success_rate,
    refund_rate,
    
    -- Percentile rank
    PERCENT_RANK() OVER (ORDER BY total_revenue) AS revenue_percentile,
    
    -- Performance category
    CASE 
        WHEN PERCENT_RANK() OVER (ORDER BY total_revenue) >= 0.9 THEN 'Top 10%'
        WHEN PERCENT_RANK() OVER (ORDER BY total_revenue) >= 0.75 THEN 'Top 25%'
        WHEN PERCENT_RANK() OVER (ORDER BY total_revenue) <= 0.1 THEN 'Bottom 10%'
        ELSE 'Middle 50%'
    END AS performance_tier
    
FROM merchant_metrics
WHERE transaction_count > 10
ORDER BY total_revenue DESC;

-- 6. TIME-SERIES ANALYSIS

-- Query 6.1: Daily revenue with moving averages
-- Use case: Trend analysis with smoothing
SELECT 
    t.full_date,
    t.day_name,
    t.is_weekend,
    
    SUM(f.amount) AS daily_revenue,
    COUNT(*) AS transaction_count,
    
    -- 7-day moving average
    AVG(SUM(f.amount)) OVER (
        ORDER BY t.full_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS ma_7day,
    
    -- 30-day moving average
    AVG(SUM(f.amount)) OVER (
        ORDER BY t.full_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS ma_30day,
    
    -- Day-over-day growth
    (SUM(f.amount) - LAG(SUM(f.amount)) OVER (ORDER BY t.full_date)) / 
        NULLIF(LAG(SUM(f.amount)) OVER (ORDER BY t.full_date), 0) * 100 AS dod_growth_rate
    
FROM fact_transactions f
INNER JOIN dim_time t ON f.time_key = t.time_key
WHERE f.is_successful = 1
    AND t.full_date >= DATEADD(DAY, -90, GETDATE())
GROUP BY t.full_date, t.day_name, t.is_weekend
ORDER BY t.full_date;

-- Query 6.2: Seasonality analysis
-- Use case: Identify seasonal patterns
SELECT 
    t.month,
    t.month_name,
    t.week_of_year,
    
    AVG(daily_revenue) AS avg_daily_revenue,
    MIN(daily_revenue) AS min_daily_revenue,
    MAX(daily_revenue) AS max_daily_revenue,
    STDEV(daily_revenue) AS stddev_daily_revenue,
    
    -- Coefficient of variation (volatility)
    CASE 
        WHEN AVG(daily_revenue) > 0 
        THEN STDEV(daily_revenue) / AVG(daily_revenue) * 100
        ELSE NULL
    END AS coefficient_of_variation
    
FROM (
    SELECT 
        t.full_date,
        t.month,
        t.month_name,
        t.week_of_year,
        SUM(f.amount) AS daily_revenue
    FROM fact_transactions f
    INNER JOIN dim_time t ON f.time_key = t.time_key
    WHERE f.is_successful = 1
        AND t.year >= 2024
    GROUP BY t.full_date, t.month, t.month_name, t.week_of_year
) daily_data
GROUP BY t.month, t.month_name, t.week_of_year
ORDER BY t.month, t.week_of_year;

-- 7. USING PRE-COMPUTED AGGREGATES (for ultra-fast queries)

-- Query 7.1: Quick merchant daily summary (uses materialized view)
-- Use case: Real-time dashboard refresh
SELECT 
    m.business_name,
    t.full_date,
    mv.transaction_count,
    mv.total_revenue,
    mv.net_revenue,
    mv.avg_transaction_amount,
    mv.unique_customers
FROM mv_daily_merchant_summary mv
INNER JOIN dim_merchant m ON mv.merchant_key = m.merchant_key
INNER JOIN dim_time t ON mv.time_key = t.time_key
WHERE m.is_current = 1
    AND t.full_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY m.business_name, t.full_date;

-- Query 7.2: Monthly KPIs from aggregates (uses agg_monthly_metrics)
-- Use case: Executive monthly report (instant)
SELECT 
    amm.year_month,
    m.business_name,
    m.industry,
    
    amm.gross_revenue,
    amm.net_revenue,
    amm.transaction_count,
    amm.unique_customers,
    amm.new_customers,
    amm.returning_customers,
    amm.avg_order_value,
    amm.customer_lifetime_value,
    amm.refund_rate,
    amm.chargeback_rate,
    amm.fraud_rate
    
FROM agg_monthly_metrics amm
INNER JOIN dim_merchant m ON amm.merchant_key = m.merchant_key
WHERE m.is_current = 1
    AND amm.year_month >= 202501
ORDER BY amm.year_month, amm.gross_revenue DESC;

-- END OF OLAP QUERIES

-- Performance notes:
-- - All queries leverage columnstore compression
-- - Partition elimination on time_key reduces scan volume
-- - Materialized views provide sub-second response times
-- - Aggregate tables pre-compute common metrics
-- - Expected query times: < 5 seconds for complex analytics on 300M+ rows


