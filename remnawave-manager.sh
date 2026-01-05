#!/usr/bin/env bash
# Remnawave Panel & Node - Production-grade Installer/Manager
# Author: Matin Shahabadi (@power0matin)
# License: MIT
#
# Notes:
# - Designed for Debian/Ubuntu (APT-based) servers
# - Uses Docker + Docker Compose plugin + Caddy for automatic HTTPS
# - Idempotent where possible, with safe prompts

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0.0"

# ---------- Colors (safe fallback) ----------
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  BOLD="$(tput bold)"
  NC="$(tput sgr0)"
else
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'
  BOLD=""
  NC=$'\033[0m'
fi

# ---------- Paths ----------
PANEL_DIR="/opt/remnawave"
NODE_DIR="/opt/remnawave-node"

# ---------- Logging ----------
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERR ]${NC} $*"; }

die() { log_error "$*"; exit 1; }

on_error() {
  local exit_code=$?
  local line_no=$1
  log_error "Failed at line ${line_no}. Exit code: ${exit_code}"
  log_error "Tip: Run with 'bash -x ./remnawave-manager.sh ...' for debugging."
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

# ---------- Helpers ----------
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root (use: sudo $0 ...)"
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

rand_hex() {
  local bytes="${1:-32}"
  if has_cmd openssl; then
    openssl rand -hex "$bytes"
  else
    # fallback: /dev/urandom
    head -c "$bytes" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}
require_docker_or_die() {
  if ! has_cmd docker; then
    die "Docker is not installed. Run: $0 install-panel (or install Docker first)."
  fi

  # Compose v2 plugin OR docker-compose v1
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi
  if has_cmd docker-compose; then
    return 0
  fi

  die "Docker Compose not found. Install docker compose plugin or docker-compose."
}

confirm() {
  local prompt="${1:-Are you sure?}"
  local default_no="${2:-true}" # true => default is No
  local ans
  if [[ "${default_no}" == "true" ]]; then
    read -r -p "${prompt} [y/N]: " ans
    [[ "${ans}" == "y" || "${ans}" == "Y" ]]
  else
    read -r -p "${prompt} [Y/n]: " ans
    [[ -z "${ans}" || "${ans}" == "y" || "${ans}" == "Y" ]]
  fi
}

usage() {
  cat <<EOF
${BOLD}Remnawave Manager${NC} v${VERSION}

Usage:
  $0 install-panel   --domain panel.example.com [--email you@example.com]
  $0 uninstall-panel [--yes]
  $0 install-node
  $0 uninstall-node  [--yes]
  $0 status
  $0 logs            [--panel|--node] [--tail 200]
  $0 update          [--panel|--node]
  $0 backup          [--panel|--node] [--out /root/backup.tgz]

Examples:
  sudo $0 install-panel --domain panel.example.com --email admin@example.com
  sudo $0 status
  sudo $0 update --panel

Notes:
  - Debian/Ubuntu only (APT-based).
  - Requires ports 80/443 open for Caddy HTTPS.
  - Optional env vars:
      DOCKER_INSTALL_METHOD=auto|official|ubuntu
      DOCKER_REGISTRY_MIRROR=https://mirror.example.com
      RMNW_BACKEND_IMAGE=...
      RMNW_POSTGRES_IMAGE=...
      RMNW_VALKEY_IMAGE=...
      RMNW_CADDY_IMAGE=...
EOF
}

detect_apt_based() {
  [[ -f /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID_LIKE:-}" == *"debian"* || "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" ]]
}

apt_install() {
  local pkgs=("$@")
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends "${pkgs[@]}"
}

docker_compose() {
  # Prefer Docker Compose v2 plugin: `docker compose`
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif has_cmd docker-compose; then
    docker-compose "$@"
  else
    die "Docker Compose not found. Install docker compose plugin."
  fi
}
# --- run a command without killing the script via ERR trap (we handle rc manually)
run_soft() {
  local rc=0
  trap - ERR
  set +e
  "$@"
  rc=$?
  set -e
  trap 'on_error $LINENO' ERR
  return "$rc"
}
configure_docker_registry_mirror() {
  # Optional: configure a Docker registry mirror to bypass Docker Hub restrictions.
  # User provides DOCKER_REGISTRY_MIRROR, e.g. https://mirror.example.com
  local mirror="${DOCKER_REGISTRY_MIRROR:-}"
  [[ -n "${mirror}" ]] || return 0

  mkdir -p /etc/docker
  local daemon="/etc/docker/daemon.json"

  if [[ -f "${daemon}" ]]; then
    if grep -q '"registry-mirrors"' "${daemon}"; then
      log_ok "Docker registry mirror already configured in ${daemon}."
      return 0
    fi
    log_warn "Found existing ${daemon}; not modifying automatically."
    log_warn "To add a mirror, update it manually and restart Docker."
    log_warn "Suggested JSON: {\"registry-mirrors\": [\"${mirror}\"]}"
    return 0
  fi

  cat >"${daemon}" <<EOF
{
  "registry-mirrors": ["${mirror}"]
}
EOF

  systemctl restart docker >/dev/null 2>&1 || true
  log_ok "Configured Docker registry mirror: ${mirror}"
}

cleanup_docker_repo() {
  # Remove stale/broken Docker repo configs that can break apt-get update globally
  rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker-ce.list >/dev/null 2>&1 || true
  rm -f /etc/apt/keyrings/docker.gpg >/dev/null 2>&1 || true
}

install_docker_ubuntu_fallback() {
  log_warn "Docker CE repo is not reachable (or blocked). Falling back to Ubuntu packages (docker.io)."
  export DEBIAN_FRONTEND=noninteractive

  apt-get update -y
  apt-get install -y --no-install-recommends docker.io

  systemctl enable --now docker >/dev/null 2>&1 || true

  # Optional: configure mirror (safe behavior if daemon.json already exists)
  configure_docker_registry_mirror

  # Prefer compose v2 package if available; fallback to v1
  if ! docker compose version >/dev/null 2>&1; then
    if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
      apt-get install -y --no-install-recommends docker-compose-v2 || true
    fi
  fi

  if ! docker compose version >/dev/null 2>&1 && ! has_cmd docker-compose; then
    apt-get install -y --no-install-recommends docker-compose
  fi

  log_ok "Docker installed via Ubuntu repository."
  log_warn "Compose support: docker compose (v2) or docker-compose (v1) is supported by this script."
}

install_docker() {
  if has_cmd docker && (docker compose version >/dev/null 2>&1 || has_cmd docker-compose); then
    log_ok "Docker & Compose are already installed."
    return
  fi

  detect_apt_based || die "Unsupported OS. This script supports Debian/Ubuntu (APT-based) only."

  local method="${DOCKER_INSTALL_METHOD:-auto}" # auto|official|ubuntu
  case "${method}" in
    auto|official|ubuntu) ;;
    *) die "Invalid DOCKER_INSTALL_METHOD='${method}'. Use: auto|official|ubuntu" ;;
  esac

  if [[ "${method}" == "ubuntu" ]]; then
    log_info "Installing Docker (Ubuntu repository method)..."
    install_docker_ubuntu_fallback
    return
  fi

  # If previous attempts left a broken docker repo, it can break apt-get update entirely.
  cleanup_docker_repo

  log_info "Installing Docker (official repository method)..."
  apt_install ca-certificates curl gnupg lsb-release

  local os_id arch codename
  # shellcheck disable=SC1091
  . /etc/os-release
  os_id="${ID}"
  arch="$(dpkg --print-architecture)"
  codename="$(lsb_release -cs)"

  install -m 0755 -d /etc/apt/keyrings

  # --- Fetch Docker GPG key (always rebuild to avoid stale/empty key files) ---
  local gpg_url="https://download.docker.com/linux/${os_id}/gpg"
  local tmpkey
  tmpkey="$(mktemp -t docker-gpg.XXXXXX)"

  if ! run_soft curl -4 -fsSL "${gpg_url}" -o "${tmpkey}"; then
    run_soft curl -fsSL "${gpg_url}" -o "${tmpkey}" || true
  fi

  if [[ ! -s "${tmpkey}" ]]; then
    rm -f "${tmpkey}" || true
    if [[ "${method}" == "official" ]]; then
      die "Failed to fetch Docker GPG key (empty/blocked). Your network may restrict download.docker.com."
    fi
    install_docker_ubuntu_fallback
    return
  fi

  if ! run_soft gpg --dearmor -o /etc/apt/keyrings/docker.gpg "${tmpkey}"; then
    rm -f "${tmpkey}" || true
    rm -f /etc/apt/keyrings/docker.gpg >/dev/null 2>&1 || true
    if [[ "${method}" == "official" ]]; then
      die "Failed to import Docker GPG key. Network may be returning non-key content."
    fi
    install_docker_ubuntu_fallback
    return
  fi
  rm -f "${tmpkey}" || true
  chmod a+r /etc/apt/keyrings/docker.gpg

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${os_id} ${codename} stable
EOF

  export DEBIAN_FRONTEND=noninteractive

  # --- apt update (try normal, then ForceIPv4). DO NOT let ERR trap exit. ---
  if ! run_soft apt-get update -y; then
    log_warn "Docker repo update failed. Retrying with IPv4 forced..."
    if ! run_soft apt-get -o Acquire::ForceIPv4=true update -y; then
      rm -f /etc/apt/sources.list.d/docker.list >/dev/null 2>&1 || true
      if [[ "${method}" == "official" ]]; then
        die "Docker repo is not usable (NO_PUBKEY/403/network). Set DOCKER_INSTALL_METHOD=ubuntu to bypass."
      fi
      install_docker_ubuntu_fallback
      return
    fi
  fi

  # --- Install Docker CE packages (soft, to allow fallback) ---
  if run_soft apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    systemctl enable --now docker >/dev/null 2>&1 || true

    # Optional: configure mirror (safe behavior if daemon.json already exists)
    configure_docker_registry_mirror

    log_ok "Docker installed successfully (Docker CE)."
    return
  fi

  log_warn "Docker CE install failed."
  rm -f /etc/apt/sources.list.d/docker.list >/dev/null 2>&1 || true

  if [[ "${method}" == "official" ]]; then
    die "Docker CE install failed and DOCKER_INSTALL_METHOD=official is set. Try DOCKER_INSTALL_METHOD=ubuntu."
  fi

  install_docker_ubuntu_fallback
}

