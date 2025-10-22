# Terraform Configuration for Stripe Data Architecture

# Azure Provider Configuration

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45.0"
    }
  }
  
  # Backend pour stocker le state Terraform (optionnel mais recommandé)
  backend "azurerm" {
    resource_group_name  = "stripe-terraform-state-rg"
    storage_account_name = "stripetfstate"
    container_name       = "tfstate"
    key                  = "stripe-data-architecture.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    
  }
  
  # Les credentials sont gérées via Azure CLI ou Service Principal
  # az login --tenant TENANT_ID
  # export ARM_SUBSCRIPTION_ID="..."
  # export ARM_CLIENT_ID="..."
  # export ARM_CLIENT_SECRET="..."
  # export ARM_TENANT_ID="..."
}

provider "azuread" {
  # Utilisé pour créer les Managed Identities et RBAC
}

provider "random" {
  # Utilisé pour générer des mots de passe aléatoires
}