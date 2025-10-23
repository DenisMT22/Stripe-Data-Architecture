"""
Fraud Detection Model Training
Stripe Data Architecture - ML Module

Purpose: Train XGBoost model for fraud detection
Schedule: Weekly (incremental), Monthly (full retrain)
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    roc_auc_score, precision_score, recall_score, 
    f1_score, confusion_matrix, classification_report
)
import xgboost as xgb
import mlflow
import mlflow.xgboost
from mlflow.tracking import MlflowClient  # <-- CORRECT, pas azure.ai.mlflow
from datetime import datetime
import logging
import yaml
import joblib
from typing import Tuple, Dict

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FraudModelTrainer:
    """Train and evaluate fraud detection model."""
    
    def __init__(self, config_path: str = "config.yaml"):
        """
        Initialize trainer with configuration.
        
        Args:
            config_path: Path to config YAML file
        """
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        # MLflow setup
        mlflow.set_tracking_uri(self.config['mlflow']['tracking_uri'])
        mlflow.set_experiment(self.config['mlflow']['experiment_name'])
        
        logger.info("Fraud Model Trainer initialized")
    
    
    def load_training_data(self, start_date: str, end_date: str) -> pd.DataFrame:
        """
        Load training data from feature store.
        """
        logger.info(f"Loading training data from {start_date} to {end_date}")
        
        # Demo: Génère données synthétiques ; en prod : requête sur feature store réel
        n_samples = 1_000_000
        data = {
            # ... (les mêmes 45 features que dans ton code initial)
            'transaction_count_1h': np.random.poisson(2, n_samples),
            'transaction_count_24h': np.random.poisson(10, n_samples),
            'transaction_count_7d': np.random.poisson(50, n_samples),
            'transaction_count_30d': np.random.poisson(200, n_samples),
            'unique_cards_30d': np.random.randint(1, 5, n_samples),
            'unique_merchants_30d': np.random.randint(1, 10, n_samples),
            # ... (toutes les autres features inchangées)
            'merchant_industry_risk': np.random.choice([0, 1, 2], n_samples, p=[0.7, 0.2, 0.1]),
            'time_of_day': np.random.randint(0, 24, n_samples),
            'day_of_week': np.random.randint(0, 7, n_samples),
            'is_weekend': np.random.binomial(1, 2/7, n_samples),
            'is_holiday': np.random.binomial(1, 0.03, n_samples),
            'shipping_address_mismatch': np.random.binomial(1, 0.2, n_samples),
        }
        df = pd.DataFrame(data)
        fraud_prob = (
            0.01 + 0.15 * df['card_country_mismatch'] +
            0.20 * df['ip_country_mismatch'] +
            0.10 * df['device_fingerprint_new'] +
            0.15 * df['email_domain_disposable'] +
            0.10 * df['high_risk_country'] +
            0.05 * (df['velocity_km_per_hour'] > 500)
        )
        fraud_prob = np.clip(fraud_prob, 0, 1)
        df['is_fraud'] = np.random.binomial(1, fraud_prob)
        logger.info(f"Loaded {len(df)} samples, fraud rate: {df['is_fraud'].mean():.2%}")
        return df

    def prepare_data(self, df: pd.DataFrame) -> Tuple:
        logger.info("Preparing data for training")
        X = df.drop('is_fraud', axis=1)
        y = df['is_fraud']
        X_temp, X_test, y_temp, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42, stratify=y
        )
        X_train, X_val, y_train, y_val = train_test_split(
            X_temp, y_temp, test_size=0.25, random_state=42, stratify=y_temp
        )
        logger.info(f"Train: {len(X_train)}, Val: {len(X_val)}, Test: {len(X_test)}")
        logger.info(f"Train fraud rate: {y_train.mean():.2%}")
        return X_train, X_val, X_test, y_train, y_val, y_test

    def train_model(self, X_train: pd.DataFrame, y_train: pd.Series,
                   X_val: pd.DataFrame, y_val: pd.Series) -> xgb.XGBClassifier:
        logger.info("Training XGBoost model")
        scale_pos_weight = len(y_train[y_train == 0]) / len(y_train[y_train == 1])
        logger.info(f"Scale pos weight: {scale_pos_weight:.2f}")
        params = self.config['model']['params']
        params['scale_pos_weight'] = scale_pos_weight
        model = xgb.XGBClassifier(**params)
        model.fit(
            X_train, y_train,
            eval_set=[(X_val, y_val)],
            early_stopping_rounds=50,
            verbose=100
        )
        logger.info(f"Training completed. Best iteration: {model.best_iteration}")
        return model

    def evaluate_model(self, model: xgb.XGBClassifier,
                      X_test: pd.DataFrame, y_test: pd.Series) -> Dict:
        logger.info("Evaluating model")
        y_pred_proba = model.predict_proba(X_test)[:, 1]
        y_pred = (y_pred_proba >= 0.7).astype(int)
        metrics = {
            'auc_roc': roc_auc_score(y_test, y_pred_proba),
            'precision': precision_score(y_test, y_pred),
            'recall': recall_score(y_test, y_pred),
            'f1_score': f1_score(y_test, y_pred),
            'false_positive_rate': self._calculate_fpr(y_test, y_pred),
            'false_negative_rate': 1 - recall_score(y_test, y_pred)
        }
        cm = confusion_matrix(y_test, y_pred)
        metrics['true_negatives'] = int(cm[0, 0])
        metrics['false_positives'] = int(cm[0, 1])
        metrics['false_negatives'] = int(cm[1, 0])
        metrics['true_positives'] = int(cm[1, 1])
        logger.info("Model Performance:")
        logger.info(f"  AUC-ROC: {metrics['auc_roc']:.4f}")
        logger.info(f"  Precision: {metrics['precision']:.4f}")
        logger.info(f"  Recall: {metrics['recall']:.4f}")
        logger.info(f"  F1-Score: {metrics['f1_score']:.4f}")
        logger.info(f"  False Positive Rate: {metrics['false_positive_rate']:.4f}")
        logger.info("\nClassification Report:")
        logger.info(classification_report(y_test, y_pred))
        return metrics

    def _calculate_fpr(self, y_true, y_pred) -> float:
        cm = confusion_matrix(y_true, y_pred)
        fp = cm[0, 1]
        tn = cm[0, 0]
        return fp / (fp + tn) if (fp + tn) > 0 else 0

    def analyze_feature_importance(self, model: xgb.XGBClassifier,
                                   feature_names: list) -> pd.DataFrame:
        logger.info("Analyzing feature importance")
        importance = model.feature_importances_
        feature_importance_df = pd.DataFrame({
            'feature': feature_names,
            'importance': importance
        }).sort_values('importance', ascending=False)
        logger.info("\nTop 10 Most Important Features:")
        logger.info(feature_importance_df.head(10))
        return feature_importance_df

    def log_to_mlflow(self, model: xgb.XGBClassifier, metrics: Dict,
                     feature_importance: pd.DataFrame) -> str:
        logger.info("Logging to MLflow")
        with mlflow.start_run() as run:
            mlflow.log_params(self.config['model']['params'])
            mlflow.log_metrics(metrics)
            mlflow.xgboost.log_model(
                model,
                artifact_path="model",
                registered_model_name="fraud_detection_model"
            )
            feature_importance.to_csv('feature_importance.csv', index=False)
            mlflow.log_artifact('feature_importance.csv')
            mlflow.log_artifact('config.yaml')
            mlflow.set_tags({
                'model_type': 'xgboost',
                'version': '2.3.1',
                'training_date': datetime.utcnow().isoformat(),
                'environment': 'production'
            })
            logger.info(f"Model logged to MLflow. Run ID: {run.info.run_id}")
            return run.info.run_id

    def save_model_locally(self, model: xgb.XGBClassifier, 
                          path: str = 'fraud_model.pkl') -> None:
        joblib.dump(model, path)
        logger.info(f"Model saved to {path}")

    def run_training_pipeline(self, start_date: str, end_date: str) -> Dict:
        logger.info("=" * 60)
        logger.info("FRAUD DETECTION MODEL TRAINING PIPELINE")
        logger.info("=" * 60)
        df = self.load_training_data(start_date, end_date)
        X_train, X_val, X_test, y_train, y_val, y_test = self.prepare_data(df)
        model = self.train_model(X_train, y_train, X_val, y_val)
        metrics = self.evaluate_model(model, X_test, y_test)
        feature_importance = self.analyze_feature_importance(
            model, 
            X_train.columns.tolist()
        )
        run_id = self.log_to_mlflow(model, metrics, feature_importance)
        self.save_model_locally(model)
        logger.info("=" * 60)
        logger.info("TRAINING PIPELINE COMPLETED SUCCESSFULLY")
        logger.info("=" * 60)
        return {
            'run_id': run_id,
            'metrics': metrics,
            'model_path': 'fraud_model.pkl'
        }


# MODEL COMPARISON & SELECTION

def compare_models(candidate_run_id: str, production_run_id: str) -> bool:
    """
    Compare candidate model with production model.
    """
    client = MlflowClient()
    candidate_metrics = client.get_run(candidate_run_id).data.metrics
    production_metrics = client.get_run(production_run_id).data.metrics
    improvements = {
        'auc_roc': candidate_metrics['auc_roc'] > production_metrics['auc_roc'],
        'recall': candidate_metrics['recall'] > production_metrics['recall'] - 0.01,
        'precision': candidate_metrics['precision'] > production_metrics['precision'] - 0.02,
        'false_positive_rate': candidate_metrics['false_positive_rate'] < production_metrics['false_positive_rate']
    }
    promote = all(improvements.values())
    logger.info(f"Model Comparison:")
    logger.info(f"  AUC-ROC: {candidate_metrics['auc_roc']:.4f} vs {production_metrics['auc_roc']:.4f} ({'✓' if improvements['auc_roc'] else '✗'})")
    logger.info(f"  Recall: {candidate_metrics['recall']:.4f} vs {production_metrics['recall']:.4f} ({'✓' if improvements['recall'] else '✗'})")
    logger.info(f"  Precision: {candidate_metrics['precision']:.4f} vs {production_metrics['precision']:.4f} ({'✓' if improvements['precision'] else '✗'})")
    logger.info(f"  FPR: {candidate_metrics['false_positive_rate']:.4f} vs {production_metrics['false_positive_rate']:.4f} ({'✓' if improvements['false_positive_rate'] else '✗'})")
    logger.info(f"  Decision: {'PROMOTE ✓' if promote else 'REJECT ✗'}")
    return promote

# HYPERPARAMETER TUNING

def hyperparameter_tuning(X_train, y_train, X_val, y_val) -> Dict:
    from hyperopt import hp, fmin, tpe, Trials, STATUS_OK
    def objective(params):
        model = xgb.XGBClassifier(**params)
        model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)
        y_pred_proba = model.predict_proba(X_val)[:, 1]
        auc = roc_auc_score(y_val, y_pred_proba)
        return {'loss': -auc, 'status': STATUS_OK}
    space = {
        'n_estimators': hp.choice('n_estimators', [300, 500, 700]),
        'max_depth': hp.choice('max_depth', [6, 8, 10]),
        'learning_rate': hp.loguniform('learning_rate', np.log(0.01), np.log(0.1)),
        'subsample': hp.uniform('subsample', 0.7, 0.9),
        'colsample_bytree': hp.uniform('colsample_bytree', 0.7, 0.9),
        'objective': 'binary:logistic',
        'eval_metric': 'auc'
    }
    trials = Trials()
    best_params = fmin(
        fn=objective,
        space=space,
        algo=tpe.suggest,
        max_evals=50,
        trials=trials
    )
    logger.info(f"Best hyperparameters: {best_params}")
    return best_params

# MAIN EXECUTION

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Train fraud detection model")
    parser.add_argument('--start-date', default='2025-04-01', help='Training data start date')
    parser.add_argument('--end-date', default='2025-10-01', help='Training data end date')
    parser.add_argument('--config', default='config.yaml', help='Config file path')
    args = parser.parse_args()
    trainer = FraudModelTrainer(config_path=args.config)
    result = trainer.run_training_pipeline(args.start_date, args.end_date)
    print("\n" + "=" * 60)
    print("TRAINING SUMMARY")
    print("=" * 60)
    print(f"Run ID: {result['run_id']}")
    print(f"Model Path: {result['model_path']}")
    print("\nMetrics:")
    for metric, value in result['metrics'].items():
        print(f"  {metric}: {value:.4f}")
    print("=" * 60)