sanitize_domain() {
  local d="$1"
  d="${d#http://}"
  d="${d#https://}"
  d="${d%%/*}"
  echo "$d"
}

validate_domain() {
  local d="$1"
  # Basic FQDN validation (sub.domain.tld)
  [[ "$d" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

write_panel_files() {
  local domain="$1"
  local email="$2"

  mkdir -p "${PANEL_DIR}"
  cd "${PANEL_DIR}"

  # Secure file permissions for secrets
  umask 077

  local jwt_auth_secret jwt_api_tokens_secret webhook_secret metrics_user metrics_pass
  local pg_user pg_pass pg_db redis_host redis_port
  local backend_image postgres_image valkey_image caddy_image

  jwt_auth_secret="$(rand_hex 64)"
  jwt_api_tokens_secret="$(rand_hex 64)"
  webhook_secret="$(rand_hex 64)"

  metrics_user="metrics"
  metrics_pass="$(rand_hex 32)"

  pg_user="remnawave"
  pg_pass="$(rand_hex 24)"
  pg_db="remnawave"

  redis_host="remnawave-redis"
  redis_port="6379"

  # Images (override-friendly) - allow bypassing Docker Hub
  backend_image="${RMNW_BACKEND_IMAGE:-remnawave/backend:latest}"
  postgres_image="${RMNW_POSTGRES_IMAGE:-postgres:17.0}"
  valkey_image="${RMNW_VALKEY_IMAGE:-valkey/valkey:8.0-alpine}"
  caddy_image="${RMNW_CADDY_IMAGE:-caddy:2-alpine}"

  cat > .env <<EOF
# Remnawave Panel Environment
# Generated by: remnawave-manager.sh
# Domain
FRONT_END_DOMAIN=${domain}
SUB_PUBLIC_DOMAIN=${domain}/api/sub

# Secrets
JWT_AUTH_SECRET=${jwt_auth_secret}
JWT_API_TOKENS_SECRET=${jwt_api_tokens_secret}
WEBHOOK_SECRET_HEADER=${webhook_secret}

# Metrics (basic auth, if Remnawave uses it)
METRICS_USER=${metrics_user}
METRICS_PASS=${metrics_pass}

# Database
POSTGRES_USER=${pg_user}
POSTGRES_PASSWORD=${pg_pass}
POSTGRES_DB=${pg_db}
DATABASE_URL=postgresql://${pg_user}:${pg_pass}@remnawave-db:5432/${pg_db}?schema=public

# Redis/Valkey
REDIS_HOST=${redis_host}
REDIS_PORT=${redis_port}

# Images (override-friendly)
BACKEND_IMAGE=${backend_image}
POSTGRES_IMAGE=${postgres_image}
VALKEY_IMAGE=${valkey_image}
CADDY_IMAGE=${caddy_image}
EOF

  chmod 600 .env

  cat > docker-compose.yml <<'EOF'
services:
  remnawave-db:
    image: ${POSTGRES_IMAGE}
    restart: unless-stopped
    env_file: .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    volumes:
      - remnawave-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 10s
      retries: 10
      start_period: 15s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  remnawave-redis:
    image: ${VALKEY_IMAGE}
    restart: unless-stopped
    volumes:
      - remnawave-redis-data:/data
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 5s
      timeout: 10s
      retries: 10
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  remnawave:
    image: ${BACKEND_IMAGE}
    restart: unless-stopped
    env_file: .env
    # Bind only on localhost; public access via Caddy
    ports:
      - "127.0.0.1:3000:3000"
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  caddy:
    image: ${CADDY_IMAGE}
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      - remnawave
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  remnawave-db-data:
  remnawave-redis-data:
  caddy-data:
  caddy-config:
EOF

  # Caddyfile (domain + optional email)
  if [[ -n "${email}" ]]; then
    cat > Caddyfile <<EOF
{
  email ${email}
}

${domain} {
  encode zstd gzip
  reverse_proxy 127.0.0.1:3000
}
EOF
  else
    cat > Caddyfile <<EOF
${domain} {
  encode zstd gzip
  reverse_proxy 127.0.0.1:3000
}
EOF
  fi

  # Validate compose
  docker_compose -f docker-compose.yml config -q
  log_ok "Panel files generated under ${PANEL_DIR}"
}
docker_pull_with_hint() {
  # Pull images and show a friendly hint if registry access is blocked.
  local out rc

  trap - ERR
  set +e
  out="$(docker_compose pull 2>&1)"
  rc=$?
  set -e
  trap 'on_error $LINENO' ERR

  if [[ $rc -ne 0 ]]; then
    echo "${out}"

    if echo "${out}" | grep -qiE "export control regulations|Since Docker is a US company|denied:.*403 Forbidden|403 Forbidden"; then
      log_error "Image pull failed due to registry access restrictions (403 / export control)."
      log_warn "Fix options:"
      log_warn "  1) Use a Docker registry mirror (recommended):"
      log_warn "     - Set DOCKER_REGISTRY_MIRROR and re-run install-panel"
      log_warn "  2) Override images to a reachable registry (set these env vars):"
      log_warn "     - RMNW_POSTGRES_IMAGE, RMNW_VALKEY_IMAGE, RMNW_CADDY_IMAGE, RMNW_BACKEND_IMAGE"
      log_warn "Example:"
      log_warn "  sudo DOCKER_REGISTRY_MIRROR=https://mirror.example.com \\"
      log_warn "    RMNW_BACKEND_IMAGE=ghcr.io/remnawave/backend:latest \\"
      log_warn "    $0 install-panel --domain panel.example.com --email admin@example.com"
    else
      log_error "Image pull failed. Check network/DNS/proxy and try again."
    fi

    return "$rc"
  fi

  return 0
}

panel_up() {
  cd "${PANEL_DIR}"
  log_info "Starting Remnawave Panel stack..."

  docker_pull_with_hint || return 1

  docker_compose up -d
  log_ok "Services started."
  log_info "Useful commands:"
  echo "  - Status:   sudo $0 status"
  echo "  - Logs:     sudo $0 logs --panel --tail 200"
  echo "  - Update:   sudo $0 update --panel"
}

panel_down_and_remove() {
  cd "${PANEL_DIR}"
  log_warn "Stopping containers and removing volumes..."
  docker_compose down -v
  cd /
  rm -rf "${PANEL_DIR}"
  log_ok "Panel uninstalled and files removed."
}

node_up() {
  cd "${NODE_DIR}"
  docker_compose -f docker-compose.yml config -q
  log_info "Starting Node stack..."

  docker_pull_with_hint || return 1

  docker_compose up -d
  log_ok "Node started successfully."
}

node_down_and_remove() {
  cd "${NODE_DIR}"
  docker_compose down -v || true
  cd /
  rm -rf "${NODE_DIR}"
  log_ok "Node uninstalled and files removed."
}

status_all() {
  echo -e "${BOLD}== Panel ==${NC}"
  if [[ -d "${PANEL_DIR}" ]]; then
    (cd "${PANEL_DIR}" && docker_compose ps) || true
  else
    log_warn "Panel not installed at ${PANEL_DIR}"
  fi

  echo ""
  echo -e "${BOLD}== Node ==${NC}"
  if [[ -d "${NODE_DIR}" ]]; then
    (cd "${NODE_DIR}" && docker_compose ps) || true
  else
    log_warn "Node not installed at ${NODE_DIR}"
  fi
}

logs_cmd() {
  local target="${1:-panel}" # panel|node
  local tail="${2:-200}"

  local dir
  if [[ "${target}" == "panel" ]]; then
    dir="${PANEL_DIR}"
  else
    dir="${NODE_DIR}"
  fi

  [[ -d "${dir}" ]] || die "Target '${target}' not installed at ${dir}"

  cd "${dir}"
  docker_compose logs --tail "${tail}"
}

update_cmd() {
  local target="${1:-panel}" # panel|node
  local dir
  if [[ "${target}" == "panel" ]]; then
    dir="${PANEL_DIR}"
  else
    dir="${NODE_DIR}"
  fi

  [[ -d "${dir}" ]] || die "Target '${target}' not installed at ${dir}"

  cd "${dir}"
  log_info "Pulling latest images..."
  docker_pull_with_hint || return 1
  log_info "Recreating containers..."
  docker_compose up -d
  log_ok "Update completed."
}

backup_cmd() {
  local target="${1:-panel}"
  local out="${2:-}"

  local dir
  if [[ "${target}" == "panel" ]]; then
    dir="${PANEL_DIR}"
  else
    dir="${NODE_DIR}"
  fi

  [[ -d "${dir}" ]] || die "Target '${target}' not installed at ${dir}"

  if [[ -z "${out}" ]]; then
    out="/root/${target}-backup-$(date +%F-%H%M%S).tgz"
  fi

  tar -C "${dir}" -czf "${out}" .
  log_ok "Backup created: ${out}"
}

open_editor_and_install_node() {
  mkdir -p "${NODE_DIR}"
  cd "${NODE_DIR}"

  log_info "Node installation (interactive)"
  echo "1) Go to Panel > Nodes > Create Node"
  echo "2) Copy the docker-compose.yml content shown in the panel"
  echo "3) Paste it into the editor that opens now, then save & exit"
  echo ""

  local editor="${EDITOR:-}"
  if [[ -z "${editor}" ]]; then
    if has_cmd nano; then editor="nano"
    elif has_cmd vi; then editor="vi"
    else die "No editor found. Install nano or set EDITOR."
    fi
  fi

  touch docker-compose.yml
  ${editor} docker-compose.yml

  if [[ ! -s docker-compose.yml ]]; then
    die "docker-compose.yml is empty. Aborting."
  fi

  node_up
}

# ---------- Argument parsing ----------
main() {
  require_root

  local cmd="${1:-}"
  shift || true

  case "${cmd}" in
    -h|--help|help|"")
      usage
      exit 0
      ;;
    --version|version)
      echo "${VERSION}"
      exit 0
      ;;
  esac

  # Docker auto-install only for install commands (better UX + fewer surprises)
  case "${cmd}" in
    install-panel|install-node)
      install_docker
      ;;
    status|logs|update|backup)
      require_docker_or_die
      ;;
    uninstall-panel|uninstall-node)
      # Optional: do NOT force docker install for uninstall.
      # If docker is missing, we will fail later with a clear message when needed.
      :
      ;;
  esac

  case "${cmd}" in
    install-panel)
      local domain="" email=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --domain) domain="${2:-}"; shift 2 ;;
          --email)  email="${2:-}"; shift 2 ;;
          *) die "Unknown argument: $1" ;;
        esac
      done

      [[ -n "${domain}" ]] || die "Missing --domain (e.g. --domain panel.example.com)"
      domain="$(sanitize_domain "${domain}")"
      validate_domain "${domain}" || die "Invalid domain: ${domain}"

      if [[ -d "${PANEL_DIR}" ]]; then
        log_warn "Panel directory already exists: ${PANEL_DIR}"
        confirm "Re-generate config and restart services? (will keep volumes)" false || die "Cancelled."
      fi

      write_panel_files "${domain}" "${email}"
      panel_up
      echo ""
      log_ok "Installation complete."
      echo "Panel URL: https://${domain}"
      echo "Config:    ${PANEL_DIR}/.env"
      ;;
    uninstall-panel)
      local yes="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --yes) yes="true"; shift ;;
          *) die "Unknown argument: $1" ;;
        esac
      done

      [[ -d "${PANEL_DIR}" ]] || die "Panel not installed at ${PANEL_DIR}"
      log_warn "This will remove Panel containers, volumes (DB data), and ALL related files."
      if [[ "${yes}" == "true" ]] || confirm "Proceed uninstall Panel?" true; then
        panel_down_and_remove
      else
        die "Cancelled."
      fi
      ;;
    install-node)
      open_editor_and_install_node
      ;;
    uninstall-node)
      local yes="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --yes) yes="true"; shift ;;
          *) die "Unknown argument: $1" ;;
        esac
      done

      [[ -d "${NODE_DIR}" ]] || die "Node not installed at ${NODE_DIR}"
      log_warn "This will remove Node containers, volumes, and files."
      if [[ "${yes}" == "true" ]] || confirm "Proceed uninstall Node?" true; then
        node_down_and_remove
      else
        die "Cancelled."
      fi
      ;;
    status)
      status_all
      ;;
    logs)
      local target="panel" tail="200"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --panel) target="panel"; shift ;;
          --node)  target="node"; shift ;;
          --tail)  tail="${2:-200}"; shift 2 ;;
          *) die "Unknown argument: $1" ;;
        esac
      done
      logs_cmd "${target}" "${tail}"
      ;;
    update)
      local target="panel"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --panel) target="panel"; shift ;;
          --node)  target="node"; shift ;;
          *) die "Unknown argument: $1" ;;
        esac
      done
      update_cmd "${target}"
      ;;
    backup)
      local target="panel" out=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --panel) target="panel"; shift ;;
          --node)  target="node"; shift ;;
          --out)   out="${2:-}"; shift 2 ;;
          *) die "Unknown argument: $1" ;;
        esac
      done
      backup_cmd "${target}" "${out}"
      ;;
    *)
      die "Unknown command: ${cmd}. Use: $0 --help"
      ;;
  esac
}

main "$@"
