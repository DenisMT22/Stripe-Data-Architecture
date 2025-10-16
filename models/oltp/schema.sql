-- STRIPE OLTP DATABASE - SCHEMA CREATION

-- Database: Stripe Transactional System
-- Azure SQL Database - Business Critical Tier

-- 1. TABLE: CUSTOMERS

-- Description: End customers making payments

CREATE TABLE customers (
    customer_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    email NVARCHAR(255) NOT NULL,
    first_name NVARCHAR(100) NOT NULL,
    last_name NVARCHAR(100) NOT NULL,
    phone NVARCHAR(20) NULL,
    country_code CHAR(2) NOT NULL,
    is_verified BIT NOT NULL DEFAULT 0,
    risk_score DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    is_deleted BIT NOT NULL DEFAULT 0,

    CONSTRAINT UQ_customers_email UNIQUE (email),
    CONSTRAINT CHK_customers_risk_score CHECK (risk_score BETWEEN 0 AND 100),
    CONSTRAINT CHK_customers_country_code CHECK (LEN(country_code) = 2)
);

CREATE INDEX IX_customers_country_code ON customers(country_code);
CREATE INDEX IX_customers_risk_score ON customers(risk_score) WHERE is_deleted = 0;

-- 2. TABLE: MERCHANTS

-- Description: Businesses accepting payments through Stripe

CREATE TABLE merchants (
    merchant_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    business_name NVARCHAR(255) NOT NULL,
    legal_name NVARCHAR(255) NOT NULL,
    email NVARCHAR(255) NOT NULL,
    phone NVARCHAR(20) NOT NULL,
    country_code CHAR(2) NOT NULL,
    industry NVARCHAR(100) NOT NULL,
    mcc_code CHAR(4) NOT NULL,
    is_active BIT NOT NULL DEFAULT 1,
    kyc_status NVARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    is_deleted BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT UQ_merchants_email UNIQUE (email),
    CONSTRAINT CHK_merchants_kyc_status CHECK (kyc_status IN ('PENDING', 'VERIFIED', 'REJECTED')),
    CONSTRAINT CHK_merchants_mcc_code CHECK (LEN(mcc_code) = 4)
);

CREATE INDEX IX_merchants_country_code ON merchants(country_code);
CREATE INDEX IX_merchants_is_active ON merchants(is_active) WHERE is_deleted = 0;
CREATE INDEX IX_merchants_kyc_status ON merchants(kyc_status);

-- 3. TABLE: PAYMENT_METHODS

-- Description: Payment methods registered by customers (PCI-DSS compliant)

CREATE TABLE payment_methods (
    payment_method_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    type NVARCHAR(20) NOT NULL,
    card_brand NVARCHAR(20) NULL,
    last4 CHAR(4) NULL,
    exp_month TINYINT NULL,
    exp_year SMALLINT NULL,
    token NVARCHAR(255) NOT NULL, -- Tokenized, never actual card number
    is_default BIT NOT NULL DEFAULT 0,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    is_deleted BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT FK_payment_methods_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id),
    CONSTRAINT UQ_payment_methods_token UNIQUE (token),
    CONSTRAINT CHK_payment_methods_type CHECK (type IN ('CARD', 'SEPA', 'WALLET')),
    CONSTRAINT CHK_payment_methods_last4 CHECK (last4 IS NULL OR LEN(last4) = 4),
    CONSTRAINT CHK_payment_methods_exp_month CHECK (exp_month IS NULL OR exp_month BETWEEN 1 AND 12)
);

CREATE INDEX IX_payment_methods_customer_id ON payment_methods(customer_id);
CREATE INDEX IX_payment_methods_is_active ON payment_methods(is_active) WHERE is_deleted = 0;

-- 4. TABLE: TRANSACTIONS

-- Description: Core table - all payment transactions

