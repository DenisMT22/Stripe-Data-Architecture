#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# STRIPE DATA ARCHITECTURE - DÉPLOIEMENT GCP
# ═══════════════════════════════════════════════════════════════════
# Script automatisé de déploiement infrastructure GCP avec Terraform
# Stratégie : Deploy → Capture → Destroy
# ═══════════════════════════════════════════════════════════════════

set -e  # Arrêter si erreur
set -u  # Arrêter si variable non définie

# ───────────────────────────────────────────────────────────────────
# CONFIGURATION
# ───────────────────────────────────────────────────────────────────

PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-europe-west1}"
SQL_PASSWORD="${SQL_ADMIN_PASSWORD:-}"

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ───────────────────────────────────────────────────────────────────
# FONCTIONS UTILITAIRES
# ───────────────────────────────────────────────────────────────────

print_header() {
    echo -e "${BLUE}"
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ ERREUR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 n'est pas installé. Installation requise."
        exit 1
    fi
}

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATIONS PRÉ-DÉPLOIEMENT
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATIONS PRÉ-DÉPLOIEMENT"

# Vérifier commandes nécessaires
print_info "Vérification des outils requis..."
check_command gcloud
check_command terraform
check_command jq
print_success "Tous les outils sont installés"

# Vérifier connexion gcloud
print_info "Vérification authentification gcloud..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    print_error "Pas de compte gcloud actif. Exécutez: gcloud auth login"
    exit 1
fi
CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
print_success "Connecté avec: $CURRENT_ACCOUNT"

# Demander PROJECT_ID si non fourni
if [ -z "$PROJECT_ID" ]; then
    print_warning "Variable GCP_PROJECT_ID non définie"
    echo -n "Entrez l'ID de votre projet GCP: "
    read PROJECT_ID
    export GCP_PROJECT_ID="$PROJECT_ID"
fi

# Vérifier que le projet existe
print_info "Vérification du projet: $PROJECT_ID"
if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    print_error "Le projet $PROJECT_ID n'existe pas ou n'est pas accessible"
    exit 1
fi
print_success "Projet $PROJECT_ID trouvé"

# Définir projet par défaut
gcloud config set project "$PROJECT_ID" --quiet
print_success "Projet par défaut défini: $PROJECT_ID"

