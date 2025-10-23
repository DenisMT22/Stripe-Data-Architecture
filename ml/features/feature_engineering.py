"""
Feature Engineering Pipeline for Fraud Detection
Stripe Data Architecture - ML Module

Purpose: Compute 45 features from raw transaction data
Latency Target: < 50ms for real-time scoring
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import logging
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential
import pyodbc

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FeatureEngineer:
    """
    Feature engineering for fraud detection.
    Computes 45 features across 7 categories.
    """
    
    def __init__(self, sql_connection_string: str, cosmos_endpoint: str):
        """
        Initialize feature engineer with database connections.
        
        Args:
            sql_connection_string: Azure SQL connection string
            cosmos_endpoint: Cosmos DB endpoint URL
        """
        self.sql_conn = pyodbc.connect(sql_connection_string)
        self.cosmos_client = CosmosClient(
            cosmos_endpoint, 
            credential=DefaultAzureCredential()
        )
        self.cosmos_db = self.cosmos_client.get_database_client("stripe_nosql_db")
        self.features_container = self.cosmos_db.get_container_client("fraud_features")
        
        logger.info("Feature Engineer initialized")
    
    
    def compute_features(self, transaction: Dict) -> Dict:
        """
        Compute all 45 features for a transaction.
        
        Args:
            transaction: Dictionary with transaction details
                {
                    "payment_id": "pi_123",
                    "customer_id": "cus_456",
                    "merchant_id": "acct_789",
                    "amount": 5000,
                    "currency": "USD",
                    "card_country": "US",
                    "ip_address": "203.0.113.42",
                    "device_fingerprint": "fp_abc123",
                    "email": "customer@example.com"
                }
        
        Returns:
            Dictionary with 45 features
        """
        start_time = datetime.utcnow()
        logger.info(f"Computing features for payment {transaction['payment_id']}")
        
        features = {}
        
        # Category 1: Transaction Velocity (6 features)
        features.update(self._compute_velocity_features(transaction))
        
        # Category 2: Amount Analysis (8 features)
        features.update(self._compute_amount_features(transaction))
        
        # Category 3: Geography (7 features)
        features.update(self._compute_geo_features(transaction))
        
        # Category 4: Device & Email (6 features)
        features.update(self._compute_device_email_features(transaction))
        
        # Category 5: Customer History (8 features)
        features.update(self._compute_customer_history_features(transaction))
        
        # Category 6: Merchant Risk (5 features)
        features.update(self._compute_merchant_features(transaction))
        
        # Category 7: Contextual (5 features)
        features.update(self._compute_contextual_features(transaction))
        
        # Add metadata
        features['payment_id'] = transaction['payment_id']
        features['computed_at'] = datetime.utcnow().isoformat()
        
        elapsed_ms = (datetime.utcnow() - start_time).total_seconds() * 1000
        logger.info(f"Features computed in {elapsed_ms:.2f}ms")
        
        return features
    
    
    def _compute_velocity_features(self, txn: Dict) -> Dict:
        """Compute transaction velocity features."""
        customer_id = txn['customer_id']
        now = datetime.utcnow()
        
        # Query Cosmos DB for recent transactions
        query = """
        SELECT COUNT(1) as count
        FROM c
        WHERE c.customer_id = @customer_id
          AND c.timestamp >= @since
        """
        
        features = {}
        
        # 1h velocity
        items = list(self.features_container.query_items(
            query=query,
            parameters=[
                {"name": "@customer_id", "value": customer_id},
                {"name": "@since", "value": (now - timedelta(hours=1)).isoformat()}
            ],
            enable_cross_partition_query=True
        ))
        features['transaction_count_1h'] = items[0]['count'] if items else 0
        
        # 24h velocity
        items = list(self.features_container.query_items(
            query=query,
            parameters=[
                {"name": "@customer_id", "value": customer_id},
                {"name": "@since", "value": (now - timedelta(hours=24)).isoformat()}
            ],
            enable_cross_partition_query=True
        ))
        features['transaction_count_24h'] = items[0]['count'] if items else 0
        
        # 7d, 30d velocities (similar queries)
        features['transaction_count_7d'] = self._get_transaction_count(customer_id, days=7)
        features['transaction_count_30d'] = self._get_transaction_count(customer_id, days=30)
        
        # Unique cards and merchants (SQL query)
        cursor = self.sql_conn.cursor()
        cursor.execute("""
            SELECT 
                COUNT(DISTINCT PaymentMethod) as unique_cards,
                COUNT(DISTINCT MerchantID) as unique_merchants
            FROM Payment
            WHERE CustomerID = ?
              AND CreatedAt >= DATEADD(DAY, -30, GETDATE())
        """, customer_id)
        
        row = cursor.fetchone()
        features['unique_cards_30d'] = row.unique_cards if row else 0
        features['unique_merchants_30d'] = row.unique_merchants if row else 0
        
        return features
    
    
    def _compute_amount_features(self, txn: Dict) -> Dict:
        """Compute amount-based features."""
        customer_id = txn['customer_id']
        amount = txn['amount']
        
        # Get historical amounts (SQL)
        cursor = self.sql_conn.cursor()
        cursor.execute("""
            SELECT 
                AVG(CAST(Amount AS FLOAT)) as avg_amount,
                STDEV(CAST(Amount AS FLOAT)) as stddev_amount,
                MAX(Amount) as max_amount
            FROM Payment
            WHERE CustomerID = ?
              AND CreatedAt >= DATEADD(DAY, -7, GETDATE())
              AND Status = 'succeeded'
        """, customer_id)
        
        row = cursor.fetchone()
        
        avg_7d = row.avg_amount if row and row.avg_amount else amount
        stddev_7d = row.stddev_amount if row and row.stddev_amount else 0
        max_30d = row.max_amount if row and row.max_amount else amount
        
        features = {
            'avg_amount_7d': avg_7d,
            'stddev_amount_7d': stddev_7d,
            'max_amount_30d': max_30d,
            'amount_ratio_to_avg': amount / avg_7d if avg_7d > 0 else 1.0,
            'amount_zscore': (amount - avg_7d) / stddev_7d if stddev_7d > 0 else 0,
            'round_amount': 1 if amount % 100 == 0 else 0,
            'high_value_flag': 1 if amount > 1000000 else 0,  # > $10,000
            'amount_percentile': self._calculate_percentile(customer_id, amount)
        }
        
        return features
    
    
    def _compute_geo_features(self, txn: Dict) -> Dict:
        """Compute geographic features."""
        card_country = txn.get('card_country', 'US')
        ip_country = self._get_country_from_ip(txn['ip_address'])
        billing_country = txn.get('billing_country', 'US')
        
        # Get last transaction location
        last_lat, last_lon, last_time = self._get_last_transaction_location(
            txn['customer_id']
        )
        
        current_lat, current_lon = self._get_lat_lon_from_ip(txn['ip_address'])
        
        # Calculate distance
        distance_km = self._haversine_distance(
            last_lat, last_lon, current_lat, current_lon
        )
        
        # Calculate velocity (km/h)
        time_diff_hours = (datetime.utcnow() - last_time).total_seconds() / 3600
        velocity = distance_km / time_diff_hours if time_diff_hours > 0 else 0
        
        # High risk countries (simplified list)
        high_risk_countries = ['XX', 'YY', 'ZZ']  # Placeholder
        
        features = {
            'card_country_mismatch': 1 if card_country != ip_country else 0,
            'ip_country_mismatch': 1 if ip_country != billing_country else 0,
            'distance_km': distance_km,
            'velocity_km_per_hour': velocity,
            'high_risk_country': 1 if ip_country in high_risk_countries else 0,
            'country_change_24h': self._check_country_change(txn['customer_id']),
            'timezone_anomaly': self._check_timezone_anomaly(
                txn['customer_id'], 
                datetime.utcnow()
            )
        }
        
        return features
    
    
    def _compute_device_email_features(self, txn: Dict) -> Dict:
        """Compute device and email features."""
        device_fp = txn.get('device_fingerprint', '')
        email = txn.get('email', '')
        
        # Device fingerprint age
        device_age_days = self._get_device_age(txn['customer_id'], device_fp)
        
        # Email domain analysis
        email_domain = email.split('@')[1] if '@' in email else ''
        email_domain_age = self._get_email_domain_age(email_domain)
        
        free_email_domains = [
            'gmail.com', 'yahoo.com', 'hotmail.com', 
            'outlook.com', 'aol.com'
        ]
        disposable_domains = [
            'tempmail.com', '10minutemail.com', 'guerrillamail.com'
        ]
        
        features = {
            'device_fingerprint_age_days': device_age_days,
            'device_fingerprint_new': 1 if device_age_days < 1 else 0,
            'email_domain_age_days': email_domain_age,
            'email_domain_free': 1 if email_domain in free_email_domains else 0,
            'email_domain_disposable': 1 if email_domain in disposable_domains else 0,
            'browser_version_outdated': 0  # Placeholder (requires browser detection)
        }
        
        return features
    
    
    def _compute_customer_history_features(self, txn: Dict) -> Dict:
        """Compute customer history features."""
        customer_id = txn['customer_id']
        
        cursor = self.sql_conn.cursor()
        
        # Customer age
        cursor.execute("""
            SELECT DATEDIFF(DAY, CreatedAt, GETDATE()) as age_days
            FROM Customer
            WHERE CustomerID = ?
        """, customer_id)
        row = cursor.fetchone()
        customer_age_days = row.age_days if row else 0
        
        # Transaction history
        cursor.execute("""
            SELECT 
                COUNT(*) as total_txn,
                SUM(CASE WHEN Status = 'succeeded' THEN 1 ELSE 0 END) as success_count,
                SUM(Amount) as lifetime_value,
                DATEDIFF(DAY, MAX(CreatedAt), GETDATE()) as days_since_last
            FROM Payment
            WHERE CustomerID = ?
        """, customer_id)
        
        row = cursor.fetchone()
        
        total_txn = row.total_txn if row else 0
        success_count = row.success_count if row else 0
        
        # Dispute history
        cursor.execute("""
            SELECT COUNT(*) as dispute_count
            FROM Dispute d
            INNER JOIN Payment p ON d.PaymentID = p.PaymentID
            WHERE p.CustomerID = ?
        """, customer_id)
        
        row = cursor.fetchone()
        dispute_count = row.dispute_count if row else 0
        
        features = {
            'customer_age_days': customer_age_days,
            'first_transaction_customer': 1 if total_txn == 0 else 0,
            'customer_dispute_history': dispute_count,
            'customer_success_rate': success_count / total_txn if total_txn > 0 else 0,
            'days_since_last_transaction': row.days_since_last if row else 9999,
            'customer_lifetime_value': row.lifetime_value if row else 0,
            'avg_transaction_per_month': total_txn / (customer_age_days / 30) if customer_age_days > 0 else 0,
            'chargeback_rate_30d': self._get_chargeback_rate(customer_id)
        }
        
        return features
    
    
    def _compute_merchant_features(self, txn: Dict) -> Dict:
        """Compute merchant risk features."""
        merchant_id = txn['merchant_id']
        
        cursor = self.sql_conn.cursor()
        
        # Merchant age and stats
        cursor.execute("""
            SELECT 
                DATEDIFF(DAY, m.CreatedAt, GETDATE()) as age_days,
                m.Industry,
                COUNT(d.DisputeID) * 1.0 / NULLIF(COUNT(p.PaymentID), 0) as dispute_rate,
                AVG(CAST(p.Amount AS FLOAT)) as avg_ticket
            FROM Merchant m
            LEFT JOIN Payment p ON m.MerchantID = p.MerchantID 
                AND p.CreatedAt >= DATEADD(DAY, -30, GETDATE())
            LEFT JOIN Dispute d ON p.PaymentID = d.PaymentID
            WHERE m.MerchantID = ?
            GROUP BY m.CreatedAt, m.Industry
        """, merchant_id)
        
        row = cursor.fetchone()
        
        # Industry risk mapping (simplified)
        high_risk_industries = ['gambling', 'cryptocurrency', 'adult_content']
        medium_risk_industries = ['travel', 'electronics', 'jewelry']
        
        industry = row.Industry if row else 'unknown'
        if industry in high_risk_industries:
            industry_risk = 2
        elif industry in medium_risk_industries:
            industry_risk = 1
        else:
            industry_risk = 0
        
        features = {
            'merchant_age_days': row.age_days if row else 0,
            'merchant_dispute_rate_30d': row.dispute_rate if row and row.dispute_rate else 0,
            'merchant_chargeback_rate': self._get_merchant_chargeback_rate(merchant_id),
            'merchant_avg_ticket': row.avg_ticket if row and row.avg_ticket else 0,
            'merchant_industry_risk': industry_risk
        }
        
        return features
    
    
    def _compute_contextual_features(self, txn: Dict) -> Dict:
        """Compute contextual features."""
        now = datetime.utcnow()
        
        # Shipping address mismatch
        shipping_match = 1 if txn.get('shipping_address') == txn.get('billing_address') else 0
        
        # Holidays (simplified)
        holidays = [
            datetime(2025, 12, 25),  # Christmas
            datetime(2025, 1, 1),    # New Year
            datetime(2025, 7, 4),    # Independence Day
        ]
        is_holiday = 1 if now.date() in [h.date() for h in holidays] else 0
        
        features = {
            'time_of_day': now.hour,
            'day_of_week': now.weekday(),
            'is_weekend': 1 if now.weekday() >= 5 else 0,
            'is_holiday': is_holiday,
            'shipping_address_mismatch': 1 - shipping_match
        }
        
        return features
    
    
    # ========================================================================
    # HELPER METHODS
    # ========================================================================
    
    def _get_transaction_count(self, customer_id: str, days: int) -> int:
        """Get transaction count for customer in last N days."""
        # Implementation omitted for brevity
        return 0
    
    def _calculate_percentile(self, customer_id: str, amount: float) -> float:
        """Calculate percentile of current amount vs history."""
        # Implementation omitted for brevity
        return 0.5
    
    def _get_country_from_ip(self, ip_address: str) -> str:
        """Get country from IP address using GeoIP."""
        # In production: use MaxMind GeoIP2 or Azure Maps
        return "US"  # Placeholder
    
    def _get_lat_lon_from_ip(self, ip_address: str) -> tuple:
        """Get latitude/longitude from IP."""
        return (37.7749, -122.4194)  # Placeholder (San Francisco)
    
    def _haversine_distance(self, lat1: float, lon1: float, 
                           lat2: float, lon2: float) -> float:
        """Calculate distance between two points using Haversine formula."""
        from math import radians, sin, cos, sqrt, atan2
        
        R = 6371  # Earth radius in km
        
        dlat = radians(lat2 - lat1)
        dlon = radians(lon2 - lon1)
        
        a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon/2)**2
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c
    
    def _get_last_transaction_location(self, customer_id: str) -> tuple:
        """Get location of last transaction."""
        # Query Cosmos DB for last transaction
        return (37.7749, -122.4194, datetime.utcnow() - timedelta(hours=2))
    
    def _check_country_change(self, customer_id: str) -> int:
        """Check if country changed in last 24h."""
        # Implementation omitted
        return 0
    
    def _check_timezone_anomaly(self, customer_id: str, txn_time: datetime) -> int:
        """Check if transaction at unusual hour for customer."""
        # Implementation omitted
        return 0
    
    def _get_device_age(self, customer_id: str, device_fp: str) -> int:
        """Get age of device fingerprint in days."""
        # Query Cosmos DB
        return 30  # Placeholder
    
    def _get_email_domain_age(self, domain: str) -> int:
        """Get age of email domain in days."""
        # In production: use WHOIS API
        return 365  # Placeholder
    
    def _get_chargeback_rate(self, customer_id: str) -> float:
        """Get chargeback rate for customer."""
        # Implementation omitted
        return 0.01
    
    def _get_merchant_chargeback_rate(self, merchant_id: str) -> float:
        """Get chargeback rate for merchant."""
        # Implementation omitted
        return 0.015
    
    
    def store_features(self, features: Dict) -> None:
        """
        Store computed features in Cosmos DB for future reference.
        
        Args:
            features: Dictionary of computed features
        """
        self.features_container.upsert_item(features)
        logger.info(f"Features stored for payment {features['payment_id']}")


# ============================================================================
# BATCH FEATURE COMPUTATION (for training)
# ============================================================================

def compute_features_batch(
    transactions: pd.DataFrame,
    sql_connection_string: str,
    cosmos_endpoint: str
) -> pd.DataFrame:
    """
    Compute features for batch of transactions (for model training).
    
    Args:
        transactions: DataFrame with transaction data
        sql_connection_string: Azure SQL connection string
        cosmos_endpoint: Cosmos DB endpoint
    
    Returns:
        DataFrame with computed features
    """
    engineer = FeatureEngineer(sql_connection_string, cosmos_endpoint)
    
    features_list = []
    for idx, txn in transactions.iterrows():
        txn_dict = txn.to_dict()
        features = engineer.compute_features(txn_dict)
        features_list.append(features)
    
    features_df = pd.DataFrame(features_list)
    
    logger.info(f"Computed features for {len(features_df)} transactions")
    
    return features_df


if __name__ == "__main__":
    # Example usage
    sample_transaction = {
        "payment_id": "pi_test_123",
        "customer_id": "cus_test_456",
        "merchant_id": "acct_test_789",
        "amount": 5000,
        "currency": "USD",
        "card_country": "US",
        "ip_address": "203.0.113.42",
        "device_fingerprint": "fp_abc123",
        "email": "customer@example.com"
    }
    
    engineer = FeatureEngineer(
        sql_connection_string="connection_string_here",
        cosmos_endpoint="https://stripe-cosmos.documents.azure.com"
    )
    
    features = engineer.compute_features(sample_transaction)
    print(f"Computed {len(features)} features")
    print(features)