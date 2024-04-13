#!/bin/bash

set -e

export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPPORTED=false

# Function to update the system based on the detected OS
update_system() {
    case "$OS" in
        debian|ubuntu)
            echo "Updating Debian/Ubuntu system..."
            sudo apt-get update && sudo apt-get upgrade -y
            ;;
        centos)
            echo "Updating CentOS system..."
            sudo yum update -y
            ;;
        *)
            echo "Unsupported distribution. Please update manually."
            exit 1
            ;;
    esac
}

# Function to install Docker
install_docker() {
    case "$OS" in
        debian|ubuntu)
            echo "Installing Docker on Debian/Ubuntu system..."
            export DEBIAN_FRONTEND=noninteractive
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rocky|almalinux)
            echo "Installing Docker on CentOS/RHEL system..."
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            echo "Unsupported distribution. Docker installation not supported."
            exit 1
            ;;
    esac
}

enable_and_start_docker() {
    echo "Enabling and starting Docker service..."
    sudo systemctl enable docker
    sudo systemctl start docker
}

# Function to configure firewall
configure_firewall() {
    case "$OS" in
        debian|ubuntu)
            echo "Configuring firewall for Debian/Ubuntu system..."
            sudo ufw allow 80/tcp
            sudo ufw allow 443/tcp
            sudo ufw enable
            ;;
        centos|rocky|almalinux)
            echo "Configuring firewall for CentOS/RHEL system..."
            sudo firewall-cmd --permanent --add-port=80/tcp
            sudo firewall-cmd --permanent --add-port=443/tcp
            sudo firewall-cmd --no-reload
            ;;
        *)
            echo "Unsupported distribution. Firewall configuration not supported."
            exit 1
            ;;
    esac
}

if [[ $EUID -ne 0 ]]; then
  error "This script must be executed with root privileges."
  exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
  # freedesktop.org and systemd
  . /etc/os-release
  OS=$(echo "$ID" | awk '{print tolower($0)}')
  OS_VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
  # linuxbase.org
  OS=$(lsb_release -si | awk '{print tolower($0)}')
  OS_VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
  # For some versions of Debian/Ubuntu without lsb_release command
  . /etc/lsb-release
  OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
  OS_VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
  # Older Debian/Ubuntu/etc.
  OS="debian"
  OS_VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
  # Older SuSE/etc.
  OS="SuSE"
  OS_VER="?"
elif [ -f /etc/redhat-release ]; then
  # Older Red Hat, CentOS, etc.
  OS="CentOS"
  OS_VER="?"
else
  # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
  OS=$(uname -s)
  OS_VER=$(uname -r)
fi

OS=$(echo "$OS" | awk '{print tolower($0)}')
OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
CPU_ARCHITECTURE=$(uname -m)

case "$CPU_ARCHITECTURE" in
x86_64)
  ARCH=amd64
  ;;
arm64 | aarch64)
  ARCH=arm64
  ;;
*)
  error "Only x86_64 and arm64 are supported!"
  exit 1
  ;;
esac

case "$OS" in
    ubuntu)
        case "$OS_VER_MAJOR" in
            16|18|20|22)
                SUPPORTED=true
                ;;
            *)
                SUPPORTED=false
                ;;
        esac
        ;;
    debian)
        case "$OS_VER_MAJOR" in
            8|9|10|11|12)
                SUPPORTED=true
                ;;
            *)
                SUPPORTED=false
                ;;
        esac
        ;;
    centos)
        case "$OS_VER_MAJOR" in
            7|8)
                SUPPORTED=true
                ;;
            *)
                SUPPORTED=false
                ;;
        esac
        ;;
    rocky)
        case "$OS_VER_MAJOR" in
            8|9)
                SUPPORTED=true
                ;;
            *)
                SUPPORTED=false
                ;;
        esac
        ;;
    almalinux)
        case "$OS_VER_MAJOR" in
            8|9)
                SUPPORTED=true
                ;;
            *)
                SUPPORTED=false
                ;;
        esac
        ;;
    *)
        SUPPORTED=false
        ;;
esac

# exit if not supported
if [ "$SUPPORTED" == false ]; then
  output "$OS $OS_VER is not supported"
  error "Unsupported OS"
  exit 1
fi


if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."
    install_docker
else
    echo "Docker is already installed."
fi

enable_and_start_docker

configure_firewall

update_system