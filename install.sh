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
  local var_name="$2"

  # Validate var name to avoid unexpected behavior
  if [[ ! "${var_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    die "Internal error: invalid variable name '${var_name}'"
  fi

  # Bash nameref: write into the caller-provided variable
  local -n out="${var_name}"

  if [[ "${TTY_FD}" -ne 0 ]]; then
    read -r -u "${TTY_FD}" -p "${prompt}" out
  else
    read -r -p "${prompt}" out
  fi
}

pause_msg() {
  local msg="${1:-Press Enter to return to menu...}"
  echo ""
  echo -e "${YELLOW}${msg}${NC}"
  read_i "" _ || true
}

# Run an action and ALWAYS return to menu (never exit on failure)
run_action() {
  local title="$1"; shift

  show_header
  echo -e "${BLUE}[ACTION]${NC} ${title}"
  echo ""

  # Prevent set -e from killing the menu loop
  local rc=0
  if run_manager "$@"; then
    log_ok "Done: ${title}"
  else
    rc=$?
    log_err "Failed (${rc}): ${title}"
  fi

  pause_msg "Press Enter to return to menu..."
  return 0
}

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_err()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }

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
  local tmp retries=3 n=1
  tmp="$(mktemp -t remnawave-manager.XXXXXX)"

  while true; do
    log_info "Downloading manager (${n}/${retries})..."
    if curl -fsSL "${MANAGER_URL}" -o "${tmp}"; then
      break
    fi

    if (( n >= retries )); then
      rm -f "${tmp}" || true
      die "Failed to download manager. Check network/DNS and try again."
    fi

    n=$((n+1))
    sleep 1
  done

  if [[ ! -s "${tmp}" ]]; then
    rm -f "${tmp}" || true
    die "Downloaded manager is empty. Please try again."
  fi

  chmod +x "${tmp}"
  echo "${tmp}"  # IMPORTANT: only output path on stdout
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
IN_MENU="false"

on_int() {
  # If user hits Ctrl+C, do not exit; just return to menu
  if [[ "${IN_MENU}" == "true" ]]; then
    echo ""
    log_warn "Interrupted. Returning to menu..."
    sleep 1
    return 0
  fi

  # If not in menu (e.g., direct mode), exit with standard code
  echo ""
  log_warn "Interrupted."
  exit 130
}
trap on_int INT

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

  # Predeclare interactive vars to satisfy ShellCheck (and keep -u safe)
  local choice="" domain="" email=""

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
      if [[ "${TTY_FD}" -ne 0 ]]; then
        log_warn "No input received. Returning to menu..."
        sleep 1
        continue
      fi

      log_err "Interactive mode requires a TTY."
      echo "Try direct mode:"
      echo "  curl -fsSL ${RAW_BASE}/install.sh | sudo bash -s -- status"
      echo "  curl -fsSL ${RAW_BASE}/install.sh | sudo bash -s -- install-panel --domain panel.example.com --email admin@example.com"
      exit 2
    fi

    case "${choice}" in
      1)
        if ! read_i "Enter your Domain (e.g., panel.example.com): " domain; then
          log_err "No interactive input available."
          pause_msg
          continue
        fi

        if [[ -z "${domain}" ]]; then
          log_warn "Domain cannot be empty."
          pause_msg
          continue
        fi
        if ! read_i "Enter email for TLS (optional, recommended): " email; then
          die "No interactive input available."
        fi

        if [[ -n "${email}" ]]; then
          IN_MENU="true"
          run_action "Install Panel for ${domain}" install-panel --domain "${domain}" --email "${email}"
        else
          IN_MENU="true"
          run_action "Install Panel for ${domain}" install-panel --domain "${domain}"
        fi
        ;;
      2)
        IN_MENU="true"
        run_action "Install Node (On this server)" install-node
        ;;
      3)
        IN_MENU="true"
        run_action "Uninstall Panel (Delete everything)" uninstall-panel
        ;;
      4)
        IN_MENU="true"
        run_action "Uninstall Node (Delete node only)" uninstall-node
        ;;
      5)
        IN_MENU="true"
        run_action "Status (Panel/Node)" status
        ;;
      6)
        IN_MENU="true"
        run_action "Panel Logs (tail 200)" logs --panel --tail 200
        ;;
      7)
        IN_MENU="true"
        run_action "Update Panel (pull images + recreate)" update --panel
        ;;
      8)
        log_ok "Bye."
        exit 0
        ;;
      *)
        log_warn "Invalid option: ${choice}"
        pause_msg "Press Enter to return to menu..."
        ;;
    esac
  done
}

main "$@"
