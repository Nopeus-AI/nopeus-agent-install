#!/usr/bin/env bash
# Standalone Nopeus Agent public installer. No source checkout, build, or GitHub login.
set -euo pipefail
umask 077
RELEASE='0.1.8'
IMAGE='nopeus-agent-runtime:0.1.8'
IMAGE_INDEX='sha256:4725974afd56c7c57e3f20ecaee46a2de22e7d7a3d353da4bcf7bb63ab90f443'
IMAGE_CONFIG='sha256:80d31be56ac186f48f94d23db1ad832f31bc4cda49ffe742e52da6f1eda7b8f9'
ARCHIVE_SHA256='d64aebbf92834fee78d7a1ca155b651ca496c62fdf2aa077db336ce3096edea3'
ARCHIVE_URL='https://github.com/Nopeus-AI/nopeus-agent-install/releases/download/v0.1.8/nopeus-agent-linux-amd64.tar.gz'
run_setup=true
case "${1:-}" in
  --no-setup) run_setup=false ;;
  --help|-h) printf 'Usage: curl -fsSL https://nopeus.xyz/agent/install | bash [-s -- --no-setup]\n'; exit 0 ;;
  '') ;;
  *) printf 'Unknown option. Use --help.\n' >&2; exit 1 ;;
esac
die() { printf '%s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || die 'This pilot installer supports Linux x86-64 servers only.'
for command in docker curl sha256sum; do command -v "$command" >/dev/null || die "Required command missing: $command"; done
docker compose version >/dev/null || die 'Docker Compose v2 is required.'
docker info >/dev/null 2>&1 || die 'Cannot access Docker. Use a server account authorized to run Docker (Coolify servers already have it).'
[[ "$(docker info --format '{{.OSType}}')" == linux ]] || die 'A Linux Docker engine is required.'
if [[ "$run_setup" == true ]]; then
  { : </dev/tty; } 2>/dev/null || die 'An interactive terminal is required for setup. Use --no-setup to install now, then run nopeus-agent setup in a terminal.'
fi
install_dir="${NOPEUS_INSTALL_DIR:-$HOME/.local/share/nopeus-agent}"
project="${NOPEUS_PROJECT_NAME:-nopeus-agent}"
[[ "$project" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die 'Invalid Compose project name.'
if [[ -n "${NOPEUS_BIN_DIR:-}" ]]; then bin_dir="$NOPEUS_BIN_DIR";
elif [[ -w /usr/local/bin ]]; then bin_dir=/usr/local/bin;
else bin_dir="$HOME/.local/bin"; fi
mkdir -p -- "$install_dir" "$bin_dir"
[[ ! -L "$install_dir/compose.yaml" ]] || die 'Refusing symlinked Compose file.'
if [[ -e "$install_dir/compose.yaml" ]] && ! head -n 2 -- "$install_dir/compose.yaml" | grep -Fq '# Nopeus Agent managed runtime'; then
  die "Refusing to replace unrelated files in $install_dir. Choose another NOPEUS_INSTALL_DIR."
fi
launcher="$bin_dir/nopeus-agent"
if [[ -e "$launcher" || -L "$launcher" ]]; then
  [[ -f "$launcher" && ! -L "$launcher" ]] && head -n 3 -- "$launcher" | grep -Fq '# Nopeus Agent managed launcher' || die "Refusing to replace unrelated command: $launcher"
fi
printf 'Installing Nopeus Agent %s (text-and-messaging pilot).\n' "$RELEASE"
printf 'Model keys and messaging accounts are configured afterward in the terminal UI.\n'
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
verify_image() {
  local image_id
  image_id="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null)" || return 1
  [[ "$image_id" == "$IMAGE_INDEX" || "$image_id" == "$IMAGE_CONFIG" ]]
}
if ! verify_image; then
  printf 'Downloading the prebuilt runtime (no GitHub login required)...\n'
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 "$ARCHIVE_URL" -o "$work_dir/runtime.tar.gz" </dev/null
  printf '%s  %s\n' "$ARCHIVE_SHA256" "$work_dir/runtime.tar.gz" | sha256sum --check --status || die 'Runtime checksum mismatch. Nothing was loaded.'
  docker load --input "$work_dir/runtime.tar.gz" </dev/null
  verify_image || die 'Loaded runtime does not match the reviewed release identity.'
fi
launcher="$bin_dir/nopeus-agent"
launcher_tmp="$(mktemp "$bin_dir/.nopeus-agent.XXXXXX")"
{
  printf '#!/usr/bin/env bash\n# Nopeus Agent managed launcher\nset -euo pipefail\n'
  printf 'install_dir=%q\nproject=%q\n' "$install_dir" "$project"
  cat <<'LAUNCHER'
compose=(docker compose -p "$project" -f "$install_dir/compose.yaml")
case "${1:-}" in
  start) exec "${compose[@]}" up -d --wait --wait-timeout 240 ;;
  stop) exec "${compose[@]}" stop ;;
  restart) exec "${compose[@]}" restart agent ;;
  logs) exec "${compose[@]}" logs -f agent ;;
  update)
    export NOPEUS_INSTALL_DIR="$install_dir" NOPEUS_PROJECT_NAME="$project"
    export NOPEUS_BIN_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
    curl -fsSL https://raw.githubusercontent.com/Nopeus-AI/nopeus-agent-install/main/install.sh | bash -s -- --no-setup ;;
  *) exec "${compose[@]}" exec agent node src/cli.js "$@" ;;
