#!/usr/bin/env bash
# Standalone Nopeus Agent public installer. No source checkout, build, or GitHub login.
set -euo pipefail
umask 077
RELEASE_REPOSITORY='Nopeus-AI/nopeus-agent-install'
run_setup=true
case "${1:-}" in
  --no-setup) run_setup=false ;;
  --help|-h) printf 'Usage: curl -fsSL https://nopeus.xyz/agent/install | bash [-s -- --no-setup]\n'; exit 0 ;;
  '') ;;
  *) printf 'Unknown option. Use --help.\n' >&2; exit 1 ;;
esac
die() { printf '%s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || die 'This pilot installer supports Linux x86-64 servers only.'
printf 'Checking Docker and the existing Nopeus Agent installation...\n'
for command in docker curl sha256sum tar gzip sed sort awk grep; do command -v "$command" >/dev/null || die "Required command missing: $command"; done
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
work_dir="$(mktemp -d)"
update_started=false
OLD_VERSION=""
update_project_compose=(docker compose -p "$project" -f "$install_dir/compose.yaml")
send_update_telegram() {
  local message="$1"
  "${update_project_compose[@]}" exec -T -e NOPEUS_UPDATE_MESSAGE="$message" agent node --input-type=module -e 'import { runtimeEnvironment } from "./src/config.js"; const env=runtimeEnvironment(); if (!env.TELEGRAM_BOT_TOKEN) process.exit(0); for (const id of (env.TELEGRAM_ALLOWED_USERS||"").split(",").filter(x=>/^\d+$/.test(x))) { const r=await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({chat_id:id,text:process.env.NOPEUS_UPDATE_MESSAGE})}); if (!r.ok) throw new Error("Telegram update notice failed"); }' >/dev/null 2>&1 </dev/null
}
finish_install() {
  local status=$?
  if [[ "$status" -ne 0 && "$update_started" == true ]]; then
    local target="${RELEASE:-the latest release}"
    send_update_telegram "⚠️ Nopeus Agent could not finish its update to $target. The running version was not confirmed; it should still be v$OLD_VERSION. Please retry /upgrade or run nopeus-agent update on the server." || true
  fi
  rm -rf -- "$work_dir"
}
trap finish_install EXIT
# Read the running version before contacting GitHub so an update request still
# gets a useful failure notice if release lookup or metadata validation fails.
compose=("${update_project_compose[@]}")
OLD_VERSION="$("${compose[@]}" exec -T agent node -p "require('./package.json').version" 2>/dev/null </dev/null || true)"
if [[ "$OLD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  update_started=true
fi
release_list="$work_dir/releases.json"
printf 'Checking the latest published agent release...\n'
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
  "https://api.github.com/repos/$RELEASE_REPOSITORY/releases?per_page=30" -o "$release_list" </dev/null
RELEASE_TAG="$(sed -n 's/^[[:space:]]*"tag_name": "\([^"]*\)".*/\1/p' "$release_list" \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$' \
  | awk '{ tag=$0; version=tag; sub(/^v/, "", version); base=version; sub(/-.*/, "", base); stable=(version == base ? 1 : 0); print base "\t" stable "\t" tag }' \
  | sort -t $'\t' -k1,1V -k2,2n -k3,3V \
  | tail -n 1 | cut -f 3 || true)"
[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || die 'Could not find a published Nopeus Agent release.'
printf 'Selected release %s. Validating its release metadata...\n' "$RELEASE_TAG"
RELEASE_INFO_URL="https://github.com/$RELEASE_REPOSITORY/releases/download/$RELEASE_TAG/release-info.txt"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 "$RELEASE_INFO_URL" -o "$work_dir/release-info.txt" </dev/null
release_field() { sed -n "s/^$1=//p" "$work_dir/release-info.txt" | sed -n '1p'; }
RELEASE="$(release_field version)"
[[ "$RELEASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ && "$RELEASE_TAG" == "v$RELEASE" ]] || die 'Latest release metadata has an invalid version.'
RELEASE_SUMMARY="$(release_field summary)"
[[ -n "$RELEASE_SUMMARY" && ${#RELEASE_SUMMARY} -le 500 && "$RELEASE_SUMMARY" != *$'\n'* && "$RELEASE_SUMMARY" != *$'\r'* ]] || RELEASE_SUMMARY="This release includes improvements and fixes."
[[ "$(release_field release_tag)" == "$RELEASE_TAG" ]] || die 'Release metadata tag does not match the selected release.'
[[ "$(release_field source_commit)" =~ ^[a-f0-9]{40}$ ]] || die 'Release metadata has an invalid source commit.'
ARCHIVE_SHA256="$(release_field archive_sha256)"
BROWSER_ARCHIVE_SHA256="$(release_field browser_archive_sha256)"
[[ "$ARCHIVE_SHA256" =~ ^[a-f0-9]{64}$ && "$BROWSER_ARCHIVE_SHA256" =~ ^[a-f0-9]{64}$ ]] || die 'Release metadata has invalid archive checksums.'
IMAGE_TAG="$RELEASE"
IMAGES=("nopeus-agent-runtime:$IMAGE_TAG" "nopeus-agent-computer:$IMAGE_TAG" "nopeus-agent-audio:$IMAGE_TAG" "nopeus-agent-browser-egress:$IMAGE_TAG" "nopeus-agent-browser:$IMAGE_TAG" "nopeus-agent-browser-runtime:$IMAGE_TAG")
IMAGE_IDS=("$(release_field image_runtime)" "$(release_field image_computer)" "$(release_field image_audio)" "$(release_field image_egress)" "$(release_field image_browser)" "$(release_field image_browser_runtime)")
for image_id in "${IMAGE_IDS[@]}"; do [[ "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || die 'Release metadata has an invalid Docker image identity.'; done
ARCHIVE_NAME="$(release_field archive)"
BROWSER_ARCHIVE_NAME="$(release_field browser_archive)"
[[ "$ARCHIVE_NAME" == nopeus-agent-linux-amd64.tar.gz && "$BROWSER_ARCHIVE_NAME" == nopeus-agent-browser-linux-amd64.tar.gz ]] || die 'Release metadata has unexpected archive names.'
ARCHIVE_URL="https://github.com/$RELEASE_REPOSITORY/releases/download/$RELEASE_TAG/$ARCHIVE_NAME"
BROWSER_ARCHIVE_URL="https://github.com/$RELEASE_REPOSITORY/releases/download/$RELEASE_TAG/$BROWSER_ARCHIVE_NAME"
printf 'Installing Nopeus Agent %s (standalone alpha).\n' "$RELEASE"
printf 'Model keys and messaging accounts are configured afterward in the terminal UI.\n'
# Capture the old runtime's version before its image is replaced. Deliver the
# start notice through its existing Telegram configuration and preserve a
# completion notice in the shared data volume for the new runtime to send.
compose=("${update_project_compose[@]}")
if [[ "$OLD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ && "$OLD_VERSION" != "$RELEASE" ]]; then
  start_message="⏳ Nopeus Agent update started: v$OLD_VERSION → v$RELEASE. Downloading the runtime images now; this may take several minutes. I will restart and send a confirmation with the new version and release notes when it is ready."
  send_update_telegram "$start_message" || printf 'Could not deliver Telegram update-start notice; continuing installation.\n' >&2
  "${compose[@]}" exec -T \
    -e NOPEUS_UPDATE_FROM_VERSION="$OLD_VERSION" \
    -e NOPEUS_UPDATE_TO_VERSION="$RELEASE" \
    -e NOPEUS_UPDATE_SUMMARY="$RELEASE_SUMMARY" \
    agent node --input-type=module -e 'import { openSync, writeFileSync, closeSync, renameSync, lstatSync, existsSync } from "node:fs"; import { join } from "node:path"; import { dataDirectory } from "./src/config.js"; const dir=dataDirectory(); const path=join(dir,"update-notice.json"); if (existsSync(path) && lstatSync(path).isSymbolicLink()) throw new Error("Refusing symlinked update notice"); const temp=join(dir,".update-notice-"+process.pid+".tmp"); const fd=openSync(temp,"wx",0o600); try { writeFileSync(fd,JSON.stringify({fromVersion:process.env.NOPEUS_UPDATE_FROM_VERSION,toVersion:process.env.NOPEUS_UPDATE_TO_VERSION,summary:process.env.NOPEUS_UPDATE_SUMMARY})+"\n"); closeSync(fd); renameSync(temp,path); } catch(e) { try { closeSync(fd); } catch {} throw e; }' >/dev/null 2>&1 </dev/null || die 'Could not preserve the Telegram update completion notice; update cancelled before replacing the running agent.'
elif [[ "$OLD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  update_started=false
  send_update_telegram "✅ Nopeus Agent is already up to date. This server is running v$OLD_VERSION, the latest published release. No restart was needed." || true
fi
verify_images() {
  local i image_id
  for i in "${!IMAGES[@]}"; do
    image_id="$(docker image inspect "${IMAGES[$i]}" --format '{{.Id}}' 2>/dev/null)" || return 1
    [[ "$image_id" == "${IMAGE_IDS[$i]}" ]] || return 1
  done
}
verify_loaded_release() {
  local i image_id runtime_version
  for i in "${!IMAGES[@]}"; do
    image_id="$(docker image inspect "${IMAGES[$i]}" --format '{{.Id}}' 2>/dev/null)" || return 1
    [[ "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
  done
  runtime_version="$(docker run --rm --network none --entrypoint node "${IMAGES[0]}" -p "require('./package.json').version" </dev/null 2>/dev/null)" || return 1
  [[ "$runtime_version" == "$RELEASE" ]]
}
if ! verify_images; then
  printf 'Downloading the prebuilt runtime and isolated worker images...\n'
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 "$ARCHIVE_URL" -o "$work_dir/release.tar.gz" </dev/null
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 "$BROWSER_ARCHIVE_URL" -o "$work_dir/browser-images.tar.gz" </dev/null
  printf '%s  %s\n' "$ARCHIVE_SHA256" "$work_dir/release.tar.gz" | sha256sum --check --status || die 'Release checksum mismatch. Nothing was loaded.'
  printf '%s  %s\n' "$BROWSER_ARCHIVE_SHA256" "$work_dir/browser-images.tar.gz" | sha256sum --check --status || die 'Browser runtime checksum mismatch. Nothing was loaded.'
  mkdir "$work_dir/package"
  tar -xzf "$work_dir/release.tar.gz" --no-same-owner --no-same-permissions -C "$work_dir/package"
  [[ -f "$work_dir/package/images.tar" && -f "$work_dir/package/compose.yaml" && -f "$work_dir/package/seccomp/chromium.json" ]] || die 'Release package is incomplete.'
  docker load --input "$work_dir/package/images.tar" </dev/null
  gzip -dc "$work_dir/browser-images.tar.gz" | docker load
  if ! verify_images; then
    printf 'Release image IDs differ from the release metadata; checking the checksum-verified archive contents and runtime version.\n' >&2
    verify_loaded_release || die 'Loaded release archive is missing images or its runtime version does not match the release.'
  fi
fi
launcher="$bin_dir/nopeus-agent"
launcher_tmp="$(mktemp "$bin_dir/.nopeus-agent.XXXXXX")"
{
  printf '#!/usr/bin/env bash\n# Nopeus Agent managed launcher\nset -euo pipefail\n'
  printf 'install_dir=%q\nproject=%q\n' "$install_dir" "$project"
  cat <<'LAUNCHER'
compose=(docker compose -p "$project" -f "$install_dir/compose.yaml")
case "${1:-}" in
  start) exec "${compose[@]}" up -d --wait --wait-timeout 900 ;;
  stop) exec "${compose[@]}" stop ;;
  restart) exec "${compose[@]}" restart agent ;;
  logs) exec "${compose[@]}" logs -f agent ;;
  update)
    export NOPEUS_INSTALL_DIR="$install_dir" NOPEUS_PROJECT_NAME="$project"
    export NOPEUS_BIN_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
    update_script="$(mktemp)"
    trap 'rm -f -- "$update_script"' EXIT
    printf 'Downloading the Nopeus Agent updater...\n'
    curl --fail --location --show-error --retry 3 --connect-timeout 15 \
      https://raw.githubusercontent.com/Nopeus-AI/nopeus-agent-install/main/install.sh \
      -o "$update_script"
    printf 'Starting the updater. It will report the selected release and any failed step below.\n'
    bash "$update_script" --no-setup ;;
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
  "$launcher" update-watcher-heartbeat >/dev/null 2>&1 || true
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

if [[ ! -f "$work_dir/package/compose.yaml" ]]; then
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 "$ARCHIVE_URL" -o "$work_dir/release.tar.gz" </dev/null
  printf '%s  %s\n' "$ARCHIVE_SHA256" "$work_dir/release.tar.gz" | sha256sum --check --status || die 'Release checksum mismatch.'
  mkdir -p "$work_dir/package"
  tar -xzf "$work_dir/release.tar.gz" --no-same-owner --no-same-permissions -C "$work_dir/package"
fi
sed "s/__AUTO_UPDATE_ENABLED__/$auto_update_enabled/" "$work_dir/package/compose.yaml" > "$work_dir/compose.yaml"
[[ ! -L "$install_dir/seccomp" ]] || die 'Refusing symlinked seccomp configuration.'
mkdir -p "$install_dir/seccomp"
cp "$work_dir/package/seccomp/chromium.json" "$install_dir/seccomp/chromium.json.tmp"
chmod 600 "$install_dir/seccomp/chromium.json.tmp"
mv "$install_dir/seccomp/chromium.json.tmp" "$install_dir/seccomp/chromium.json"
# Create files atomically; keep the same project/volume on every reinstallation.
compose_tmp="$(mktemp "$install_dir/.compose.XXXXXX")"
cp -- "$work_dir/compose.yaml" "$compose_tmp"; chmod 600 "$compose_tmp"; mv -- "$compose_tmp" "$install_dir/compose.yaml"
docker compose -p "$project" -f "$install_dir/compose.yaml" up -d --wait --wait-timeout 900 </dev/null
printf '\nInstalled: %s\n' "$launcher"
printf 'The agent, isolated workspace, browser, and audio services are installed. Existing conversation data is preserved in the agent-data volume.\n'
if [[ "$auto_update_enabled" == true ]]; then printf 'Owner-triggered self-updates are enabled via /upgrade.\n'; else printf 'Self-updates need an active systemd service; use nopeus-agent update on the server meanwhile. A non-root user service also needs loginctl enable-linger.\n'; fi
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then printf 'To use the short command: export PATH="%s:$PATH"\n' "$bin_dir"; fi
if [[ "$run_setup" == true ]]; then
  # curl | bash owns stdin. Read terminal interaction from the controlling TTY instead.
  "$launcher" setup </dev/tty >/dev/tty 2>/dev/tty
fi
printf '\nCommands: nopeus-agent setup | nopeus-agent status | nopeus-agent logs\n'
printf 'This is the standalone agent pilot, separate from Nopeus Business and Coolify-managed apps.\n'
