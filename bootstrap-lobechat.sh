#!/usr/bin/env bash
#
# bootstrap-lobechat.sh — provisions the LobeChat stack on Ubuntu 24.04 EC2.
#
# Run after SSH-ing into the instance, with the required env vars exported
# (see REQUIRED_ENV below). Idempotent: safe to re-run.
#
#   export KEY_VAULTS_SECRET=...  NEXT_AUTH_SECRET=...  OPENROUTER_API_KEY=...
#   export POSTGRES_PASSWORD=...  MINIO_ROOT_PASSWORD=...
#   export MCPHUB_ADMIN_PASSWORD=...  HOST_DOMAIN=...
#   ./bootstrap-lobechat.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — REVIEW BEFORE RUNNING
# ---------------------------------------------------------------------------
REPO_URL="${REPO_URL:-https://github.com/FinnSolly2/lobechat-aws.git}"  # <-- set me
REPO_REF="${REPO_REF:-main}"
APP_DIR="${APP_DIR:-$HOME/lobechat-aws}"
DOMAIN="esade-user81-lobechat.duckdns.org"
NEW_REDIRECT_URI="https://${DOMAIN}"
PROF_REDIRECT_MATCH="${PROF_REDIRECT_MATCH:-wsl.ymbihq.local}"  # string in init_data.json to replace
CADDY_EMAIL="${CADDY_EMAIL:-finnsolly2@gmail.com}"
INIT_DATA="config/init_data.json"

