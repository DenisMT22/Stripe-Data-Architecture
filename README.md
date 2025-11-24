# Architecture de Données Stripe

La Présentation + la Vidéo de déploiement sont consultables via ce lien https://drive.google.com/drive/folders/1DmyGvGb58mn18-oMCWjkortsZ5wElDGC?usp=sharing


## Contexte

Conception d'une architecture de données complète pour Stripe (FinTech) intégrant :

- **OLTP** : Système transactionnel haute performance
- **OLAP** : Système analytique pour Business Intelligence
- **NoSQL** : Gestion de données non structurées et ML

## Objectifs

1. Gérer des millions de transactions par jour
2. Fournir des analyses en temps quasi-réel
3. Détecter la fraude via Machine Learning
4. Assurer la conformité GDPR, PCI-DSS, CCPA
5. Scalabilité horizontale sur Azure

## Architecture

### Composants principaux

#### Azure

- **OLTP** : Azure SQL Database (HA)
- **OLAP** : Azure Synapse Analytics
- **NoSQL** : Azure Cosmos DB
- **Streaming** : Azure Event Hubs
- **Orchestration** : Azure Data Factory + Apache Airflow
- **ML** : Azure Machine Learning

#### GCP

- **OLTP** : Cloud SQL (PostgreSQL)
- **OLAP** : BigQuery (Star Schema)
- **NoSQL** : Firestore (JSON Docs)
- **Streaming** : Pub/Sub
- **Data Lake** : Cloud Storage
 


### Technologies utilisées

- **IaC** : Terraform
- **Containers** : Docker
- **CI/CD** : GitHub Actions
- **Monitoring** : Google Cloud Operations (Cloud Monitoring)

## Structure du projet

stripe-data-architecture/
├── docs/                    # Documentation technique
├── models/                  # Modèles de données (OLTP/OLAP/NoSQL)
├── pipelines/              # Code des pipelines de données
├── queries/                # Exemples de requêtes SQL/NoSQL
├── diagrams/               # Diagrammes d'architecture
└── presentation/           # Slides de présentation

## Déploiement

Instructions de déploiement dans `pipelines/terraform/gcp/README.md`

