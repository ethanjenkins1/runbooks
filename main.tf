main.tf
main.tf
terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.116, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"
}

locals {
  location    = var.location
  environment = var.environment
  identifier  = var.identifier
  tags = {
    scenario = "Infoblox NIOS-X"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "dns-hub-${local.location}-${local.environment}-${local.identifier}-rg"
  location = local.location
  tags     = local.tags
}

resource "azurerm_marketplace_agreement" "infoblox" {
  publisher = "infoblox"
  offer     = "infoblox-bloxone-33"
  plan      = "infoblox-bloxone-33"
  accepted  = true
}

data "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group
}

data "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_virtual_network.vnet.resource_group_name
}

module "keyvault" {
  source              = "Azure/avm-res-keyvault-vault/azurerm"
  version             = "0.10.0"
  name                = module.naming.key_vault.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags

  role_assignments = {
    secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }
}

data "azurerm_key_vault" "kv" {
  name                = module.keyvault.name
  resource_group_name = azurerm_resource_group.this.name
}

data "azurerm_key_vault_secret" "admin_username" {
  name         = "infoblox-admin-username"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "admin_password" {
  name         = "infoblox-admin-password"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "join_token" {
  name         = "infoblox-join-token"
  key_vault_id = data.azurerm_key_vault.kv.id
}

module "loadbalancer" {
  source  = "Azure/avm-res-network-loadbalancer/azurerm"
  version = "0.3.2"

  frontend_ip_configurations = {
    frontend_configuration_1 = {
      name                          = "ilb-frontend"
      subnet_id                     = data.azurerm_subnet.subnet.id
      private_ip_address_allocation = "Static"
      private_ip_address            = var.lb_private_ip
    }
  }
  backend_address_pools = {
    pool_1 = { name = "default-pool" }
  }
  location            = local.location
  name                = module.naming.lb.name_unique
  resource_group_name = azurerm_resource_group.this.name
}

locals {
  infoblox_vms = {
    vm01 = {
      name     = "dns-hub-${local.location}-${local.environment}-${local.identifier}-vm01"
      nic_name = "dns-hub-${local.location}-${local.environment}-${local.identifier}-nic01"
      ipconfig = "dns-hub-${local.location}-${local.environment}-${local.identifier}-ipconfig01"
    }
    vm02 = {
      name     = "dns-hub-${local.location}-${local.environment}-${local.identifier}-vm02"
      nic_name = "dns-hub-${local.location}-${local.environment}-${local.identifier}-nic02"
      ipconfig = "dns-hub-${local.location}-${local.environment}-${local.identifier}-ipconfig02"
    }
  }
  infoblox_image = {
    publisher = "infoblox"
    offer     = "infoblox-bloxone-33"
    sku       = "infoblox-bloxone-33"
    version   = "latest"
  }
  infoblox_plan = {
    name      = "infoblox-bloxone-33"
    publisher = "infoblox"
    product   = "infoblox-bloxone-33"
  }
}

module "infoblox_vms" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.13.2"

  for_each            = local.infoblox_vms
  name                = each.value.name
  resource_group_name = azurerm_resource_group.this.name
  location            = local.location

  network_interfaces = {
    nic_1 = {
      name = each.value.nic_name
      ip_configurations = {
        ipconfig_1 = {
          name                          = each.value.ipconfig
          private_ip_subnet_resource_id = data.azurerm_subnet.subnet.id
          load_balancer_backend_pools = {
            bepool = {
              load_balancer_backend_pool_resource_id = module.loadbalancer.azurerm_lb_backend_address_pool["pool_1"].id
            }
          }
        }
      }
    }
  }

  os_disk = {
    size_gb = var.os_disk_size_gb
  }
  os_type                = "Linux"
  sku_size               = var.vm_size
  source_image_reference = local.infoblox_image
  plan                   = local.infoblox_plan
  admin_username         = data.azurerm_key_vault_secret.admin_username.value
  admin_password         = data.azurerm_key_vault_secret.admin_password.value
  custom_data            = base64encode("#!/bin/bash\necho '${data.azurerm_key_vault_secret.join_token.value}' > /etc/infoblox/join_token.txt")
  tags                   = local.tags

  depends_on = [azurerm_marketplace_agreement.infoblox]
}

variable "location" {
  description = "Azure region for deployment"
  default     = "eastus"
}

variable "environment" {
  description = "Environment code"
  default     = "np"
}

variable "identifier" {
  description = "Workload identifier"
  default     = "infoblox-uddi"
}

variable "vnet_name" {
  description = "Name of the existing VNet"
  type        = string
}

variable "vnet_resource_group" {
  description = "Resource group for the VNet"
  type        = string
}

variable "subnet_name" {
  description = "Name of the existing subnet"
  type        = string
}

variable "lb_private_ip" {
  description = "Private IP for the internal load balancer frontend"
  default     = "10.0.2.4"
}

variable "vm_size" {
  description = "Size of the VM"
  default     = "Standard_F8s_v2"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  default     = 128
}

tfvars
vnet_name           = "your-existing-vnet-name"
vnet_resource_group = "your-vnet-rg"
subnet_name         = "your-subnet"
admin_password      = "P@ssword123!"     # Use a strong value!
join_token          = "YOUR_JOIN_TOKEN"

Ethan Jenkins
Senior Consultant
Retail & Consumer Goods
Industry Solutions Delivery Team
Mobile: 469-775-0711
    
 
