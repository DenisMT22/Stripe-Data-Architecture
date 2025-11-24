# 🌐 Stripe Data Architecture - Déploiement GCP

**Bloc 2 : Concevoir et déployer des architecture de données (pour l'IA)**

Infrastructure complète de traitement de données Stripe sur Google Cloud Platform en parallèle d'Azure.

---

## 📋 Table des Matières

1. [Vue d'ensemble](#vue-densemble)
2. [Architecture GCP](#architecture-gcp)
3. [Prérequis](#prérequis)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Déploiement](#déploiement)
7. [Vérifications](#vérifications)
8. [Captures d'écran](#captures-décran)
9. [Destruction](#destruction)
10. [Coûts](#coûts)
11. [Troubleshooting](#troubleshooting)

---

## 🎯 Vue d'ensemble

### Objectif

Déployer une architecture de données complète sur GCP pour le traitement transactionnel et analytique de Stripe, en utilisant la stratégie **Deploy → Capture → Destroy** pour minimiser les coûts.

### Composants Déployés

| Composant | Service GCP | Usage |
|-----------|-------------|-------|
| **OLTP** | Cloud SQL (PostgreSQL 15) | Base transactionnelle |
| **OLAP** | BigQuery | Data Warehouse (Star Schema) |
| **NoSQL** | Firestore | Logs, sessions, ML features |
| **Storage** | Cloud Storage | Data Lake |
| **Streaming** | Pub/Sub | Ingestion temps réel |
| **Secrets** | Secret Manager | Credentials |
| **IAM** | Service Accounts | Permissions ETL |

---

## 🏗️ Architecture GCP

```
┌─────────────────────────────────────────────────────────────┐
│                    STRIPE DATA PLATFORM                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐      ┌──────────────┐      ┌───────────┐│
│  │  Cloud SQL   │─────▶│  BigQuery    │◀────▶│ Firestore ││
│  │  (OLTP)      │ ETL  │  (OLAP)      │ Logs │ (NoSQL)   ││
│  │ PostgreSQL   │      │ Star Schema  │      │ JSON Docs ││
│  └──────────────┘      └──────────────┘      └───────────┘│
│         ▲                      ▲                    ▲       │
│         │                      │                    │       │
│         └──────────┬───────────┴────────────────────┘       │
│                    │                                        │
│            ┌───────▼────────┐                              │
│            │   Pub/Sub      │                              │
│            │ (Streaming)    │                              │
│            └────────────────┘                              │
│                    ▲                                        │
│                    │                                        │
│            ┌───────▼────────┐                              │
│            │ Cloud Storage  │                              │
│            │  (Data Lake)   │                              │
│            └────────────────┘                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Équivalences Azure ↔ GCP

| Azure | GCP | Raison |
|-------|-----|--------|
| Azure SQL Database | Cloud SQL PostgreSQL | Compatibilité OLTP |
| Azure Synapse Analytics | BigQuery | OLAP serverless |
| Azure Cosmos DB | Firestore | NoSQL documentaire |
| Azure Blob Storage | Cloud Storage | Object storage |
| Azure Event Hubs | Pub/Sub | Messaging |
| Azure Key Vault | Secret Manager | Secrets |

---

## ✅ Prérequis

### 1. Compte Google Cloud Platform

- **Nouveau compte** : [300$ de crédits gratuits](https://cloud.google.com/free)
- **Compte existant** : Vérifier crédits disponibles
- Carte bancaire requise (pas de débit si crédits suffisants)

### 2. Outils Installés

```bash
# Vérifier installations
gcloud version      # Google Cloud SDK
terraform --version # Terraform >= 1.0
jq --version       # JSON processor
psql --version     # PostgreSQL client
```

### 3. Quota Projet

- Projet GCP actif
- APIs non bloquées par l'organisation
- Quota Compute Engine disponible

---

## 🔧 Installation

### Étape 1 : Installer Google Cloud SDK

#### **macOS**
```bash
# Homebrew
brew install --cask google-cloud-sdk

# Vérification
gcloud version
```

#### **Linux**
```bash
# Ubuntu/Debian
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
sudo apt update && sudo apt install google-cloud-sdk

# Vérification
gcloud version
```

#### **Windows**
```powershell
# Télécharger installateur
https://cloud.google.com/sdk/docs/install#windows

# Après installation
gcloud version
```

### Étape 2 : Authentification

```bash
# Connexion à GCP
gcloud auth login

# Lister comptes actifs
gcloud auth list

# Définir configuration par défaut
gcloud config set project YOUR_PROJECT_ID
```

### Étape 3 : Créer Projet GCP

```bash
# Option 1 : Via console web
# https://console.cloud.google.com/projectcreate

# Option 2 : Via gcloud
gcloud projects create stripe-data-XXXXXX --name="Stripe Data Architecture"

# Lier compte de facturation
gcloud beta billing projects link stripe-data-XXXXXX --billing-account=YOUR_BILLING_ACCOUNT
```

### Étape 4 : Installer Terraform

```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Linux
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Vérification
terraform --version
```

---

## ⚙️ Configuration

### Variables d'Environnement

Créer un fichier `.env` (ne PAS committer) :

```bash
# .env
export GCP_PROJECT_ID="stripe-data-123456"
export GCP_REGION="europe-west1"
export SQL_ADMIN_PASSWORD="VotreMotDePasseSecurise12345!"
```

Charger les variables :

```bash
source .env
```

### Fichier `terraform.tfvars` (automatiquement créé par deploy.sh)

```hcl
project_id         = "stripe-data-123456"
region             = "europe-west1"
sql_admin_password = "VotreMotDePasseSecurise12345!"
environment        = "dev"
```

---

## 🚀 Déploiement

### Déploiement Automatisé (RECOMMANDÉ)

```bash
# Naviguer vers le dossier GCP
cd pipelines/terraform/gcp

# Définir variables
export GCP_PROJECT_ID="stripe-data-123456"
export SQL_ADMIN_PASSWORD="VotreMotDePasseSecurise12345!"

# Lancer déploiement
./deploy.sh
```

Le script va :
1. ✅ Vérifier prérequis
2. ✅ Activer APIs GCP nécessaires
3. ✅ Initialiser Terraform
4. ✅ Générer le plan
5. ✅ Déployer infrastructure (~10-15 min)
6. ✅ Afficher connexions

### Déploiement Manuel

```bash
cd pipelines/terraform/gcp

# Initialisation
terraform init

# Validation
terraform validate

# Plan
terraform plan -out=tfplan

# Application
terraform apply tfplan
```

---

## 🔍 Vérifications

### 1. Vérifier Outputs Terraform

```bash
# Afficher tous les outputs
terraform output

# Connexion Cloud SQL
terraform output sql_connection_command

# URLs console
terraform output gcp_console_urls
```

### 2. Tester Cloud SQL

```bash
# Connexion via psql
export SQL_IP=$(terraform output -raw sql_public_ip)
psql -h $SQL_IP -U stripe_admin -d stripe_oltp

# Depuis GCP Console
gcloud sql connect $(terraform output -raw sql_instance_name) --user=stripe_admin
```

### 3. Tester BigQuery

```bash
# Lister tables
bq ls stripe_olap

# Requête test
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) FROM `stripe_olap.fact_transactions`'
```

### 4. Tester Firestore

```bash
# Via console
https://console.cloud.google.com/firestore?project=YOUR_PROJECT_ID

# Via gcloud
gcloud firestore databases describe --database="(default)"
```

### 5. Tester Cloud Storage

```bash
# Lister buckets
gsutil ls

# Lister contenu
gsutil ls -r gs://YOUR_PROJECT_ID-stripe-data-datalake/
```

---

## 📸 Captures d'Écran

### Checklist des 10 Captures Obligatoires

#### **1. Dashboard GCP**
- URL : `https://console.cloud.google.com/home/dashboard`
- Capture : Vue d'ensemble projet avec APIs activées

#### **2. Cloud SQL Instance**
- URL : `https://console.cloud.google.com/sql/instances`
- Capture : Instance PostgreSQL avec statut "Running"

#### **3. BigQuery Dataset**
- URL : `https://console.cloud.google.com/bigquery`
- Capture : Dataset `stripe_olap` avec les 5 tables visibles

#### **4. BigQuery Tables**
- URL : `https://console.cloud.google.com/bigquery`
- Capture : Schéma de `fact_transactions` avec colonnes

#### **5. Firestore**
- URL : `https://console.cloud.google.com/firestore`
- Capture : Base Firestore Native mode activé

#### **6. Cloud Storage Bucket**
- URL : `https://console.cloud.google.com/storage/browser`
- Capture : Bucket avec dossiers (raw/, processed/, logs/)

#### **7. Pub/Sub Topic**
- URL : `https://console.cloud.google.com/cloudpubsub/topic`
- Capture : Topic `stripe-data-transactions` actif

#### **8. IAM Service Account**
- URL : `https://console.cloud.google.com/iam-admin/serviceaccounts`
- Capture : Service account ETL avec permissions

#### **9. Terraform Outputs**
- Terminal : `terraform output`
- Capture : Tous les outputs (connexions, URLs)

#### **10. Billing Report**
- URL : `https://console.cloud.google.com/billing/costTable`
- Capture : Coûts du jour (preuve de déploiement temporaire)

### Script de Captures Automatisé

```bash
# Créer dossier captures
mkdir -p screenshots

# Ouvrir toutes les URLs nécessaires
URLS=(
  "https://console.cloud.google.com/home/dashboard?project=$GCP_PROJECT_ID"
  "https://console.cloud.google.com/sql/instances?project=$GCP_PROJECT_ID"
  "https://console.cloud.google.com/bigquery?project=$GCP_PROJECT_ID"
  "https://console.cloud.google.com/firestore?project=$GCP_PROJECT_ID"
  "https://console.cloud.google.com/storage/browser?project=$GCP_PROJECT_ID"
  "https://console.cloud.google.com/cloudpubsub/topic/list?project=$GCP_PROJECT_ID"
  "https://console.cloud.google.com/iam-admin/serviceaccounts?project=$GCP_PROJECT_ID"
  "https://console.cloud.google.com/billing/costTable?project=$GCP_PROJECT_ID"
)

for url in "${URLS[@]}"; do
  open "$url"  # macOS
  # xdg-open "$url"  # Linux
done

# Afficher outputs
terraform output
```

---

## 🗑️ Destruction

### Destruction Automatisée (RECOMMANDÉ)

```bash
cd pipelines/terraform/gcp

# Lancer destruction
./destroy.sh
```

Le script va :
1. ⚠️ Demander confirmation (taper "DESTROY")
2. 🗑️ Détruire toutes les ressources Terraform
3. 🔍 Vérifier ressources orphelines
4. 🧹 Nettoyer fichiers temporaires
5. 📄 Générer rapport de destruction

### Destruction Manuelle

```bash
# Destruction Terraform
terraform destroy -auto-approve

# Vérification
./verify_cleanup.sh
```

### Vérification Post-Destruction

```bash
# Script de vérification
./verify_cleanup.sh

# Vérification manuelle
gcloud sql instances list --project=$GCP_PROJECT_ID
gsutil ls -p $GCP_PROJECT_ID
bq ls --project_id=$GCP_PROJECT_ID
```

---

## 💰 Coûts

### Estimation Mensuelle (Déploiement Permanent)

| Service | Configuration | Coût/Mois |
|---------|---------------|-----------|
| Cloud SQL | db-f1-micro (0.6GB RAM) | ~8 USD |
| BigQuery | Stockage 10GB | ~0.20 USD |
| Firestore | < 1GB | Gratuit |
| Cloud Storage | 10GB STANDARD | ~0.20 USD |
| Pub/Sub | < 10GB/mois | Gratuit |
| Secret Manager | 6 secrets | Gratuit |
| **TOTAL** | | **~8-10 USD/mois** |

### Stratégie "Deploy → Capture → Destroy"

| Durée | Coût Estimé |
|-------|-------------|
| 1 heure | ~0.11 USD |
| 2 heures | ~0.22 USD |
| **3 heures** | **~0.33 USD** |
| 24 heures | ~2.70 USD |

**Avec 300$ de crédits gratuits :** Possibilité de déployer ~900 sessions de 3h !

### Optimisations Coûts

1. **Cloud SQL** : Utiliser `db-f1-micro` (tier gratuit éligible)
2. **BigQuery** : Partitionnement pour réduire scans
3. **Cloud Storage** : Lifecycle policy (suppression après 90j)
4. **High Availability** : Désactivée (économie 50%)
5. **Backups** : Rétention 7 jours seulement

---

## 🔧 Troubleshooting

### Problème : APIs Non Activées

```bash
# Erreur
Error: Error creating instance: googleapi: Error 403: Access Not Configured

# Solution
gcloud services enable compute.googleapis.com sqladmin.googleapis.com
```

### Problème : Quota Dépassé

```bash
# Erreur
Error: Quota 'CPUS' exceeded

# Solution
1. Vérifier quotas : https://console.cloud.google.com/iam-admin/quotas
2. Demander augmentation ou utiliser autre région
```

### Problème : Billing Non Activé

```bash
# Erreur
Error: The billing account for the owning project is disabled

# Solution
https://console.cloud.google.com/billing/linkedaccount
```

### Problème : Connexion Cloud SQL Refusée

```bash
# Erreur
psql: could not connect to server: Connection refused

# Solutions
1. Vérifier IP publique autorisée (0.0.0.0/0 temporairement)
2. Attendre 2-3 min après déploiement (propagation)
3. Utiliser Cloud SQL Proxy :
   cloud_sql_proxy -instances=CONNECTION_NAME=tcp:5432
```

### Problème : Terraform State Lock

```bash
# Erreur
Error: Error locking state

# Solution
terraform force-unlock LOCK_ID
```

### Problème : Ressources Déjà Existantes

```bash
# Erreur
Error: Resource already exists

# Solution
terraform import google_sql_database_instance.stripe_oltp instance-name
```

---

## 📚 Ressources

### Documentation Officielle

- [Google Cloud Documentation](https://cloud.google.com/docs)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud SQL Best Practices](https://cloud.google.com/sql/docs/postgres/best-practices)
- [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)

### Tutoriels

- [Getting Started with GCP](https://cloud.google.com/docs/get-started)
- [Terraform on GCP](https://learn.hashicorp.com/tutorials/terraform/google-cloud-platform-build)
- [Cloud SQL Connection](https://cloud.google.com/sql/docs/postgres/connect-overview)

### Tarification

- [Calculateur de Prix GCP](https://cloud.google.com/products/calculator)
- [Cloud SQL Pricing](https://cloud.google.com/sql/pricing)
- [BigQuery Pricing](https://cloud.google.com/bigquery/pricing)

---

## Compétences Démontrées

1. **Architecture Multi-Cloud** : Azure + GCP
2. **Infrastructure as Code** : Terraform
3. **Base de Données OLTP** : Cloud SQL (PostgreSQL)
4. **Data Warehouse** : BigQuery (Star Schema)
5. **NoSQL** : Firestore
6. **Streaming** : Pub/Sub
7. **DevOps** : Scripts automatisés, CI/CD ready
8. **Sécurité** : IAM, Secret Manager, RBAC
9. **Conformité RGPD** : Région EU, encryption
10. **Gestion Coûts** : Stratégie économique

### Livrables

- ✅ Code Terraform complet
- ✅ Scripts déploiement/destruction
- ✅ Documentation technique
- ✅ 10 captures d'écran
- ✅ Comparatif Azure/GCP
- ✅ Analyse de coûts



