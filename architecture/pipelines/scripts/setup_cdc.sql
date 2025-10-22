-- Change Data Capture (CDC) Setup Script

-- Azure SQL Database - Stripe OLTP

-- Purpose: Enable CDC on critical tables for ETL to OLAP

-- Execution: sqlcmd -S <server>.database.windows.net -d stripe_oltp_db -i setup_cdc.sql

USE stripe_oltp_db;
GO

-- STEP 1: Enable CDC on Database

PRINT 'Step 1: Enabling CDC on database...';
GO

-- Check if CDC is already enabled
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'stripe_oltp_db' AND is_cdc_enabled = 1)
BEGIN
    EXEC sys.sp_cdc_enable_db;
    PRINT 'CDC enabled on database stripe_oltp_db';
END
ELSE
BEGIN
    PRINT 'CDC already enabled on database';
END
GO

-- STEP 2: Enable CDC on Individual Tables

PRINT 'Step 2: Enabling CDC on tables...';
GO

-- Table 1: Payment (CRITICAL - Most important for OLAP)
-- ---------------------------------------------------------------
PRINT 'Enabling CDC on Payment table...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t 
               JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id 
               WHERE t.name = 'Payment')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Payment',
        @role_name = NULL,                    -- No role restriction
        @supports_net_changes = 1,            -- Enable net changes query
        @captured_column_list = N'PaymentID, CustomerID, MerchantID, Amount, Currency, Status, PaymentMethod, CreatedAt, UpdatedAt';  -- Capture specific columns
    
    PRINT '✓ CDC enabled on Payment table';
END
ELSE
BEGIN
    PRINT '✓ CDC already enabled on Payment table';
END
GO

-- Table 2: Customer
-- ---------------------------------------------------------------
PRINT 'Enabling CDC on Customer table...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t 
               JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id 
               WHERE t.name = 'Customer')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Customer',
        @role_name = NULL,
        @supports_net_changes = 1,
        @captured_column_list = N'CustomerID, Email, Country, IsActive, CreatedAt, UpdatedAt';
    
    PRINT '✓ CDC enabled on Customer table';
END
ELSE
BEGIN
    PRINT '✓ CDC already enabled on Customer table';
END
GO

-- Table 3: Merchant
-- ---------------------------------------------------------------
PRINT 'Enabling CDC on Merchant table...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t 
               JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id 
               WHERE t.name = 'Merchant')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Merchant',
        @role_name = NULL,
        @supports_net_changes = 1,
        @captured_column_list = N'MerchantID, BusinessName, Country, Industry, IsActive, CreatedAt, UpdatedAt';
    
    PRINT '✓ CDC enabled on Merchant table';
END
ELSE
BEGIN
    PRINT '✓ CDC already enabled on Merchant table';
END
GO

-- Table 4: Subscription
-- ---------------------------------------------------------------
PRINT 'Enabling CDC on Subscription table...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t 
               JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id 
               WHERE t.name = 'Subscription')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Subscription',
        @role_name = NULL,
        @supports_net_changes = 1,
        @captured_column_list = N'SubscriptionID, CustomerID, PlanID, Status, StartDate, EndDate, CreatedAt, UpdatedAt';
    
    PRINT '✓ CDC enabled on Subscription table';
END
ELSE
BEGIN
    PRINT '✓ CDC already enabled on Subscription table';
END
GO

-- Table 5: Dispute
-- ---------------------------------------------------------------
PRINT 'Enabling CDC on Dispute table...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t 
               JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id 
               WHERE t.name = 'Dispute')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Dispute',
        @role_name = NULL,
        @supports_net_changes = 1,
        @captured_column_list = N'DisputeID, PaymentID, Reason, Status, Amount, CreatedAt, ResolvedAt';
    
    PRINT '✓ CDC enabled on Dispute table';
END
ELSE
BEGIN
    PRINT '✓ CDC already enabled on Dispute table';
END
GO

-- Table 6: Refund
-- ---------------------------------------------------------------
PRINT 'Enabling CDC on Refund table...';
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t 
               JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id 
               WHERE t.name = 'Refund')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Refund',
        @role_name = NULL,
        @supports_net_changes = 1,
        @captured_column_list = N'RefundID, PaymentID, Amount, Reason, Status, CreatedAt';
    
    PRINT '✓ CDC enabled on Refund table';
END
ELSE
BEGIN
    PRINT '✓ CDC already enabled on Refund table';
