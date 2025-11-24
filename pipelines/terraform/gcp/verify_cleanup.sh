#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# STRIPE DATA ARCHITECTURE - VÉRIFICATION NETTOYAGE GCP
# ═══════════════════════════════════════════════════════════════════
# Script de vérification complète après destruction
# Détecte ressources orphelines et coûts potentiels
# ═══════════════════════════════════════════════════════════════════

set -u

# ───────────────────────────────────────────────────────────────────
# CONFIGURATION
# ───────────────────────────────────────────────────────────────────

PROJECT_ID="${GCP_PROJECT_ID:-}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ───────────────────────────────────────────────────────────────────
# FONCTIONS
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
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATIONS
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION ENVIRONNEMENT"

# Vérifier gcloud
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI non installé"
    exit 1
fi
print_success "gcloud CLI installé"

# Vérifier PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    print_warning "Variable GCP_PROJECT_ID non définie"
    echo -n "Entrez l'ID du projet GCP: "
    read PROJECT_ID
fi

# Vérifier authentification
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    print_error "Pas de compte gcloud actif"
    print_info "Exécutez: gcloud auth login"
    exit 1
fi

CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
print_success "Connecté: $CURRENT_ACCOUNT"

# Définir projet
gcloud config set project "$PROJECT_ID" --quiet
print_success "Projet: $PROJECT_ID"

# ───────────────────────────────────────────────────────────────────
# COMPTEURS
# ───────────────────────────────────────────────────────────────────

ISSUES_FOUND=0
WARNINGS_FOUND=0

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION CLOUD SQL
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION CLOUD SQL"

print_info "Recherche instances Cloud SQL..."
SQL_INSTANCES=$(gcloud sql instances list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null)

if [ -n "$SQL_INSTANCES" ]; then
    print_error "Instances Cloud SQL trouvées:"
    echo "$SQL_INSTANCES" | while read -r instance; do
        echo "  🗄️  $instance"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    done
    print_warning "Coût potentiel: ~8-10 USD/mois par instance"
else
    print_success "Aucune instance Cloud SQL"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION BIGQUERY
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION BIGQUERY"

print_info "Recherche datasets BigQuery..."
BQ_DATASETS=$(bq ls --project_id="$PROJECT_ID" --format=json 2>/dev/null | jq -r '.[].datasetReference.datasetId' 2>/dev/null || echo "")

if [ -n "$BQ_DATASETS" ]; then
    print_warning "Datasets BigQuery trouvés:"
    echo "$BQ_DATASETS" | while read -r dataset; do
        echo "  📊 $dataset"
        
        # Vérifier taille
        TABLES=$(bq ls --project_id="$PROJECT_ID" "$dataset" --format=json 2>/dev/null | jq -r '.[].id' 2>/dev/null || echo "")
        if [ -n "$TABLES" ]; then
            echo "$TABLES" | while read -r table; do
                echo "     └─ $table"
            done
        fi
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    done
    print_info "BigQuery facture le stockage à ~0.02 USD/GB/mois"
else
    print_success "Aucun dataset BigQuery"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION FIRESTORE
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION FIRESTORE"

print_info "Recherche bases Firestore..."
FIRESTORE_DBS=$(gcloud firestore databases list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")

if [ -n "$FIRESTORE_DBS" ]; then
    print_warning "Bases Firestore trouvées:"
    echo "$FIRESTORE_DBS" | while read -r db; do
        echo "  🔥 $db"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    done
    print_info "Firestore gratuit jusqu'à 1GB + 50K lectures/jour"
else
    print_success "Aucune base Firestore (ou API désactivée)"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION CLOUD STORAGE
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION CLOUD STORAGE"

print_info "Recherche buckets Cloud Storage..."
BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null || echo "")

if [ -n "$BUCKETS" ]; then
    print_error "Buckets trouvés:"
    echo "$BUCKETS" | while read -r bucket; do
        BUCKET_NAME=$(echo "$bucket" | sed 's|gs://||' | sed 's|/||')
        SIZE=$(gsutil du -s "$bucket" 2>/dev/null | awk '{print $1}')
        SIZE_MB=$((SIZE / 1024 / 1024))
        
        echo "  💾 $BUCKET_NAME (${SIZE_MB}MB)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    done
    print_warning "Coût: ~0.02 USD/GB/mois"
else
    print_success "Aucun bucket Cloud Storage"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION PUB/SUB
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION PUB/SUB"