CREATE TABLE transactions (
    transaction_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    merchant_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    payment_method_id BIGINT NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status NVARCHAR(20) NOT NULL,
    payment_intent_id NVARCHAR(100) NOT NULL,
    description NVARCHAR(500) NULL,
    ip_address NVARCHAR(45) NULL,
    user_agent NVARCHAR(500) NULL,
    device_type NVARCHAR(20) NULL,
    country_code CHAR(2) NULL,
    failure_code NVARCHAR(50) NULL,
    failure_message NVARCHAR(500) NULL,
    processing_fee DECIMAL(18,2) NULL,
    net_amount DECIMAL(18,2) NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    is_deleted BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT FK_transactions_merchant FOREIGN KEY (merchant_id) 
        REFERENCES merchants(merchant_id),
    CONSTRAINT FK_transactions_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id),
    CONSTRAINT FK_transactions_payment_method FOREIGN KEY (payment_method_id) 
        REFERENCES payment_methods(payment_method_id),
    CONSTRAINT UQ_transactions_payment_intent_id UNIQUE (payment_intent_id),
    CONSTRAINT CHK_transactions_status CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'REFUNDED')),
    CONSTRAINT CHK_transactions_amount CHECK (amount > 0),
    CONSTRAINT CHK_transactions_currency CHECK (LEN(currency) = 3)
);

-- Critical indexes for performance

CREATE INDEX IX_transactions_merchant_date_status 
    ON transactions(merchant_id, created_at, status) WHERE is_deleted = 0;
CREATE INDEX IX_transactions_customer_date 
    ON transactions(customer_id, created_at) WHERE is_deleted = 0;
CREATE INDEX IX_transactions_status_date 
    ON transactions(status, created_at) WHERE is_deleted = 0;

-- 5. TABLE: REFUNDS

-- Description: Partial or full transaction refunds

CREATE TABLE refunds (
    refund_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    transaction_id BIGINT NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    reason NVARCHAR(50) NOT NULL,
    status NVARCHAR(20) NOT NULL,
    description NVARCHAR(500) NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    processed_at DATETIME2 NULL,
    is_deleted BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT FK_refunds_transaction FOREIGN KEY (transaction_id) 
        REFERENCES transactions(transaction_id),
    CONSTRAINT CHK_refunds_reason CHECK (reason IN ('REQUESTED_BY_CUSTOMER', 'FRAUDULENT', 'DUPLICATE')),
    CONSTRAINT CHK_refunds_status CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED')),
    CONSTRAINT CHK_refunds_amount CHECK (amount > 0)
);

CREATE INDEX IX_refunds_transaction_id ON refunds(transaction_id);
CREATE INDEX IX_refunds_status ON refunds(status);

-- 6. TABLE: CHARGEBACKS

-- Description: Payment disputes initiated by customer's bank

CREATE TABLE chargebacks (
    chargeback_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    transaction_id BIGINT NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    reason_code NVARCHAR(20) NOT NULL,
    reason_description NVARCHAR(500) NOT NULL,
    status NVARCHAR(20) NOT NULL,
    evidence_due_date DATETIME2 NULL,
    resolved_at DATETIME2 NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    is_deleted BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT FK_chargebacks_transaction FOREIGN KEY (transaction_id) 
        REFERENCES transactions(transaction_id),
    CONSTRAINT CHK_chargebacks_status CHECK (status IN ('OPEN', 'WON', 'LOST')),
    CONSTRAINT CHK_chargebacks_amount CHECK (amount > 0)
);

CREATE INDEX IX_chargebacks_transaction_id ON chargebacks(transaction_id);
CREATE INDEX IX_chargebacks_status ON chargebacks(status);

-- 7. TABLE: FRAUD_CHECKS

-- Description: Fraud analysis for each transaction (1:1 relationship)

CREATE TABLE fraud_checks (
    fraud_check_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    transaction_id BIGINT NOT NULL,
    risk_score DECIMAL(5,2) NOT NULL,
    risk_level NVARCHAR(20) NOT NULL,
    is_flagged BIT NOT NULL DEFAULT 0,
    ml_model_version NVARCHAR(50) NOT NULL,
    factors NVARCHAR(MAX) NULL, -- JSON format
    action_taken NVARCHAR(20) NULL,
    reviewed_by NVARCHAR(100) NULL,
    reviewed_at DATETIME2 NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT FK_fraud_checks_transaction FOREIGN KEY (transaction_id) 
        REFERENCES transactions(transaction_id),
    CONSTRAINT UQ_fraud_checks_transaction UNIQUE (transaction_id),
    CONSTRAINT CHK_fraud_checks_risk_score CHECK (risk_score BETWEEN 0 AND 100),
    CONSTRAINT CHK_fraud_checks_risk_level CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    CONSTRAINT CHK_fraud_checks_action CHECK (action_taken IS NULL OR action_taken IN ('APPROVED', 'BLOCKED', 'REVIEW'))
);

