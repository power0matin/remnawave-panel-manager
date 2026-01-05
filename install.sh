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

# ---------- Interactive input (works even when stdin is piped) ----------
TTY_FD=0
if [[ -r /dev/tty ]]; then
  exec 3</dev/tty
  TTY_FD=3
fi

read_i() {
  local prompt="$1"
  local var="$2"

  if [[ "${TTY_FD}" -ne 0 ]]; then
    read -r -u "${TTY_FD}" -p "${prompt}" "${var}"
  else
    read -r -p "${prompt}" "${var}"
  fi
}

pause() {
  # Never fail hard on pause
  read_i "Press Enter to continue..." _ || true
}

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR ]${NC} $*"; }

die() { log_err "$*"; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root. Use one of these:\n  curl -fsSL ${RAW_BASE}/install.sh | sudo bash\n  curl -fsSL ${RAW_BASE}/install.sh -o /tmp/remnawave-install.sh && sudo bash /tmp/remnawave-install.sh"
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

  run_manager() {
    if [[ "${TTY_FD}" -ne 0 ]]; then
      bash "${manager}" "$@" <&${TTY_FD}
    else
      bash "${manager}" "$@"
    fi
  }

  # If user passed arguments, directly forward to manager (advanced usage)
  # Example:
  # curl -fsSL .../install.sh | sudo bash -s -- install-panel --domain panel.example.com --email admin@example.com
  if [[ $# -gt 0 ]]; then
    run_manager "$@"
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
    if ! read_i "Enter choice [1-8]: " choice; then
      die "Interactive mode requires a TTY. Try direct mode:\n  curl -fsSL ${RAW_BASE}/install.sh | sudo bash -s -- install-panel --domain panel.example.com --email admin@example.com"
    fi

    case "${choice}" in
      1)
        if ! read_i "Enter your Domain (e.g., panel.example.com): " domain; then
          die "No interactive input available."
        fi
        [[ -n "${domain}" ]] || die "Domain cannot be empty."

        if ! read_i "Enter email for TLS (optional, recommended): " email; then
          die "No interactive input available."
        fi

        if [[ -n "${email}" ]]; then
          run_manager install-panel --domain "${domain}" --email "${email}"
        else
          run_manager install-panel --domain "${domain}"
        fi

        pause
        ;;
      2)
        run_manager install-node
        pause
        ;;
      3)
        run_manager uninstall-panel
        pause
        ;;
      4)
        run_manager uninstall-node
        pause
        ;;
      5)
        run_manager status
        pause
        ;;
      6)
        run_manager logs --panel --tail 200
        pause
        ;;
      7)
        run_manager update --panel
        pause
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
