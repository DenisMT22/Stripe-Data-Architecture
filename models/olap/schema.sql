-- STRIPE OLAP DATA WAREHOUSE - SCHEMA CREATION

-- Platform: Azure Synapse Analytics (Dedicated SQL Pool)
-- Distribution Strategy: Hash for facts, Replicate for dimensions

-- DIMENSION TABLES

-- 1. DIM_TIME - Calendar dimension (pre-computed)

CREATE TABLE dim_time (
    time_key INT NOT NULL,
    full_date DATE NOT NULL,
    year SMALLINT NOT NULL,
    quarter TINYINT NOT NULL,
    month TINYINT NOT NULL,
    month_name NVARCHAR(20) NOT NULL,
    week_of_year TINYINT NOT NULL,
    day_of_month TINYINT NOT NULL,
    day_of_week TINYINT NOT NULL,
    day_name NVARCHAR(20) NOT NULL,
    is_weekend BIT NOT NULL,
    is_holiday BIT NOT NULL DEFAULT 0,
    fiscal_year SMALLINT NOT NULL,
    fiscal_quarter TINYINT NOT NULL,
    fiscal_period TINYINT NOT NULL,
    
    CONSTRAINT PK_dim_time PRIMARY KEY NONCLUSTERED (time_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);

-- 2. DIM_CUSTOMER - Customer dimension (SCD Type 2)

CREATE TABLE dim_customer (
    customer_key INT NOT NULL,
    customer_id BIGINT NOT NULL,
    email NVARCHAR(255) NOT NULL,
    first_name NVARCHAR(100) NOT NULL,
    last_name NVARCHAR(100) NOT NULL,
    full_name NVARCHAR(200) NOT NULL,
    country_code CHAR(2) NOT NULL,
    country_name NVARCHAR(100) NOT NULL,
    risk_score DECIMAL(5,2) NOT NULL,
    risk_category NVARCHAR(20) NOT NULL,
    is_verified BIT NOT NULL,
    customer_segment NVARCHAR(50) NOT NULL,
    lifetime_value DECIMAL(18,2) NOT NULL DEFAULT 0,
    
    -- SCD Type 2 fields
    effective_date DATE NOT NULL,
    expiration_date DATE NULL,
    is_current BIT NOT NULL DEFAULT 1,
    version INT NOT NULL DEFAULT 1,
    
    CONSTRAINT PK_dim_customer PRIMARY KEY NONCLUSTERED (customer_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);

-- 3. DIM_MERCHANT - Merchant dimension (SCD Type 2)

CREATE TABLE dim_merchant (
    merchant_key INT NOT NULL,
    merchant_id BIGINT NOT NULL,
    business_name NVARCHAR(255) NOT NULL,
    legal_name NVARCHAR(255) NOT NULL,
    email NVARCHAR(255) NOT NULL,
    country_code CHAR(2) NOT NULL,
    country_name NVARCHAR(100) NOT NULL,
    industry NVARCHAR(100) NOT NULL,
    industry_group NVARCHAR(50) NOT NULL,
    mcc_code CHAR(4) NOT NULL,
    mcc_description NVARCHAR(200) NOT NULL,
    is_active BIT NOT NULL,
    kyc_status NVARCHAR(20) NOT NULL,
    merchant_tier NVARCHAR(20) NOT NULL,
    
    -- SCD Type 2 fields
    effective_date DATE NOT NULL,
    expiration_date DATE NULL,
    is_current BIT NOT NULL DEFAULT 1,
    version INT NOT NULL DEFAULT 1,
    
    CONSTRAINT PK_dim_merchant PRIMARY KEY NONCLUSTERED (merchant_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);

-- 4. DIM_PAYMENT_METHOD - Payment method dimension

CREATE TABLE dim_payment_method (
    payment_method_key INT NOT NULL,
    payment_method_id BIGINT NOT NULL,
    type NVARCHAR(20) NOT NULL,
    type_description NVARCHAR(100) NOT NULL,
    card_brand NVARCHAR(20) NULL,
    card_brand_category NVARCHAR(50) NULL,
    card_type NVARCHAR(20) NULL,
    issuing_bank NVARCHAR(100) NULL,
    issuing_country CHAR(2) NULL,
    is_digital_wallet BIT NOT NULL DEFAULT 0,
    processing_cost_pct DECIMAL(5,4) NOT NULL,
    
    CONSTRAINT PK_dim_payment_method PRIMARY KEY NONCLUSTERED (payment_method_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);

-- 5. DIM_GEOGRAPHY - Geographic hierarchy dimension

CREATE TABLE dim_geography (
    geography_key INT NOT NULL,
    country_code CHAR(2) NOT NULL,
    country_name NVARCHAR(100) NOT NULL,
    region NVARCHAR(50) NOT NULL,
    sub_region NVARCHAR(50) NOT NULL,
    continent NVARCHAR(50) NOT NULL,
    currency_code CHAR(3) NOT NULL,
    currency_name NVARCHAR(50) NOT NULL,
    timezone NVARCHAR(50) NOT NULL,
    gdp_per_capita DECIMAL(18,2) NULL,
    population BIGINT NULL,
    internet_penetration DECIMAL(5,2) NULL,
    is_gdpr_country BIT NOT NULL DEFAULT 0,
    is_high_risk BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT PK_dim_geography PRIMARY KEY NONCLUSTERED (geography_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);

-- 6. DIM_PRODUCT - Product dimension

CREATE TABLE dim_product (
    product_key INT NOT NULL,
    product_code NVARCHAR(50) NOT NULL,
    product_name NVARCHAR(100) NOT NULL,
    product_category NVARCHAR(50) NOT NULL,
    product_family NVARCHAR(50) NOT NULL,
    pricing_model NVARCHAR(20) NOT NULL,
    base_fee DECIMAL(18,2) NOT NULL,
    percentage_fee DECIMAL(5,4) NOT NULL,
    is_active BIT NOT NULL DEFAULT 1,
    
    CONSTRAINT PK_dim_product PRIMARY KEY NONCLUSTERED (product_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);

-- FACT TABLE

-- 7. FACT_TRANSACTIONS - Main fact table (granular transactions)

CREATE TABLE fact_transactions (
    transaction_key BIGINT NOT NULL,
    transaction_id BIGINT NOT NULL,
    
    -- Foreign keys to dimensions
    time_key INT NOT NULL,
    customer_key INT NOT NULL,
        merchant_key INT NOT NULL,
    payment_method_key INT NOT NULL,
    geography_key INT NOT NULL,
    product_key INT NOT NULL,
    
    -- Measures (Metrics)
    amount DECIMAL(18,2) NOT NULL,
    processing_fee DECIMAL(18,2) NOT NULL,
    net_amount DECIMAL(18,2) NOT NULL,
    refund_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    chargeback_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    
    -- Flags
    is_successful BIT NOT NULL,
    is_refunded BIT NOT NULL DEFAULT 0,
    is_disputed BIT NOT NULL DEFAULT 0,
    is_fraudulent BIT NOT NULL DEFAULT 0,
    
    -- Counters
    transaction_count INT NOT NULL DEFAULT 1,
    
    -- Timestamps
    transaction_datetime DATETIME2 NOT NULL,
    inserted_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_fact_transactions PRIMARY KEY NONCLUSTERED (transaction_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = HASH(customer_key),
    CLUSTERED COLUMNSTORE INDEX,
    PARTITION (
        time_key RANGE RIGHT FOR VALUES (
            20250101, 20250201, 20250301, 20250401, 20250501, 20250601,
            20250701, 20250801, 20250901, 20251001, 20251101, 20251201,
            20260101, 20260201, 20260301, 20260401, 20260501, 20260601,
            20260701, 20260801, 20260901, 20261001, 20261101, 20261201,
            20270101
        )
    )
);

-- AGGREGATE TABLES (Pre-computed for performance)

-- 8. AGG_DAILY_REVENUE - Daily aggregated metrics

CREATE TABLE agg_daily_revenue (
    agg_key BIGINT NOT NULL IDENTITY(1,1),
    date_key INT NOT NULL,
    merchant_key INT NOT NULL,
    geography_key INT NOT NULL,
    payment_method_key INT NOT NULL,
    
    -- Metrics
    transaction_count INT NOT NULL,
    successful_count INT NOT NULL,
    failed_count INT NOT NULL,
    refunded_count INT NOT NULL,
    
    total_amount DECIMAL(18,2) NOT NULL,
    total_fees DECIMAL(18,2) NOT NULL,
    total_net DECIMAL(18,2) NOT NULL,
    
    avg_transaction_amount DECIMAL(18,2) NOT NULL,
    max_transaction_amount DECIMAL(18,2) NOT NULL,
    min_transaction_amount DECIMAL(18,2) NOT NULL,
    
    unique_customers INT NOT NULL,
    
    calculated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_agg_daily_revenue PRIMARY KEY NONCLUSTERED (agg_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = HASH(merchant_key),
    CLUSTERED COLUMNSTORE INDEX,
    PARTITION (
        date_key RANGE RIGHT FOR VALUES (
            20250101, 20250201, 20250301, 20250401, 20250501, 20250601,
            20250701, 20250801, 20250901, 20251001, 20251101, 20251201,
            20260101, 20260201, 20260301, 20260401, 20260501, 20260601,
            20260701, 20260801, 20260901, 20261001, 20261101, 20261201,
            20270101
        )
    )
);

-- 9. AGG_MONTHLY_METRICS - Monthly KPIs for executive reporting

CREATE TABLE agg_monthly_metrics (
    agg_key BIGINT NOT NULL IDENTITY(1,1),
    year_month INT NOT NULL,
    merchant_key INT NOT NULL,
    
    -- KPIs
    gross_revenue DECIMAL(18,2) NOT NULL,
    net_revenue DECIMAL(18,2) NOT NULL,
    transaction_count INT NOT NULL,
    
    unique_customers INT NOT NULL,
    new_customers INT NOT NULL,
    returning_customers INT NOT NULL,
    
    avg_order_value DECIMAL(18,2) NOT NULL,
    customer_lifetime_value DECIMAL(18,2) NOT NULL,
    
    churn_rate DECIMAL(5,2) NOT NULL,
    refund_rate DECIMAL(5,2) NOT NULL,
    chargeback_rate DECIMAL(5,2) NOT NULL,
    fraud_rate DECIMAL(5,2) NOT NULL,
    
    calculated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_agg_monthly_metrics PRIMARY KEY NONCLUSTERED (agg_key) NOT ENFORCED
)
WITH (
    DISTRIBUTION = HASH(merchant_key),
    CLUSTERED COLUMNSTORE INDEX
);

-- VIEWS

-- VIEW: vw_transaction_details - Denormalized transaction view

CREATE VIEW vw_transaction_details
AS
SELECT 
    f.transaction_key,
    f.transaction_id,
    
    -- Time
    t.full_date,
    t.year,
    t.quarter,
    t.month,
    t.month_name,
    t.day_name,
    
    -- Customer
    c.customer_id,
    c.full_name AS customer_name,
    c.email AS customer_email,
    c.country_name AS customer_country,
    c.customer_segment,
    
    -- Merchant
    m.merchant_id,
    m.business_name AS merchant_name,
    m.industry,
    m.merchant_tier,
    
    -- Geography
    g.country_name AS transaction_country,
    g.region,
    g.continent,
    g.currency_code,
    
    -- Payment Method
    pm.type AS payment_type,
    pm.card_brand,
    pm.card_type,
    
    -- Product
    p.product_name,
    p.product_category,
    
    -- Metrics
    f.amount,
    f.processing_fee,
    f.net_amount,
    f.refund_amount,
    f.chargeback_amount,
    
    -- Flags
    f.is_successful,
    f.is_refunded,
    f.is_disputed,
    f.is_fraudulent,
    
    f.transaction_datetime
    
FROM fact_transactions f
INNER JOIN dim_time t ON f.time_key = t.time_key
INNER JOIN dim_customer c ON f.customer_key = c.customer_key
INNER JOIN dim_merchant m ON f.merchant_key = m.merchant_key
INNER JOIN dim_geography g ON f.geography_key = g.geography_key
INNER JOIN dim_payment_method pm ON f.payment_method_key = pm.payment_method_key
INNER JOIN dim_product p ON f.product_key = p.product_key
WHERE c.is_current = 1
    AND m.is_current = 1;


-- VIEW: vw_merchant_performance - Merchant KPIs view

CREATE VIEW vw_merchant_performance
AS
SELECT 
    m.merchant_id,
    m.business_name,
    m.industry,
    m.country_name,
    m.merchant_tier,
    
    COUNT(f.transaction_key) AS total_transactions,
    SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS successful_transactions,
    SUM(CASE WHEN f.is_successful = 0 THEN 1 ELSE 0 END) AS failed_transactions,
    
    SUM(f.amount) AS gross_revenue,
    SUM(f.processing_fee) AS total_fees,
    SUM(f.net_amount) AS net_revenue,
    
    AVG(f.amount) AS avg_transaction_value,
    COUNT(DISTINCT f.customer_key) AS unique_customers,
    
    CAST(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(f.transaction_key), 0) * 100 AS success_rate,
    
    CAST(SUM(CASE WHEN f.is_refunded = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END), 0) * 100 AS refund_rate,
    
    CAST(SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(COUNT(f.transaction_key), 0) * 100 AS fraud_rate
    
FROM fact_transactions f
INNER JOIN dim_merchant m ON f.merchant_key = m.merchant_key
WHERE m.is_current = 1
GROUP BY 
    m.merchant_id,
    m.business_name,
    m.industry,
    m.country_name,
    m.merchant_tier;


-- VIEW: vw_geographic_revenue - Revenue by geography

CREATE VIEW vw_geographic_revenue
AS
SELECT 
    g.country_name,
    g.region,
    g.continent,
    g.currency_code,
    
    t.year,
    t.quarter,
    t.month,
    
    COUNT(f.transaction_key) AS transaction_count,
    SUM(f.amount) AS total_revenue,
    AVG(f.amount) AS avg_transaction_value,
    COUNT(DISTINCT f.customer_key) AS unique_customers,
    COUNT(DISTINCT f.merchant_key) AS unique_merchants
    
FROM fact_transactions f
INNER JOIN dim_geography g ON f.geography_key = g.geography_key
INNER JOIN dim_time t ON f.time_key = t.time_key
WHERE f.is_successful = 1
GROUP BY 
    g.country_name,
    g.region,
    g.continent,
    g.currency_code,
    t.year,
    t.quarter,
    t.month;

-- MATERIALIZED VIEWS (for ultra-fast queries)

-- MV: mv_daily_merchant_summary - Daily merchant metrics

CREATE MATERIALIZED VIEW mv_daily_merchant_summary
WITH (DISTRIBUTION = HASH(merchant_key))
AS
SELECT 
    f.merchant_key,
    f.time_key,
    
    COUNT(*) AS transaction_count,
    SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS successful_count,
    SUM(f.amount) AS total_revenue,
    SUM(f.net_amount) AS net_revenue,
    AVG(f.amount) AS avg_transaction_amount,
    COUNT(DISTINCT f.customer_key) AS unique_customers
    
FROM fact_transactions f
WHERE f.is_successful = 1
GROUP BY f.merchant_key, f.time_key;

-- STORED PROCEDURES

-- SP: sp_refresh_daily_aggregates - Refresh daily aggregate table

CREATE PROCEDURE sp_refresh_daily_aggregates
    @date_key INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Delete existing data for the date
    DELETE FROM agg_daily_revenue
    WHERE date_key = @date_key;
    
    -- Insert fresh aggregates
    INSERT INTO agg_daily_revenue (
        date_key,
        merchant_key,
        geography_key,
        payment_method_key,
        transaction_count,
        successful_count,
        failed_count,
        refunded_count,
        total_amount,
        total_fees,
        total_net,
        avg_transaction_amount,
        max_transaction_amount,
        min_transaction_amount,
        unique_customers
    )
    SELECT 
        f.time_key AS date_key,
        f.merchant_key,
        f.geography_key,
        f.payment_method_key,
        
        COUNT(*) AS transaction_count,
        SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END) AS successful_count,
        SUM(CASE WHEN f.is_successful = 0 THEN 1 ELSE 0 END) AS failed_count,
        SUM(CASE WHEN f.is_refunded = 1 THEN 1 ELSE 0 END) AS refunded_count,
        
        SUM(f.amount) AS total_amount,
        SUM(f.processing_fee) AS total_fees,
        SUM(f.net_amount) AS total_net,
        
        AVG(f.amount) AS avg_transaction_amount,
        MAX(f.amount) AS max_transaction_amount,
        MIN(f.amount) AS min_transaction_amount,
        
        COUNT(DISTINCT f.customer_key) AS unique_customers
        
    FROM fact_transactions f
    WHERE f.time_key = @date_key
    GROUP BY 
        f.time_key,
        f.merchant_key,
        f.geography_key,
        f.payment_method_key;
    
    PRINT 'Daily aggregates refreshed for date_key: ' + CAST(@date_key AS VARCHAR(10));
END;

-- SP: sp_calculate_monthly_metrics - Calculate monthly KPIs

CREATE PROCEDURE sp_calculate_monthly_metrics
    @year_month INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @start_date_key INT = @year_month * 100 + 1;
    DECLARE @end_date_key INT = CASE 
        WHEN @year_month % 100 = 12 THEN (@year_month / 100 + 1) * 10000 + 101
        ELSE @year_month * 100 + 101 + 100
    END;
    
    -- Delete existing data for the month
    DELETE FROM agg_monthly_metrics
    WHERE year_month = @year_month;
    
    -- Calculate and insert monthly metrics
    INSERT INTO agg_monthly_metrics (
        year_month,
        merchant_key,
        gross_revenue,
        net_revenue,
        transaction_count,
        unique_customers,
        new_customers,
        returning_customers,
        avg_order_value,
        customer_lifetime_value,
        churn_rate,
        refund_rate,
        chargeback_rate,
        fraud_rate
    )
    SELECT 
        @year_month AS year_month,
        f.merchant_key,
        
        SUM(f.amount) AS gross_revenue,
        SUM(f.net_amount) AS net_revenue,
        COUNT(*) AS transaction_count,
        
        COUNT(DISTINCT f.customer_key) AS unique_customers,
        
        -- New vs returning customers (simplified)
        COUNT(DISTINCT CASE 
            WHEN first_trans.first_date_key >= @start_date_key 
            THEN f.customer_key 
        END) AS new_customers,
        
        COUNT(DISTINCT CASE 
            WHEN first_trans.first_date_key < @start_date_key 
            THEN f.customer_key 
        END) AS returning_customers,
        
        AVG(f.amount) AS avg_order_value,
        
        -- CLV (simplified as total revenue per customer)
        SUM(f.amount) / NULLIF(COUNT(DISTINCT f.customer_key), 0) AS customer_lifetime_value,
        
        -- Rates
        0.00 AS churn_rate, -- To be calculated separately
        
        CAST(SUM(CASE WHEN f.is_refunded = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END), 0) * 100 AS refund_rate,
        
        CAST(SUM(CASE WHEN f.is_disputed = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN f.is_successful = 1 THEN 1 ELSE 0 END), 0) * 100 AS chargeback_rate,
        
        CAST(SUM(CASE WHEN f.is_fraudulent = 1 THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(COUNT(*), 0) * 100 AS fraud_rate
        
    FROM fact_transactions f
    LEFT JOIN (
        SELECT 
            customer_key,
            MIN(time_key) AS first_date_key
        FROM fact_transactions
        GROUP BY customer_key
    ) first_trans ON f.customer_key = first_trans.customer_key
    
    WHERE f.time_key >= @start_date_key
        AND f.time_key < @end_date_key
        AND f.is_successful = 1
    
    GROUP BY f.merchant_key;
    
    PRINT 'Monthly metrics calculated for year_month: ' + CAST(@year_month AS VARCHAR(6));
END;

-- SP: sp_load_dim_time - Pre-load time dimension

CREATE PROCEDURE sp_load_dim_time
    @start_year INT = 2020,
    @end_year INT = 2035
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @start_date DATE = CAST(CAST(@start_year AS VARCHAR(4)) + '-01-01' AS DATE);
    DECLARE @end_date DATE = CAST(CAST(@end_year AS VARCHAR(4)) + '-12-31' AS DATE);
    DECLARE @current_date DATE = @start_date;
    
    WHILE @current_date <= @end_date
    BEGIN
        INSERT INTO dim_time (
            time_key,
            full_date,
            year,
            quarter,
            month,
            month_name,
            week_of_year,
            day_of_month,
            day_of_week,
            day_name,
            is_weekend,
            is_holiday,
            fiscal_year,
            fiscal_quarter,
            fiscal_period
        )
        VALUES (
            CAST(FORMAT(@current_date, 'yyyyMMdd') AS INT),
            @current_date,
            YEAR(@current_date),
            DATEPART(QUARTER, @current_date),
            MONTH(@current_date),
            DATENAME(MONTH, @current_date),
            DATEPART(WEEK, @current_date),
            DAY(@current_date),
            DATEPART(WEEKDAY, @current_date),
            DATENAME(WEEKDAY, @current_date),
            CASE WHEN DATEPART(WEEKDAY, @current_date) IN (1, 7) THEN 1 ELSE 0 END,
            0, -- Holiday flag (to be updated separately)
            YEAR(@current_date), -- Simplified: fiscal = calendar year
            DATEPART(QUARTER, @current_date),
            MONTH(@current_date)
        );
        
        SET @current_date = DATEADD(DAY, 1, @current_date);
    END;
    
    PRINT 'Time dimension loaded from ' + CAST(@start_year AS VARCHAR(4)) + 
          ' to ' + CAST(@end_year AS VARCHAR(4));
END;

-- SAMPLE DATA (for demonstration)

-- Note: In production, data would come from ETL pipeline
-- This is minimal sample data for testing

-- Sample Geography data
INSERT INTO dim_geography VALUES
(1, 'FR', 'France', 'Europe', 'Western Europe', 'Europe', 'EUR', 'Euro', 'UTC+1', 45000.00, 67000000, 92.00, 1, 0),
(2, 'US', 'United States', 'Americas', 'Northern America', 'North America', 'USD', 'US Dollar', 'UTC-5', 70000.00, 331000000, 90.00, 0, 0),
(3, 'GB', 'United Kingdom', 'Europe', 'Northern Europe', 'Europe', 'GBP', 'Pound Sterling', 'UTC+0', 46000.00, 67000000, 95.00, 1, 0);

-- Sample Product data
INSERT INTO dim_product VALUES
(1, 'PAY-001', 'Standard Payment', 'Payment', 'Core', 'Percentage', 0.00, 0.0290, 1),
(2, 'SUB-001', 'Subscription Payment', 'Subscription', 'Premium', 'Percentage', 0.00, 0.0250, 1);

-- STATISTICS (for query optimization)

CREATE STATISTICS stat_fact_transactions_merchant ON fact_transactions(merchant_key);
CREATE STATISTICS stat_fact_transactions_customer ON fact_transactions(customer_key);
CREATE STATISTICS stat_fact_transactions_time ON fact_transactions(time_key);
CREATE STATISTICS stat_fact_transactions_geography ON fact_transactions(geography_key);

-- END OF SCHEMA CREATION

PRINT 'Stripe OLAP Data Warehouse schema created successfully!';
PRINT 'Tables: 9 (6 dimensions + 1 fact + 2 aggregates)';
PRINT 'Views: 3';
PRINT 'Materialized Views: 1';
PRINT 'Stored Procedures: 3';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Execute: EXEC sp_load_dim_time @start_year=2020, @end_year=2035';
PRINT '2. Load dimension data via ETL pipeline';
PRINT '3. Load fact data from OLTP source';
PRINT '4. Execute: EXEC sp_refresh_daily_aggregates @date_key=20251016';