CREATE INDEX IX_fraud_checks_risk_level ON fraud_checks(risk_level);
CREATE INDEX IX_fraud_checks_is_flagged ON fraud_checks(is_flagged) WHERE is_flagged = 1;

-- 8. TABLE: SUBSCRIPTIONS

-- Description: Recurring payment subscriptions

CREATE TABLE subscriptions (
    subscription_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    merchant_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    payment_method_id BIGINT NOT NULL,
    plan_name NVARCHAR(100) NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    interval NVARCHAR(20) NOT NULL,
    interval_count INT NOT NULL DEFAULT 1,
    status NVARCHAR(20) NOT NULL,
    current_period_start DATETIME2 NOT NULL,
    current_period_end DATETIME2 NOT NULL,
    cancel_at_period_end BIT NOT NULL DEFAULT 0,
    canceled_at DATETIME2 NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    is_deleted BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT FK_subscriptions_merchant FOREIGN KEY (merchant_id) 
        REFERENCES merchants(merchant_id),
    CONSTRAINT FK_subscriptions_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id),
    CONSTRAINT FK_subscriptions_payment_method FOREIGN KEY (payment_method_id) 
        REFERENCES payment_methods(payment_method_id),
    CONSTRAINT CHK_subscriptions_status CHECK (status IN ('ACTIVE', 'PAUSED', 'CANCELED')),
    CONSTRAINT CHK_subscriptions_interval CHECK (interval IN ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY')),
    CONSTRAINT CHK_subscriptions_amount CHECK (amount > 0),
    CONSTRAINT CHK_subscriptions_interval_count CHECK (interval_count > 0)
);

CREATE INDEX IX_subscriptions_merchant_id ON subscriptions(merchant_id);
CREATE INDEX IX_subscriptions_customer_id ON subscriptions(customer_id);
CREATE INDEX IX_subscriptions_status ON subscriptions(status) WHERE is_deleted = 0;
CREATE INDEX IX_subscriptions_period_end ON subscriptions(current_period_end) WHERE status = 'ACTIVE';

-- 9. TABLE: SUBSCRIPTION_PAYMENTS

-- Description: History of recurring subscription payments

