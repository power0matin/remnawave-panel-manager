#!/usr/bin/env bash
# Remnawave Panel Manager - One-liner installer (bootstrap)
# Author: Matin Shahabadi (@power0matin)
# License: MIT

set -Eeuo pipefail
IFS=$'\n\t'

# Defaults (change these if you rename repo or branch)
REPO_OWNER="${REPO_OWNER:-power0matin}"
REPO_NAME="${REPO_NAME:-remnawave-panel-manager}"
BRANCH="${BRANCH:-main}"

RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
MANAGER_URL="${RAW_BASE}/remnawave-manager.sh"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR ]${NC} $*"; }

die() { log_err "$*"; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root. Use:\n  sudo bash <(curl -Ls ${RAW_BASE}/install.sh)"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

download_manager() {
  local tmp
  tmp="$(mktemp -t remnawave-manager.XXXXXX)"
  log_info "Downloading manager: ${MANAGER_URL}"
  curl -fsSL "${MANAGER_URL}" -o "${tmp}"
  chmod +x "${tmp}"
  echo "${tmp}"
}

show_header() {
  clear || true
  echo -e "${RED}==========================================================${NC}"
  echo -e "${YELLOW}      Remnawave Panel Manager - Quick Installer           ${NC}"
  echo -e "${RED}==========================================================${NC}"
  echo -e "${BLUE} Repo: https://github.com/${REPO_OWNER}/${REPO_NAME}      ${NC}"
  echo -e "${RED}==========================================================${NC}"
  echo ""
}

main() {
  need_cmd curl
  require_root

  local manager
  manager="$(download_manager)"

  # If user passed arguments, directly forward to manager (advanced usage)
  # Example:
  # sudo bash <(curl -Ls .../install.sh) install-panel --domain panel.example.com --email admin@example.com
  if [[ $# -gt 0 ]]; then
    bash "${manager}" "$@"
    exit 0
  fi

  while true; do
    show_header
    echo "Select an option:"
    echo "1) Install Panel (Main Server + Caddy HTTPS)"
    echo "2) Install Node (On this server)"
    echo "3) Uninstall Panel (Delete everything)"
    echo "4) Uninstall Node (Delete node only)"
    echo "5) Status (Panel/Node)"
    echo "6) Logs (Panel)"
    echo "7) Update (Panel)"
    echo "8) Exit"
    echo ""
    read -r -p "Enter choice [1-8]: " choice

    case "${choice}" in
      1)
        read -r -p "Enter your Domain (e.g., panel.example.com): " domain
        [[ -n "${domain}" ]] || die "Domain cannot be empty."
        read -r -p "Enter email for TLS (optional, recommended): " email

        if [[ -n "${email}" ]]; then
          bash "${manager}" install-panel --domain "${domain}" --email "${email}"
        else
          bash "${manager}" install-panel --domain "${domain}"
        fi

        read -r -p "Press Enter to continue..." _
        ;;
      2)
        bash "${manager}" install-node
        read -r -p "Press Enter to continue..." _
        ;;
      3)
        bash "${manager}" uninstall-panel
        read -r -p "Press Enter to continue..." _
        ;;
      4)
        bash "${manager}" uninstall-node
        read -r -p "Press Enter to continue..." _
        ;;
      5)
        bash "${manager}" status
        read -r -p "Press Enter to continue..." _
        ;;
      6)
        bash "${manager}" logs --panel --tail 200
        read -r -p "Press Enter to continue..." _
        ;;
      7)
        bash "${manager}" update --panel
        read -r -p "Press Enter to continue..." _
        ;;
      8)
        log_ok "Bye."
        exit 0
        ;;
      *)
        log_warn "Invalid option."
        sleep 1
        ;;
    esac
  done
}

main "$@"
