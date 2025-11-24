#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# STRIPE DATA ARCHITECTURE - DESTRUCTION INFRASTRUCTURE GCP
# ═══════════════════════════════════════════════════════════════════
# Script automatisé de destruction complète des ressources
# ATTENTION : Suppression définitive de toutes les données
# ═══════════════════════════════════════════════════════════════════

set -e
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
    echo -e "${RED}❌ ERREUR: $1${NC}"
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

print_header "VÉRIFICATIONS PRÉ-DESTRUCTION"

# Vérifier Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform n'est pas installé"
    exit 1
fi
print_success "Terraform installé"

# Vérifier état Terraform
if [ ! -f "terraform.tfstate" ]; then
    print_error "Fichier terraform.tfstate introuvable"
    print_info "Aucune infrastructure déployée ou déjà détruite"
    exit 0
fi
print_success "État Terraform trouvé"

# Charger PROJECT_ID depuis état si non fourni
if [ -z "$PROJECT_ID" ]; then
    if [ -f ".deployment_info" ]; then
        source .deployment_info
        print_info "PROJECT_ID chargé depuis .deployment_info: $PROJECT_ID"
    else
        print_error "PROJECT_ID non trouvé. Définissez GCP_PROJECT_ID"
        exit 1
    fi
fi

# ───────────────────────────────────────────────────────────────────
# AFFICHAGE INFORMATIONS DÉPLOIEMENT
# ───────────────────────────────────────────────────────────────────

print_header "INFORMATIONS DÉPLOIEMENT"

if [ -f ".deployment_info" ]; then
    source .deployment_info
    echo "Date de déploiement : $DEPLOYMENT_DATE"
    echo "Projet GCP          : $PROJECT_ID"
    echo "Région              : $REGION"
    echo "Détruire avant      : $DESTROY_BEFORE"
    echo ""
    
    # Calcul durée
    DEPLOY_TS=$(date -d "$DEPLOYMENT_DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$DEPLOYMENT_DATE" +%s)
    NOW_TS=$(date +%s)
    ELAPSED=$((NOW_TS - DEPLOY_TS))
    HOURS=$((ELAPSED / 3600))
    MINUTES=$(((ELAPSED % 3600) / 60))
    
    print_info "Durée écoulée: ${HOURS}h${MINUTES}m"
else
    print_warning "Fichier .deployment_info introuvable"
fi

# ───────────────────────────────────────────────────────────────────
# LISTE DES RESSOURCES
# ───────────────────────────────────────────────────────────────────

print_header "RESSOURCES À DÉTRUIRE"

print_info "Liste des ressources actuelles:"
terraform state list | while read -r resource; do
    echo "  - $resource"
done

RESOURCE_COUNT=$(terraform state list | wc -l)
print_warning "$RESOURCE_COUNT ressources seront détruites"

# ───────────────────────────────────────────────────────────────────
# SAUVEGARDE AVANT DESTRUCTION (optionnelle)
# ───────────────────────────────────────────────────────────────────

print_header "SAUVEGARDE (optionnel)"

echo -n "Voulez-vous sauvegarder les données avant destruction ? (y/N): "
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    print_info "Sauvegarde de l'état Terraform..."
    cp terraform.tfstate "$BACKUP_DIR/terraform.tfstate.backup"
    
    if [ -f "outputs.json" ]; then
        cp outputs.json "$BACKUP_DIR/outputs.json"
    fi
    
    print_success "Sauvegarde créée dans $BACKUP_DIR"
fi

# ───────────────────────────────────────────────────────────────────
# CONFIRMATION DESTRUCTION
# ───────────────────────────────────────────────────────────────────

print_header "CONFIRMATION DESTRUCTION"

print_warning "⚠️  ATTENTION : Cette action est IRRÉVERSIBLE"
print_warning "Toutes les données seront DÉFINITIVEMENT supprimées:"
echo ""
echo "  🗄️  Cloud SQL : Base de données OLTP"
echo "  📊 BigQuery : Dataset et tables OLAP"
echo "  🔥 Firestore : Collections NoSQL"
echo "  💾 Cloud Storage : Bucket et fichiers"
echo "  📨 Pub/Sub : Topics et subscriptions"
echo "  🔐 Secret Manager : Secrets"
echo "  👤 IAM : Service accounts"
echo ""

print_warning "Captures d'écran effectuées ? (pour certification)"
echo -n "Confirmer la DESTRUCTION TOTALE ? Tapez 'DESTROY': "
read -r confirmation

if [ "$confirmation" != "DESTROY" ]; then
    print_info "Destruction annulée par l'utilisateur"
    print_success "Ressources préservées"
    exit 0
fi

# ───────────────────────────────────────────────────────────────────
# DESTRUCTION TERRAFORM
# ───────────────────────────────────────────────────────────────────