esac
LAUNCHER
} > "$launcher_tmp"
chmod 700 "$launcher_tmp"; mv -- "$launcher_tmp" "$launcher"

# The model can only submit an owner-authorized update request. This host watcher
# consumes that request and runs the fixed, checksum-pinned installer command.
watcher="$install_dir/update-watcher.sh"
watcher_tmp="$(mktemp "$install_dir/.update-watcher.XXXXXX")"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'launcher=%q\n' "$launcher"
  cat <<'WATCHER'
while true; do
  request_id="$("$launcher" update-request-check 2>/dev/null || true)"
  if [[ "$request_id" =~ ^[0-9a-f-]{36}$ ]] && "$launcher" update-request-clear "$request_id" >/dev/null 2>&1; then
    if ! "$launcher" update; then printf '%s\n' 'Nopeus Agent self-update failed; request cleared. Retry with /upgrade or update from the server.' >&2; fi
  fi
  sleep 15
done
WATCHER
} > "$watcher_tmp"
chmod 700 "$watcher_tmp"; mv -- "$watcher_tmp" "$watcher"

auto_update_enabled=false
unit_name=nopeus-agent-updater.service
systemd_escape() { printf '%q' "$1"; }
if [[ "$EUID" -eq 0 && -d /run/systemd/system ]] && command -v systemctl >/dev/null && systemctl show-environment >/dev/null 2>&1; then
  unit_file="/etc/systemd/system/$unit_name"
  if [[ ! -e "$unit_file" ]] || grep -Fq '# Nopeus Agent update watcher' "$unit_file"; then
    { printf '[Unit]\nDescription=Nopeus Agent update watcher\n# Nopeus Agent update watcher\nAfter=network-online.target docker.service\n\n[Service]\nType=simple\n';
      printf 'ExecStart=%s\nRestart=always\nRestartSec=15\nNoNewPrivileges=true\nUMask=0077\n\n[Install]\nWantedBy=multi-user.target\n' "$(systemd_escape "$watcher")"; } > "$unit_file"
    if systemctl daemon-reload && systemctl enable --now "$unit_name"; then auto_update_enabled=true; fi
  fi
elif command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  unit_dir="$HOME/.config/systemd/user"; mkdir -p -- "$unit_dir"; unit_file="$unit_dir/$unit_name"
  linger=false
  if command -v loginctl >/dev/null; then [[ "$(loginctl show-user "${USER:-$(id -un)}" -p Linger --value 2>/dev/null || true)" == yes ]] && linger=true; fi
  if [[ "$linger" == true ]] && { [[ ! -e "$unit_file" ]] || grep -Fq '# Nopeus Agent update watcher' "$unit_file"; }; then
    { printf '[Unit]\nDescription=Nopeus Agent update watcher\n# Nopeus Agent update watcher\nAfter=network-online.target\n\n[Service]\nType=simple\n';
      printf 'ExecStart=%s\nRestart=always\nRestartSec=15\nNoNewPrivileges=true\nUMask=0077\n\n[Install]\nWantedBy=default.target\n' "$(systemd_escape "$watcher")"; } > "$unit_file"
    if systemctl --user daemon-reload && systemctl --user enable --now "$unit_name"; then auto_update_enabled=true; fi
  fi
fi

cat > "$work_dir/compose.yaml" <<COMPOSE
# Nopeus Agent managed runtime
services:
  agent:
    image: $IMAGE
    pull_policy: never
    init: true
    restart: unless-stopped
    environment:
      NOPEUS_HOST: 0.0.0.0
      NOPEUS_PORT: 7331
      NOPEUS_DATA_DIR: /data
      NOPEUS_AUTO_UPDATE_ENABLED: "$auto_update_enabled"
    volumes:
      - agent-data:/data
    healthcheck:
      test: ["CMD", "node", "src/healthcheck.js"]
      interval: 15s
      timeout: 8s
      start_period: 180s
      retries: 5
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    mem_limit: 2g
    pids_limit: 256
volumes:
  agent-data:
COMPOSE
# Create files atomically; keep the same project/volume on every reinstallation.
compose_tmp="$(mktemp "$install_dir/.compose.XXXXXX")"
cp -- "$work_dir/compose.yaml" "$compose_tmp"; chmod 600 "$compose_tmp"; mv -- "$compose_tmp" "$install_dir/compose.yaml"
docker compose -p "$project" -f "$install_dir/compose.yaml" up -d --wait --wait-timeout 240 </dev/null
printf '\nInstalled: %s\n' "$launcher"
printf 'No public port or domain is needed. Existing data is preserved in the agent-data volume.\n'
if [[ "$auto_update_enabled" == true ]]; then printf 'Owner-triggered self-updates are enabled via /upgrade.\n'; else printf 'Self-updates need an active systemd service; use nopeus-agent update on the server meanwhile. A non-root user service also needs loginctl enable-linger.\n'; fi
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then printf 'To use the short command: export PATH="%s:$PATH"\n' "$bin_dir"; fi
if [[ "$run_setup" == true ]]; then
  # curl | bash owns stdin. Read terminal interaction from the controlling TTY instead.
  "$launcher" setup </dev/tty >/dev/tty 2>/dev/tty
fi
printf '\nCommands: nopeus-agent setup | nopeus-agent status | nopeus-agent logs\n'
printf 'This is the standalone agent pilot, separate from Nopeus Business and Coolify-managed apps.\n'