CREATE TABLE subscription_payments (
    subscription_payment_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    subscription_id BIGINT NOT NULL,
    transaction_id BIGINT NULL,
    amount DECIMAL(18,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status NVARCHAR(20) NOT NULL,
    attempt_count INT NOT NULL DEFAULT 1,
    next_retry_at DATETIME2 NULL,
    failure_reason NVARCHAR(500) NULL,
    period_start DATETIME2 NOT NULL,
    period_end DATETIME2 NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    processed_at DATETIME2 NULL,
    
    CONSTRAINT FK_subscription_payments_subscription FOREIGN KEY (subscription_id) 
        REFERENCES subscriptions(subscription_id),
    CONSTRAINT FK_subscription_payments_transaction FOREIGN KEY (transaction_id) 
        REFERENCES transactions(transaction_id),
    CONSTRAINT CHK_subscription_payments_status CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED')),
    CONSTRAINT CHK_subscription_payments_amount CHECK (amount > 0),
    CONSTRAINT CHK_subscription_payments_attempt_count CHECK (attempt_count > 0)
);

CREATE INDEX IX_subscription_payments_subscription_id ON subscription_payments(subscription_id);
CREATE INDEX IX_subscription_payments_status ON subscription_payments(status);
CREATE INDEX IX_subscription_payments_next_retry ON subscription_payments(next_retry_at) 
    WHERE status = 'FAILED' AND next_retry_at IS NOT NULL;

-- TRIGGERS FOR UPDATED_AT COLUMNS

-- Trigger for customers

GO
CREATE TRIGGER TR_customers_updated_at
ON customers
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE customers
    SET updated_at = GETUTCDATE()
    FROM customers c
    INNER JOIN inserted i ON c.customer_id = i.customer_id;
END;
GO

-- Trigger for merchants

CREATE TRIGGER TR_merchants_updated_at
ON merchants
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE merchants
    SET updated_at = GETUTCDATE()
    FROM merchants m
    INNER JOIN inserted i ON m.merchant_id = i.merchant_id;
END;
GO

-- Trigger for payment_methods

CREATE TRIGGER TR_payment_methods_updated_at
ON payment_methods
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE payment_methods
    SET updated_at = GETUTCDATE()
    FROM payment_methods pm
    INNER JOIN inserted i ON pm.payment_method_id = i.payment_method_id;
END;
GO

-- Trigger for transactions

CREATE TRIGGER TR_transactions_updated_at
ON transactions
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE transactions
    SET updated_at = GETUTCDATE()
    FROM transactions t
    INNER JOIN inserted i ON t.transaction_id = i.transaction_id;
END;
GO

-- Trigger for subscriptions

CREATE TRIGGER TR_subscriptions_updated_at
ON subscriptions
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE subscriptions
    SET updated_at = GETUTCDATE()
    FROM subscriptions s
    INNER JOIN inserted i ON s.subscription_id = i.subscription_id;
END;
GO

-- VIEWS FOR COMMON QUERIES

-- View: Active transactions with customer and merchant info

CREATE VIEW vw_active_transactions AS
SELECT 
    t.transaction_id,
    t.payment_intent_id,
    t.amount,
    t.currency,
    t.status,
    t.created_at,
    c.customer_id,
    c.email AS customer_email,
    c.first_name + ' ' + c.last_name AS customer_name,
    m.merchant_id,
    m.business_name AS merchant_name,
    m.country_code AS merchant_country,
    pm.type AS payment_type,
    pm.card_brand,
    pm.last4,
    fc.risk_level,
    fc.risk_score
FROM transactions t
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
INNER JOIN payment_methods pm ON t.payment_method_id = pm.payment_method_id
LEFT JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE t.is_deleted = 0;
GO

-- View: Merchant revenue summary

CREATE VIEW vw_merchant_revenue AS
SELECT 
    m.merchant_id,
    m.business_name,
    m.country_code,
    COUNT(t.transaction_id) AS total_transactions,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.amount ELSE 0 END) AS total_revenue,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.processing_fee ELSE 0 END) AS total_fees,
    SUM(CASE WHEN t.status = 'SUCCEEDED' THEN t.net_amount ELSE 0 END) AS total_net,
    SUM(CASE WHEN t.status = 'REFUNDED' THEN 1 ELSE 0 END) AS refund_count,
    SUM(CASE WHEN t.status = 'FAILED' THEN 1 ELSE 0 END) AS failed_count
FROM merchants m
LEFT JOIN transactions t ON m.merchant_id = t.merchant_id AND t.is_deleted = 0
WHERE m.is_deleted = 0
GROUP BY m.merchant_id, m.business_name, m.country_code;
GO

-- View: High risk transactions

CREATE VIEW vw_high_risk_transactions AS
SELECT 
    t.transaction_id,
    t.payment_intent_id,
    t.amount,
    t.currency,
    t.status,
    t.created_at,
    c.email AS customer_email,
    m.business_name AS merchant_name,
    fc.risk_score,
    fc.risk_level,
    fc.is_flagged,
    fc.action_taken
FROM transactions t
INNER JOIN customers c ON t.customer_id = c.customer_id
INNER JOIN merchants m ON t.merchant_id = m.merchant_id
INNER JOIN fraud_checks fc ON t.transaction_id = fc.transaction_id
WHERE fc.risk_level IN ('HIGH', 'CRITICAL')
    AND t.is_deleted = 0
    AND fc.is_flagged = 1;
GO

-- STORED PROCEDURES

-- Procedure: Get customer transaction history