print_header "DESTRUCTION EN COURS"

START_TIME=$(date +%s)
print_info "Début: $(date '+%Y-%m-%d %H:%M:%S')"
print_warning "Durée estimée: 5-10 minutes"

# Désactiver protection suppression si présente
export TF_VAR_deletion_protection=false

# Destruction avec auto-approve
if terraform destroy -auto-approve; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    
    print_success "Destruction Terraform terminée en ${MINUTES}m${SECONDS}s"
else
    print_error "Échec de la destruction Terraform"
    print_info "Tentez manuellement: terraform destroy"
    exit 1
fi

# ───────────────────────────────────────────────────────────────────
# NETTOYAGE MANUEL DES RESSOURCES ORPHELINES
# ───────────────────────────────────────────────────────────────────

print_header "NETTOYAGE RESSOURCES ORPHELINES"

print_info "Vérification ressources restantes..."

# Vérifier Cloud SQL
if command -v gcloud &> /dev/null; then
    print_info "Vérification instances Cloud SQL..."
    SQL_INSTANCES=$(gcloud sql instances list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$SQL_INSTANCES" ]; then
        print_warning "Instances Cloud SQL trouvées:"
        echo "$SQL_INSTANCES"
        echo -n "Supprimer manuellement ? (y/N): "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "$SQL_INSTANCES" | while read -r instance; do
                print_info "Suppression $instance..."
                gcloud sql instances delete "$instance" --project="$PROJECT_ID" --quiet || true
            done
        fi
    else
        print_success "Aucune instance Cloud SQL orpheline"
    fi
    
    # Vérifier buckets Cloud Storage
    print_info "Vérification buckets Cloud Storage..."
    BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "gs://${PROJECT_ID}-" || echo "")
    
    if [ -n "$BUCKETS" ]; then
        print_warning "Buckets trouvés:"
        echo "$BUCKETS"
        echo -n "Supprimer contenu et buckets ? (y/N): "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "$BUCKETS" | while read -r bucket; do
                print_info "Suppression $bucket..."
                gsutil -m rm -r "$bucket" 2>/dev/null || true
            done
        fi
    else
        print_success "Aucun bucket orphelin"
    fi
else
    print_warning "gcloud non installé, vérification manuelle impossible"
fi

# ───────────────────────────────────────────────────────────────────
# NETTOYAGE FICHIERS LOCAUX
# ───────────────────────────────────────────────────────────────────

print_header "NETTOYAGE FICHIERS LOCAUX"

print_info "Suppression fichiers temporaires..."

FILES_TO_REMOVE=(
    "terraform.tfstate"
    "terraform.tfstate.backup"
    "terraform.tfvars"
    "outputs.json"
    ".terraform.lock.hcl"
    ".deployment_info"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "  - $file supprimé"
    fi
done

if [ -d ".terraform" ]; then
    rm -rf .terraform
    echo "  - .terraform/ supprimé"
fi

print_success "Fichiers locaux nettoyés"

# ───────────────────────────────────────────────────────────────────
# RAPPORT FINAL
# ───────────────────────────────────────────────────────────────────

print_header "✅ DESTRUCTION TERMINÉE"

echo ""
print_success "Toutes les ressources Terraform ont été détruites"
print_success "Fichiers temporaires supprimés"
echo ""

print_info "Vérification finale recommandée:"
echo "  1. Console GCP: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
echo "  2. Billing: https://console.cloud.google.com/billing?project=$PROJECT_ID"
echo "  3. Script: ./verify_cleanup.sh"
echo ""

print_warning "Si des ressources persistent, supprimez-les manuellement depuis la console"

# Créer rapport de destruction
REPORT_FILE="destruction_report_$(date +%Y%m%d_%H%M%S).txt"
cat > "$REPORT_FILE" <<EOF
═══════════════════════════════════════════════════════════════════
RAPPORT DE DESTRUCTION - STRIPE DATA ARCHITECTURE GCP
═══════════════════════════════════════════════════════════════════

Date destruction    : $(date '+%Y-%m-%d %H:%M:%S')
Projet GCP          : $PROJECT_ID
Ressources détruites: $RESOURCE_COUNT
Durée               : ${MINUTES}m${SECONDS}s

ACTIONS EFFECTUÉES:
✅ Destruction Terraform réussie
✅ Fichiers temporaires supprimés
✅ Rapport généré

VÉRIFICATION:
- Console GCP : https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID
- Billing    : https://console.cloud.google.com/billing?project=$PROJECT_ID

⚠️  Vérifier absence de coûts résiduels dans les 24h

═══════════════════════════════════════════════════════════════════
EOF

print_success "Rapport sauvegardé: $REPORT_FILE"

print_header "🎉 NETTOYAGE COMPLET"

exit 0