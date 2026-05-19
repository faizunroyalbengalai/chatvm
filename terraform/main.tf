terraform {
  backend "azurerm" {}
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "project_name" {
  type = string
}
variable "azure_region" {
  type    = string
  default = "eastus"
}
variable "azure_db_region" {
  type    = string
  default = ""
}
variable "public_key" {
  type = string
}
variable "vm_size" {
  type = string
  # Wizard-selected SKU comes through here. Empty user input falls back to
  # Standard_B2s (2 vCPU / 4 GB), which is broadly available across Azure
  # regions. We avoid Standard_B1s as a default because it's "free-tier
  # eligible" and frequently capacity-locked in popular regions (eastus,
  # westeurope) with SkuNotAvailable / 409 Conflict.
  default = "Standard_B2s"
}
variable "admin_username" {
  type    = string
  default = "ubuntu"
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-rg"
  location = var.azure_region
  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.project_name}-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.project_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}


resource "azurerm_public_ip" "pip" {
  name                = "${var.project_name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "http"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "https"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "app"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.project_name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "${var.project_name}-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.nic.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    Name      = var.project_name
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
output "vm_id" {
  value = azurerm_linux_virtual_machine.vm.id
}
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}