END
GO

-- STEP 3: Configure CDC Retention and Cleanup

PRINT 'Step 3: Configuring CDC retention policies...';
GO

-- Set retention to 3 days (4320 minutes)
-- After 3 days, CDC changes are automatically cleaned up
EXEC sys.sp_cdc_change_job
    @job_type = N'cleanup',
    @retention = 4320;  -- 3 days in minutes
GO

-- Set capture job to run every 5 seconds
EXEC sys.sp_cdc_change_job
    @job_type = N'capture',
    @pollinginterval = 5;  -- seconds
GO

PRINT '✓ CDC retention set to 3 days';
PRINT '✓ CDC capture interval set to 5 seconds';
GO

-- STEP 4: Verify CDC Setup

PRINT 'Step 4: Verifying CDC setup...';
GO

PRINT '----------------------------------------';
PRINT 'CDC-Enabled Tables:';
PRINT '----------------------------------------';

SELECT 
    t.name AS TableName,
    ct.capture_instance AS CaptureInstance,
    ct.create_date AS EnabledDate,
    ct.start_lsn AS StartLSN,
    ct.supports_net_changes AS SupportsNetChanges
FROM sys.tables t
INNER JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id
ORDER BY t.name;
GO

PRINT '----------------------------------------';
PRINT 'CDC Jobs Status:';
PRINT '----------------------------------------';

SELECT 
    job.name AS JobName,
    job.enabled AS IsEnabled,
    CASE 
        WHEN job.name LIKE '%capture%' THEN 'Captures changes from transaction log'
        WHEN job.name LIKE '%cleanup%' THEN 'Cleans up old CDC data'
    END AS Description
FROM msdb.dbo.sysjobs job
WHERE job.name LIKE 'cdc%'
ORDER BY job.name;
GO

-- STEP 5: Create Helper Views for ETL

PRINT 'Step 5: Creating helper views for ETL...';
GO

-- View: Get all changes since last ETL run
CREATE OR ALTER VIEW dbo.vw_CDC_Payment_Changes
AS
SELECT 
    __$start_lsn AS StartLSN,
    __$seqval AS SeqVal,
    __$operation AS Operation,  -- 1=DELETE, 2=INSERT, 3=UPDATE(before), 4=UPDATE(after)
    __$update_mask AS UpdateMask,
    PaymentID,
    CustomerID,
    MerchantID,
    Amount,
    Currency,
    Status,
    PaymentMethod,
    CreatedAt,
    UpdatedAt
FROM cdc.dbo_Payment_CT;
GO

PRINT '✓ Created view vw_CDC_Payment_Changes';
GO

-- View: Get net changes (simplified for ETL)
CREATE OR ALTER VIEW dbo.vw_CDC_Payment_Net_Changes
AS
SELECT 
    PaymentID,
    CustomerID,
    MerchantID,
    Amount,
    Currency,
    Status,
    PaymentMethod,
    CreatedAt,
    UpdatedAt,
    CASE 
        WHEN __$operation IN (1) THEN 'DELETE'
        WHEN __$operation IN (2) THEN 'INSERT'
        WHEN __$operation IN (3, 4) THEN 'UPDATE'
    END AS ChangeType
FROM cdc.fn_cdc_get_net_changes_dbo_Payment(
    sys.fn_cdc_get_min_lsn('dbo_Payment'),
    sys.fn_cdc_get_max_lsn(),
    'all'
);
GO

PRINT '✓ Created view vw_CDC_Payment_Net_Changes';
GO

-- STEP 6: Create Stored Procedure for ETL

PRINT 'Step 6: Creating stored procedure for ETL...';
GO

CREATE OR ALTER PROCEDURE dbo.sp_Get_CDC_Changes
    @TableName NVARCHAR(128),
    @FromLSN BINARY(10) = NULL,  -- NULL = get from beginning
    @ToLSN BINARY(10) = NULL     -- NULL = get to current
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @FunctionName NVARCHAR(256);
    DECLARE @MinLSN BINARY(10);
    DECLARE @MaxLSN BINARY(10);
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Get LSN range
    SET @MinLSN = ISNULL(@FromLSN, sys.fn_cdc_get_min_lsn('dbo_' + @TableName));
    SET @MaxLSN = ISNULL(@ToLSN, sys.fn_cdc_get_max_lsn());
    
    -- Build dynamic SQL
    SET @FunctionName = 'cdc.fn_cdc_get_net_changes_dbo_' + @TableName;
    SET @SQL = '
        SELECT * 
        FROM ' + @FunctionName + '(@MinLSN, @MaxLSN, ''all'')
    ';
    
    -- Execute
    EXEC sp_executesql @SQL, 
        N'@MinLSN BINARY(10), @MaxLSN BINARY(10)', 
        @MinLSN, 
        @MaxLSN;
