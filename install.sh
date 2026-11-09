#!/usr/bin/env bash
# Standalone Nopeus Agent public installer. No source checkout, build, or GitHub login.
set -euo pipefail
umask 077
RELEASE='0.1.3'
IMAGE='nopeus-agent-runtime:0.1.3'
IMAGE_INDEX='sha256:535f6a3f75d1ee7c8cf7602d7390a5df5052fba272b63a7f7b1db32d63692797'
IMAGE_CONFIG='sha256:4d85a97144dfbf2376ca312ddc25989966ce7f5d0968c6a614b157b8602a92d9'
ARCHIVE_SHA256='beab786d0ae36e3ee5d21110026bc354952924cf31a63ecd01db656bb4fa70ba'
ARCHIVE_URL='https://github.com/Nopeus-AI/nopeus-agent-install/releases/download/v0.1.3/nopeus-agent-linux-amd64.tar.gz'
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
docker compose -p "$project" -f "$install_dir/compose.yaml" up -d --wait --wait-timeout 240 </dev/null
printf '\nInstalled: %s\n' "$launcher"
printf 'No public port or domain is needed. Existing data is preserved in the agent-data volume.\n'
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then printf 'To use the short command: export PATH="%s:$PATH"\n' "$bin_dir"; fi
if [[ "$run_setup" == true ]]; then
  # curl | bash owns stdin. Read terminal interaction from the controlling TTY instead.
  "$launcher" setup </dev/tty >/dev/tty 2>/dev/tty
fi
printf '\nCommands: nopeus-agent setup | nopeus-agent status | nopeus-agent logs\n'
printf 'This is the standalone agent pilot, separate from Nopeus Business and Coolify-managed apps.\n'