CREATE PROCEDURE sp_get_customer_transactions
    @customer_id BIGINT,
    @start_date DATETIME2 = NULL,
    @end_date DATETIME2 = NULL,
    @status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        t.transaction_id,
        t.payment_intent_id,
        t.amount,
        t.currency,
        t.status,
        t.created_at,
        m.business_name AS merchant_name,
        pm.type AS payment_type,
        pm.last4
    FROM transactions t
    INNER JOIN merchants m ON t.merchant_id = m.merchant_id
    INNER JOIN payment_methods pm ON t.payment_method_id = pm.payment_method_id
    WHERE t.customer_id = @customer_id
        AND t.is_deleted = 0
        AND (@start_date IS NULL OR t.created_at >= @start_date)
        AND (@end_date IS NULL OR t.created_at <= @end_date)
        AND (@status IS NULL OR t.status = @status)
    ORDER BY t.created_at DESC;
END;
GO

-- Procedure: Calculate merchant metrics

CREATE PROCEDURE sp_calculate_merchant_metrics
    @merchant_id BIGINT,
    @start_date DATETIME2,
    @end_date DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        @merchant_id AS merchant_id,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS successful_transactions,
        SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) AS failed_transactions,
        SUM(CASE WHEN status = 'REFUNDED' THEN 1 ELSE 0 END) AS refunded_transactions,
        SUM(CASE WHEN status = 'SUCCEEDED' THEN amount ELSE 0 END) AS total_revenue,
        AVG(CASE WHEN status = 'SUCCEEDED' THEN amount ELSE NULL END) AS average_transaction_value,
        SUM(CASE WHEN status = 'SUCCEEDED' THEN processing_fee ELSE 0 END) AS total_processing_fees,
        SUM(CASE WHEN status = 'SUCCEEDED' THEN net_amount ELSE 0 END) AS total_net_revenue,
        CAST(SUM(CASE WHEN status = 'SUCCEEDED' THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(COUNT(*), 0) * 100 AS success_rate
    FROM transactions
    WHERE merchant_id = @merchant_id
        AND created_at BETWEEN @start_date AND @end_date
        AND is_deleted = 0;
END;
GO

-- SAMPLE DATA (FOR TESTING)

-- Insert sample customers

INSERT INTO customers (email, first_name, last_name, phone, country_code, is_verified, risk_score)
VALUES 
    ('john.doe@example.com', 'John', 'Doe', '+33612345678', 'FR', 1, 15.50),
    ('jane.smith@example.com', 'Jane', 'Smith', '+447700900123', 'GB', 1, 8.20),
    ('bob.martin@example.com', 'Bob', 'Martin', '+12125551234', 'US', 1, 22.75);

-- Insert sample merchants
INSERT INTO merchants (business_name, legal_name, email, phone, country_code, industry, mcc_code, is_active, kyc_status)
VALUES 
    ('TechShop Paris', 'TechShop SAS', 'contact@techshop.fr', '+33140123456', 'FR', 'Electronics', '5732', 1, 'VERIFIED'),
    ('Fashion Store', 'Fashion Store Ltd', 'info@fashionstore.co.uk', '+442071234567', 'GB', 'Clothing', '5651', 1, 'VERIFIED'),
    ('Food Delivery Inc', 'Food Delivery Corp', 'support@fooddelivery.com', '+14155551234', 'US', 'Food & Beverage', '5812', 1, 'VERIFIED');

-- Insert sample payment methods
INSERT INTO payment_methods (customer_id, type, card_brand, last4, exp_month, exp_year, token, is_default, is_active)
VALUES 
    (1, 'CARD', 'VISA', '4242', 12, 2027, 'tok_visa_4242_' + CONVERT(VARCHAR(36), NEWID()), 1, 1),
    (2, 'CARD', 'MASTERCARD', '5555', 6, 2026, 'tok_mc_5555_' + CONVERT(VARCHAR(36), NEWID()), 1, 1),
    (3, 'CARD', 'AMEX', '0005', 9, 2028, 'tok_amex_0005_' + CONVERT(VARCHAR(36), NEWID()), 1, 1);

-- END OF SCHEMA CREATION

PRINT 'Stripe OLTP database schema created successfully!';
PRINT 'Tables: 9';
PRINT 'Views: 3';
PRINT 'Stored Procedures: 2';
PRINT 'Triggers: 5';