print_info "Recherche topics Pub/Sub..."
PUBSUB_TOPICS=$(gcloud pubsub topics list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")

if [ -n "$PUBSUB_TOPICS" ]; then
    print_warning "Topics Pub/Sub trouvés:"
    echo "$PUBSUB_TOPICS" | while read -r topic; do
        echo "  📨 $topic"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    done
    print_info "Pub/Sub gratuit jusqu'à 10GB/mois"
else
    print_success "Aucun topic Pub/Sub"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION SECRET MANAGER
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION SECRET MANAGER"

print_info "Recherche secrets..."
SECRETS=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")

if [ -n "$SECRETS" ]; then
    print_warning "Secrets trouvés:"
    echo "$SECRETS" | while read -r secret; do
        echo "  🔐 $secret"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    done
    print_info "Secret Manager: 6 secrets gratuits/mois"
else
    print_success "Aucun secret"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION SERVICE ACCOUNTS
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION SERVICE ACCOUNTS"

print_info "Recherche service accounts personnalisés..."
SERVICE_ACCOUNTS=$(gcloud iam service-accounts list --project="$PROJECT_ID" \
    --filter="email:stripe-data*" --format="value(email)" 2>/dev/null || echo "")

if [ -n "$SERVICE_ACCOUNTS" ]; then
    print_warning "Service accounts trouvés:"
    echo "$SERVICE_ACCOUNTS" | while read -r sa; do
        echo "  👤 $sa"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    done
else
    print_success "Aucun service account personnalisé"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION COMPUTE ENGINE
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION COMPUTE ENGINE"

print_info "Recherche instances VM..."
VM_INSTANCES=$(gcloud compute instances list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")

if [ -n "$VM_INSTANCES" ]; then
    print_error "Instances VM trouvées:"
    echo "$VM_INSTANCES" | while read -r vm; do
        echo "  💻 $vm"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    done
    print_warning "Coût: ~24 USD/mois par VM f1-micro"
else
    print_success "Aucune instance VM"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION DISQUES PERSISTANTS
# ───────────────────────────────────────────────────────────────────

print_info "Recherche disques persistants..."
DISKS=$(gcloud compute disks list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")

if [ -n "$DISKS" ]; then
    print_warning "Disques persistants trouvés:"
    echo "$DISKS" | while read -r disk; do
        echo "  💿 $disk"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    done
else
    print_success "Aucun disque persistant"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION APIs ACTIVES
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION APIs ACTIVES"

print_info "Liste des APIs coûteuses activées..."
EXPENSIVE_APIS=$(gcloud services list --enabled --project="$PROJECT_ID" \
    --filter="name:compute OR name:sql OR name:container" \
    --format="value(config.name)" 2>/dev/null || echo "")

if [ -n "$EXPENSIVE_APIS" ]; then
    print_warning "APIs potentiellement coûteuses:"
    echo "$EXPENSIVE_APIS" | while read -r api; do
        echo "  🔌 $api"
    done
else
    print_success "Aucune API coûteuse active"
fi

# ───────────────────────────────────────────────────────────────────
# VÉRIFICATION BILLING
# ───────────────────────────────────────────────────────────────────

print_header "VÉRIFICATION FACTURATION"

print_info "Vérification compte de facturation..."
BILLING_ACCOUNT=$(gcloud beta billing projects describe "$PROJECT_ID" \
    --format="value(billingAccountName)" 2>/dev/null || echo "")

if [ -n "$BILLING_ACCOUNT" ]; then
    print_info "Compte de facturation: $BILLING_ACCOUNT"
    print_warning "Consultez: https://console.cloud.google.com/billing?project=$PROJECT_ID"
else
    print_success "Aucun compte de facturation lié"
fi

# ───────────────────────────────────────────────────────────────────
# RAPPORT FINAL
# ───────────────────────────────────────────────────────────────────

print_header "RAPPORT DE VÉRIFICATION"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  RÉSUMÉ                                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
    print_success "✨ NETTOYAGE PARFAIT"
    echo "  Aucune ressource facturée trouvée"
    echo "  Aucun avertissement"
    echo ""
    print_success "Coût estimé: 0 USD/mois"
elif [ $ISSUES_FOUND -eq 0 ]; then
    print_success "✅ NETTOYAGE CORRECT"
    echo "  Aucune ressource critique"
    echo "  $WARNINGS_FOUND avertissements mineurs"
    echo ""
    print_info "Coût estimé: < 1 USD/mois"
else
    print_error "⚠️  RESSOURCES RESTANTES"
    echo "  $ISSUES_FOUND ressources facturées trouvées"
    echo "  $WARNINGS_FOUND avertissements"
    echo ""
    print_warning "Coût potentiel: 10-50 USD/mois"
    echo ""
    print_error "ACTION REQUISE: Supprimer manuellement ces ressources"
fi

echo ""
echo "LIENS UTILES:"
echo "  📊 Dashboard: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
echo "  💰 Billing: https://console.cloud.google.com/billing?project=$PROJECT_ID"
echo "  📈 Cost Table: https://console.cloud.google.com/billing/costTable?project=$PROJECT_ID"
echo ""

# Créer rapport JSON
REPORT_FILE="cleanup_report_$(date +%Y%m%d_%H%M%S).json"
cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "project_id": "$PROJECT_ID",
  "issues_found": $ISSUES_FOUND,
  "warnings_found": $WARNINGS_FOUND,
  "status": "$([ $ISSUES_FOUND -eq 0 ] && echo "clean" || echo "needs_action")"
}
EOF

print_success "Rapport sauvegardé: $REPORT_FILE"

# Code de sortie
if [ $ISSUES_FOUND -gt 0 ]; then
    exit 1
else
    exit 0
fi