END;
GO

PRINT '✓ Created stored procedure sp_Get_CDC_Changes';
GO

-- STEP 7: Create Metadata Table for ETL Tracking

PRINT 'Step 7: Creating metadata table for ETL tracking...';
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ETL_CDC_Watermark')
BEGIN
    CREATE TABLE dbo.ETL_CDC_Watermark (
        TableName NVARCHAR(128) PRIMARY KEY,
        LastProcessedLSN BINARY(10),
        LastProcessedTime DATETIME2(7),
        RowsProcessed BIGINT,
        CreatedAt DATETIME2(7) DEFAULT SYSDATETIME(),
        UpdatedAt DATETIME2(7) DEFAULT SYSDATETIME()
    );
    
    -- Initialize with current LSN for each CDC-enabled table
    INSERT INTO dbo.ETL_CDC_Watermark (TableName, LastProcessedLSN, LastProcessedTime, RowsProcessed)
    VALUES 
        ('Payment', sys.fn_cdc_get_max_lsn(), SYSDATETIME(), 0),
        ('Customer', sys.fn_cdc_get_max_lsn(), SYSDATETIME(), 0),
        ('Merchant', sys.fn_cdc_get_max_lsn(), SYSDATETIME(), 0),
        ('Subscription', sys.fn_cdc_get_max_lsn(), SYSDATETIME(), 0),
        ('Dispute', sys.fn_cdc_get_max_lsn(), SYSDATETIME(), 0),
        ('Refund', sys.fn_cdc_get_max_lsn(), SYSDATETIME(), 0);
    
    PRINT '✓ Created ETL_CDC_Watermark table';
END
ELSE
BEGIN
    PRINT '✓ ETL_CDC_Watermark table already exists';
END
GO

-- STEP 8: Grant Permissions for ADF Managed Identity

PRINT 'Step 8: Granting permissions...';
GO

-- Create user for Azure Data Factory managed identity
-- Note: This requires the managed identity principal ID
-- Example: CREATE USER [stripe-data-prod-adf] FROM EXTERNAL PROVIDER;

-- Grant read access to CDC tables
PRINT 'Grant SELECT on CDC schema to ADF (manual step required)';
PRINT 'Execute: GRANT SELECT ON SCHEMA::cdc TO [your-adf-managed-identity];';
GO

-- FINAL SUMMARY

PRINT '';
PRINT '========================================';
PRINT 'CDC Setup Complete!';
PRINT '========================================';
PRINT '';
PRINT 'Summary:';
PRINT '- CDC enabled on 6 tables';
PRINT '- Retention: 3 days';
PRINT '- Capture interval: 5 seconds';
PRINT '- Helper views created';
PRINT '- ETL stored procedure created';
PRINT '- Watermark table initialized';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Verify CDC jobs are running:';
PRINT '   SELECT * FROM msdb.dbo.sysjobs WHERE name LIKE ''cdc%''';
PRINT '';
PRINT '2. Test CDC capture:';
PRINT '   INSERT INTO Payment (CustomerID, MerchantID, Amount, Currency, Status, PaymentMethod)';
PRINT '   VALUES (1, 1, 1000, ''USD'', ''succeeded'', ''card'');';
PRINT '   SELECT * FROM cdc.dbo_Payment_CT;';
PRINT '';
PRINT '3. Configure ADF managed identity permissions:';
PRINT '   CREATE USER [stripe-data-prod-adf] FROM EXTERNAL PROVIDER;';
PRINT '   GRANT SELECT ON SCHEMA::cdc TO [stripe-data-prod-adf];';
PRINT '   GRANT SELECT ON dbo.ETL_CDC_Watermark TO [stripe-data-prod-adf];';
PRINT '   GRANT UPDATE ON dbo.ETL_CDC_Watermark TO [stripe-data-prod-adf];';
PRINT '';
PRINT '4. Run initial ETL pipeline in Azure Data Factory';
PRINT '';
PRINT '========================================';
GO