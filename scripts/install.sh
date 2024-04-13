#!/bin/bash

set -e

export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPPORTED=false

update_repos() {
  local args=""
  [[ $1 == true ]] && args="-qq"
  case "$OS" in
  ubuntu | debian)
    apt-get -y $args update
    ;;
  *)
    # Do nothing as AlmaLinux and RockyLinux update metadata before installing packages.
    ;;
  esac
}

# First argument list of packages to install, second argument for quite mode
install_packages() {
  local args=""
  if [[ $2 == true ]]; then
    case "$OS" in
    ubuntu | debian) args="-qq" ;;
    *) args="-q" ;;
    esac
  fi

  # Eval needed for proper expansion of arguments
  case "$OS" in
  ubuntu | debian)
    eval apt-get -y $args install "$1"
    ;;
  centos | rocky | almalinux)
    eval dnf -y $args install "$1"
    ;;
  esac
}

install_firewall() {
  case "$OS" in
  ubuntu | debian)
    output ""
    output "Installing Uncomplicated Firewall (UFW)"

    if ! [ -x "$(command -v ufw)" ]; then
      update_repos true
      install_packages "ufw" true
    fi

    ufw --force enable

    success "Enabled Uncomplicated Firewall (UFW)"

    ;;
  centos | rocky | almalinux)

    output ""
    output "Installing FirewallD"+

    if ! [ -x "$(command -v firewall-cmd)" ]; then
      install_packages "firewalld" true
    fi

    systemctl --now enable firewalld >/dev/null

    success "Enabled FirewallD"

    ;;
  esac
}

firewall_allow_ports() {
  case "$OS" in
  ubuntu | debian)
    for port in $1; do
      ufw allow "$port"
    done
    ufw --force reload
    ;;
  centos | rocky | almalinux)
    for port in $1; do
      firewall-cmd --zone=public --add-port="$port"/tcp --permanent
    done
    firewall-cmd --reload -q
    ;;
  esac
}

enable_services() {
  systemctl start docker
  systemctl enable docker
}

dep_install() {
  output "Installing dependencies for $OS $OS_VER..."

  install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    install_packages "gnupg lsb-release"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;

  centos | rocky | almalinux)
    install_packages "dnf-utils"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  # Update the new repos
  update_repos

  # Install dependencies
  install_packages "docker-ce docker-ce-cli containerd.io"

  enable_services

  success "Dependencies installed!"
}

firewall_ports() {
  output "Opening port 22 (SSH), 443 (FTP) in the firewall"

  firewall_allow_ports "22 443"

  success "Firewall ports opened!"
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


perform_install() {
  output "Installing Embermanager"
  dep_install

  return 0
}

perform_install