# Demander mot de passe SQL si non fourni
if [ -z "$SQL_PASSWORD" ]; then
    print_warning "Variable SQL_ADMIN_PASSWORD non définie"
    echo -n "Entrez le mot de passe pour l'admin SQL (min 12 caractères): "
    read -s SQL_PASSWORD
    echo
    export SQL_ADMIN_PASSWORD="$SQL_PASSWORD"
    
    # Validation longueur
    if [ ${#SQL_PASSWORD} -lt 12 ]; then
        print_error "Le mot de passe doit contenir au moins 12 caractères"
        exit 1
    fi
fi

# ───────────────────────────────────────────────────────────────────
# ACTIVATION DES APIs GCP
# ───────────────────────────────────────────────────────────────────

print_header "ACTIVATION DES APIs GCP"

REQUIRED_APIS=(
    "compute.googleapis.com"
    "sqladmin.googleapis.com"
    "bigquery.googleapis.com"
    "firestore.googleapis.com"
    "storage.googleapis.com"
    "pubsub.googleapis.com"
    "secretmanager.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "iam.googleapis.com"
    "servicenetworking.googleapis.com"
)

print_info "Activation des APIs nécessaires (peut prendre 2-3 minutes)..."

for api in "${REQUIRED_APIS[@]}"; do
    echo -n "  - $api ... "
    if gcloud services enable "$api" --project="$PROJECT_ID" --quiet 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}déjà active${NC}"
    fi
done

print_success "Toutes les APIs sont activées"

# Attendre propagation des APIs
print_info "Attente propagation des APIs (30 secondes)..."
sleep 30

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION BILLING
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION FACTURATION"

BILLING_ENABLED=$(gcloud beta billing projects describe "$PROJECT_ID" \
    --format="value(billingEnabled)" 2>/dev/null || echo "false")

if [ "$BILLING_ENABLED" = "true" ]; then
    print_success "Facturation activée sur le projet"
else
    print_warning "La facturation n'est pas activée sur ce projet"
    print_info "Activez-la sur: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
    echo -n "Continuer quand même ? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_error "Déploiement annulé"
        exit 1
    fi
fi

# ───────────────────────────────────────────────────────────────────
# CONFIGURATION TERRAFORM
# ───────────────────────────────────────────────────────────────────

print_header "CONFIGURATION TERRAFORM"

# Créer fichier terraform.tfvars
print_info "Création du fichier terraform.tfvars..."
cat > terraform.tfvars <<EOF
# Configuration générée automatiquement par deploy.sh
project_id        = "$PROJECT_ID"
region            = "$REGION"
sql_admin_password = "$SQL_PASSWORD"

# Configuration optimisée pour déploiement court
environment       = "dev"
sql_tier          = "db-f1-micro"
enable_high_availability = false
enable_backups    = true
deletion_protection = false
EOF

print_success "Fichier terraform.tfvars créé"

# ───────────────────────────────────────────────────────────────────
# INITIALISATION TERRAFORM
# ───────────────────────────────────────────────────────────────────

print_header "INITIALISATION TERRAFORM"

print_info "Téléchargement des providers..."
terraform init -upgrade

print_success "Terraform initialisé"

# ───────────────────────────────────────────────────────────────────
# VALIDATION CONFIGURATION
# ───────────────────────────────────────────────────────────────────

print_header "VALIDATION CONFIGURATION"

print_info "Validation syntaxe Terraform..."
terraform validate

print_success "Configuration valide"

# ───────────────────────────────────────────────────────────────────
# PLAN TERRAFORM
# ───────────────────────────────────────────────────────────────────

print_header "GÉNÉRATION DU PLAN"

print_info "Calcul des ressources à créer..."
terraform plan -out=tfplan

print_success "Plan généré (tfplan)"

# Afficher résumé
RESOURCES_TO_ADD=$(terraform show -json tfplan | jq -r '.resource_changes | map(select(.change.actions[0] == "create")) | length')
print_info "Ressources à créer: $RESOURCES_TO_ADD"

# ───────────────────────────────────────────────────────────────────
# CONFIRMATION UTILISATEUR
# ───────────────────────────────────────────────────────────────────

print_warning "COÛTS ESTIMÉS"
echo "  Cloud SQL (db-f1-micro): ~0.27 USD/jour"
echo "  BigQuery storage: ~0.02 USD/GB/mois"
echo "  Cloud Storage: ~0.02 USD/GB/mois"
echo "  Autres services: gratuits (free tier)"
echo "  ────────────────────────────────────"
echo "  TOTAL session 3h: ~0.50-0.80 USD"
echo ""

print_warning "⏰ RAPPEL: Détruire les ressources après captures (3h max)"

echo -n "Lancer le déploiement ? (y/N): "
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    print_warning "Déploiement annulé par l'utilisateur"
    rm -f tfplan terraform.tfvars
    exit 0
fi

# ───────────────────────────────────────────────────────────────────
# DÉPLOIEMENT
# ───────────────────────────────────────────────────────────────────

print_header "DÉPLOIEMENT EN COURS"

START_TIME=$(date +%s)
print_info "Début: $(date '+%Y-%m-%d %H:%M:%S')"
print_warning "Durée estimée: 10-15 minutes"

terraform apply tfplan

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

print_success "Déploiement terminé en ${MINUTES}m${SECONDS}s"

# ───────────────────────────────────────────────────────────────────
# AFFICHAGE OUTPUTS
# ───────────────────────────────────────────────────────────────────

print_header "INFORMATIONS DE CONNEXION"

terraform output -json > outputs.json
print_success "Outputs sauvegardés dans outputs.json"

echo ""
print_info "CONNEXION CLOUD SQL:"
terraform output -raw sql_connection_command
echo ""

print_info "BIGQUERY DATASET:"
terraform output -raw bigquery_console_url
echo ""

print_info "CONSOLE GCP:"
echo "https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
echo ""

# ───────────────────────────────────────────────────────────────────
# PROCHAINES ÉTAPES
# ───────────────────────────────────────────────────────────────────

print_header "PROCHAINES ÉTAPES"

echo "1️⃣  Vérifier ressources dans la console GCP"
echo "2️⃣  Capturer 10 screenshots pour certification:"
echo "    - Dashboard GCP"
echo "    - Cloud SQL instance"
echo "    - BigQuery dataset + tables"
echo "    - Firestore"
echo "    - Cloud Storage bucket"
echo "    - Pub/Sub topic"
echo "    - IAM service account"
echo "    - Billing report"
echo "    - Terraform outputs"
echo "    - Architecture diagram"
echo ""
echo "3️⃣  Tester connexions:"
echo "    - Cloud SQL: $(terraform output -raw sql_connection_command)"
echo "    - BigQuery: bq ls $PROJECT_ID:stripe_olap"
echo ""
echo "4️⃣  ⚠️  DÉTRUIRE ressources après captures:"
echo "    ./destroy.sh"
echo ""

# Créer fichier reminder
cat > .deployment_info <<EOF
DEPLOYMENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
PROJECT_ID=$PROJECT_ID
REGION=$REGION
DESTROY_BEFORE=$(date -d '+3 hours' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v+3H '+%Y-%m-%d %H:%M:%S')
EOF

print_success "Informations de déploiement sauvegardées dans .deployment_info"

# Cleanup
rm -f tfplan

print_header "✅ DÉPLOIEMENT RÉUSSI"
print_warning "N'oubliez pas de détruire les ressources dans les 3 heures !"

exit 0