#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/install" "$root/bin" "$root/launchers"
printf '# Nopeus Agent managed runtime\nservices: {}\n' > "$root/install/compose.yaml"
awk "/cat <<'LAUNCHER'/{copy=1;next} copy && /^LAUNCHER$/{copy=0} copy" "$repo/install.sh" > "$root/launcher.body"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'install_dir=%q\nproject=%q\n' "$root/install" nopeus-agent
  cat "$root/launcher.body"
} > "$root/launchers/nopeus-agent"
chmod +x "$root/launchers/nopeus-agent"

cat > "$root/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$DOCKER_LOG"
case "$*" in
  "compose -p nopeus-agent -f "*" down "*) exit "${COMPOSE_STATUS:-0}" ;;
  *"ps -aq --filter label=com.docker.compose.project=nopeus-agent"*) printf 'container-1\n' ;;
  *"network ls -q --filter label=com.docker.compose.project=nopeus-agent"*) printf 'network-1\n' ;;
  *"volume ls -q --filter label=com.docker.compose.project=nopeus-agent"*) printf 'volume-1\nvolume-2\n' ;;
  *"images --format"*) printf 'nopeus-agent-runtime:0.2.0-alpha.68\nnopeus-agent-audio:0.2.0-alpha.68\nunrelated:latest\n' ;;
esac
exit 0
EOF
chmod +x "$root/bin/docker"
cat > "$root/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$DOCKER_LOG"
EOF
chmod +x "$root/bin/systemctl"

export PATH="$root/bin:$PATH"
export DOCKER_LOG="$root/calls"
launcher="$root/launchers/nopeus-agent"

# dry run makes no changes
"$launcher" uninstall --dry-run > "$root/dry.out"
grep -Fq 'down --volumes --rmi all --remove-orphans' "$root/dry.out"
grep -Fq 'Would remove launcher' "$root/dry.out"
[[ -f "$launcher" ]] || { echo 'dry run removed the launcher' >&2; exit 1; }
[[ ! -s "$DOCKER_LOG" ]] || { echo 'dry run called docker' >&2; cat "$DOCKER_LOG" >&2; exit 1; }

# keep data removes the stack but not the volumes
"$launcher" uninstall --yes --keep-data > "$root/keep.out"
grep -Fq 'down --rmi all --remove-orphans' "$DOCKER_LOG"
if grep -Fq 'down --volumes' "$DOCKER_LOG"; then echo 'keep-data removed volumes' >&2; exit 1; fi
if grep -Fq 'volume rm' "$DOCKER_LOG"; then echo 'keep-data called volume rm' >&2; exit 1; fi
grep -Fq 'docker rmi nopeus-agent-runtime:0.2.0-alpha.68 nopeus-agent-audio:0.2.0-alpha.68' "$DOCKER_LOG"
[[ ! -e "$launcher" ]] || { echo 'launcher not removed' >&2; exit 1; }
[[ ! -e "$root/install" ]] || { echo 'install dir not removed' >&2; exit 1; }

# full uninstall removes volumes and images too
mkdir -p "$root/install"
printf '# Nopeus Agent managed runtime\nservices: {}\n' > "$root/install/compose.yaml"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'install_dir=%q\nproject=%q\n' "$root/install" nopeus-agent
  cat "$root/launcher.body"
} > "$root/launchers/nopeus-agent"
chmod +x "$root/launchers/nopeus-agent"
: > "$DOCKER_LOG"
"$launcher" uninstall --yes > "$root/full.out"
grep -Fq 'down --volumes --rmi all --remove-orphans' "$DOCKER_LOG"
grep -Fq 'docker volume rm volume-1 volume-2' "$DOCKER_LOG"
grep -Fq 'docker rmi nopeus-agent-runtime:0.2.0-alpha.68 nopeus-agent-audio:0.2.0-alpha.68' "$DOCKER_LOG"
grep -Fq 'Nopeus Agent uninstalled and all data removed.' "$root/full.out"

# no terminal and no --yes is refused
mkdir -p "$root/install"
printf '# Nopeus Agent managed runtime\nservices: {}\n' > "$root/install/compose.yaml"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'install_dir=%q\nproject=%q\n' "$root/install" nopeus-agent
  cat "$root/launcher.body"
} > "$root/launchers/nopeus-agent"
chmod +x "$root/launchers/nopeus-agent"
: > "$DOCKER_LOG"
if "$launcher" uninstall < /dev/null > "$root/refuse.out" 2>&1; then
  echo 'uninstall without confirmation succeeded' >&2; exit 1
fi
grep -Fq 'Refusing to uninstall without a terminal' "$root/refuse.out"
[[ ! -s "$DOCKER_LOG" ]] || { echo 'refused uninstall called docker' >&2; exit 1; }

echo 'uninstall tests passed'