# Env vars that MUST be exported before running; written verbatim into .env
REQUIRED_ENV=(
  KEY_VAULTS_SECRET
  NEXT_AUTH_SECRET
  OPENROUTER_API_KEY
  POSTGRES_PASSWORD
  MINIO_ROOT_PASSWORD
  MCPHUB_ADMIN_PASSWORD
  HOST_DOMAIN
)
# Optional env vars — written to .env only if set
OPTIONAL_ENV=(
  HF_TOKEN
  AUTH_CASDOOR_ID
  AUTH_CASDOOR_SECRET
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_FILE="${APP_DIR%/*}/bootstrap-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
step() { log "=== $* ==="; }
die()  { log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------------------
step "1. Verifying required environment variables"
# ---------------------------------------------------------------------------
missing=()
for v in "${REQUIRED_ENV[@]}"; do
  [[ -n "${!v:-}" ]] || missing+=("$v")
done
[[ ${#missing[@]} -eq 0 ]] || die "missing required env vars: ${missing[*]}"
log "all required env vars present"

# ---------------------------------------------------------------------------
step "2. Installing Docker + docker-compose-plugin"
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  log "Docker + compose plugin already installed — skipping"
else
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  log "Docker installed (you may need to re-login for group membership)"
fi

# ---------------------------------------------------------------------------
step "3. Installing Caddy"
# ---------------------------------------------------------------------------
if command -v caddy >/dev/null 2>&1; then
  log "Caddy already installed — skipping"
else
  sudo apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq caddy
  log "Caddy installed"
fi

# ---------------------------------------------------------------------------
step "4. Cloning / updating repository"
# ---------------------------------------------------------------------------
if [[ -d "$APP_DIR/.git" ]]; then
  log "repo exists — fetching latest"
  git -C "$APP_DIR" fetch --quiet origin
  git -C "$APP_DIR" checkout --quiet "$REPO_REF"
  git -C "$APP_DIR" pull --quiet --ff-only origin "$REPO_REF"
else
  command -v git >/dev/null 2>&1 || sudo apt-get install -y -qq git
  git clone --quiet --branch "$REPO_REF" "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"
log "repository ready at $APP_DIR"

# ---------------------------------------------------------------------------
step "5. Patching redirectUri in $INIT_DATA"
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || sudo apt-get install -y -qq jq
[[ -f "$INIT_DATA" ]] || die "$INIT_DATA not found"

if grep -q "$PROF_REDIRECT_MATCH" "$INIT_DATA"; then
  cp "$INIT_DATA" "$INIT_DATA.bak.$(date +%s)"
  # Walk every string in the JSON; replace any containing the professor's host.
  jq --arg match "$PROF_REDIRECT_MATCH" --arg new "$NEW_REDIRECT_URI" '
    walk(if type == "string" and (test($match)) then $new else . end)
  ' "$INIT_DATA" > "$INIT_DATA.tmp"
  mv "$INIT_DATA.tmp" "$INIT_DATA"
  log "redirectUri patched to $NEW_REDIRECT_URI (backup saved)"
else
  log "no occurrence of '$PROF_REDIRECT_MATCH' found — assuming already patched"
fi

# ---------------------------------------------------------------------------
step "6. Writing .env from environment variables"
# ---------------------------------------------------------------------------
ENV_FILE="$APP_DIR/.env"
{
  echo "# Generated by bootstrap-lobechat.sh on $(date '+%Y-%m-%d %H:%M:%S')"
  echo "APP_URL=${NEW_REDIRECT_URI}"
  echo "AUTH_URL=${NEW_REDIRECT_URI}/api/auth"
  echo ""
  echo "# Non-secret defaults"
  echo "MINIO_ROOT_USER=minioadmin"
  echo "S3_BUCKET=lobe"
  echo "AWS_REGION=eu-west-1"
  echo "LOBECHAT_PORT=47000"
  echo "CASDOOR_PORT=47002"
  echo "POSTGRES_PORT=47003"
  echo "MINIO_PORT=47005"
  echo "MINIO_CONSOLE_PORT=47006"
  echo "VLLM_PORT=47007"
  echo "MCPHUB_PORT=47008"
  echo ""
  echo "# Secrets / host-specific (from environment)"
  for v in "${REQUIRED_ENV[@]}"; do echo "${v}=${!v}"; done
  for v in "${OPTIONAL_ENV[@]}"; do [[ -n "${!v:-}" ]] && echo "${v}=${!v}"; done
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
log ".env written ($(grep -c '=' "$ENV_FILE") keys, mode 600 — not committed to git)"

# ---------------------------------------------------------------------------
step "7. Configuring Caddy reverse proxy"
# ---------------------------------------------------------------------------
CADDYFILE="/etc/caddy/Caddyfile"
DESIRED_CADDY="$(cat <<EOF
{
    email ${CADDY_EMAIL}
}

${DOMAIN} {
    reverse_proxy localhost:47000
}
EOF
)"
if [[ -f "$CADDYFILE" ]] && diff -q <(echo "$DESIRED_CADDY") "$CADDYFILE" >/dev/null 2>&1; then
  log "Caddyfile already up to date — skipping"
else
  echo "$DESIRED_CADDY" | sudo tee "$CADDYFILE" >/dev/null
  sudo caddy validate --config "$CADDYFILE" --adapter caddyfile
  sudo systemctl reload caddy || sudo systemctl restart caddy
  log "Caddyfile written and Caddy reloaded"
fi

# ---------------------------------------------------------------------------
step "8. Starting the stack (compose + override)"
# ---------------------------------------------------------------------------
[[ -f docker-compose.yml ]]          || die "docker-compose.yml not found"
[[ -f docker-compose.override.yml ]] || die "docker-compose.override.yml not found (vLLM mock)"

# Use sudo if the docker group isn't active in this shell yet.
DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

$DOCKER compose -f docker-compose.yml -f docker-compose.override.yml pull --quiet || true
$DOCKER compose -f docker-compose.yml -f docker-compose.override.yml up -d
log "stack started"
$DOCKER compose -f docker-compose.yml -f docker-compose.override.yml ps | tee -a "$LOG_FILE"

step "Bootstrap complete — log: $LOG_FILE"
log "Visit https://${DOMAIN} once DuckDNS resolves to this instance."
