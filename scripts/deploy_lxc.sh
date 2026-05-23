#!/usr/bin/env bash
# deploy_lxc.sh <slug> <app_dir> [lxc_config.json]
#   - hetzner-master 에 LXC 생성/업데이트
#   - idempotent

set -euo pipefail

SLUG="${1:?slug required}"
APP_DIR="${2:?app_dir required}"
LXC_CONFIG="${3:-}"

[[ -f .env.research-design ]] && set -a && . .env.research-design && set +a
: "${HETZNER_MASTER_HOST:?HETZNER_MASTER_HOST required}"
: "${HETZNER_MASTER_USER:?HETZNER_MASTER_USER required}"

# Defaults
CONTAINER_NAME="rd-${SLUG//[^a-z0-9]/-}"
CONTAINER_NAME="${CONTAINER_NAME:0:63}"
LXC_CORES=1
LXC_MEMORY=1024
LXC_DISK=10
SYSTEMD_UNIT_NAME="research-engine-app.service"

# Override defaults from lxc_config.json if provided
if [[ -n "${LXC_CONFIG}" && -f "${LXC_CONFIG}" ]]; then
  _cn=$(jq -r '.container_name // empty' "${LXC_CONFIG}")
  [[ -n "${_cn}" ]] && CONTAINER_NAME="${_cn}"
  _cores=$(jq -r '.cores // empty' "${LXC_CONFIG}")
  [[ -n "${_cores}" ]] && LXC_CORES="${_cores}"
  _mem=$(jq -r '.memory_mb // empty' "${LXC_CONFIG}")
  [[ -n "${_mem}" ]] && LXC_MEMORY="${_mem}"
  _disk=$(jq -r '.disk_gb // empty' "${LXC_CONFIG}")
  [[ -n "${_disk}" ]] && LXC_DISK="${_disk}"
  _unit=$(jq -r '.systemd_unit_name // empty' "${LXC_CONFIG}")
  [[ -n "${_unit}" ]] && SYSTEMD_UNIT_NAME="${_unit}"
fi

REMOTE_APP="/opt/research-design/${SLUG}"

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "set -e; \
  if ! pct list | awk '{print \$3}' | grep -qx '${CONTAINER_NAME}'; then \
    NEXT_ID=\$(pvesh get /cluster/nextid); \
    pct create \$NEXT_ID local:vztmpl/debian-12-standard_*.tar.zst --hostname ${CONTAINER_NAME} --cores ${LXC_CORES} --memory ${LXC_MEMORY} --rootfs local-lvm:${LXC_DISK} --net0 name=eth0,bridge=vmbr0,ip=dhcp --features nesting=1 --unprivileged 1; \
    pct start \$NEXT_ID; \
  fi"

CTID=$(ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct list | awk '\$3==\"${CONTAINER_NAME}\" {print \$1}'")
[[ -n "${CTID}" ]] || { echo "[deploy] CTID not found" >&2; exit 1; }

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- bash -lc '
  set -e
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates gnupg unzip caddy
  if ! command -v node >/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y -qq nodejs
  fi
  npm i -g pnpm@9 >/dev/null
  if ! command -v tailscale >/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  mkdir -p ${REMOTE_APP}
'"

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- bash -lc '
  if ! tailscale status >/dev/null 2>&1; then
    echo \"[deploy] tailscale not authenticated in container. Run inside container: tailscale up --hostname=${CONTAINER_NAME}\"
    echo \"[deploy] Then re-run lxc_deploy.sh\"
    exit 10
  fi
  tailscale status | head -1
'"

APP_TAR=$(mktemp --suffix=.tar.gz)
tar -czf "${APP_TAR}" -C "${APP_DIR}" .
scp "${APP_TAR}" "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}:/tmp/${CONTAINER_NAME}.tar.gz"
ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct push ${CTID} /tmp/${CONTAINER_NAME}.tar.gz /tmp/app.tar.gz && pct exec ${CTID} -- bash -lc 'tar -xzf /tmp/app.tar.gz -C ${REMOTE_APP} && cd ${REMOTE_APP} && pnpm install --frozen-lockfile && pnpm build'"
rm -f "${APP_TAR}"

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- bash -lc '
  cat > /etc/systemd/system/${SYSTEMD_UNIT_NAME} <<EOF
[Unit]
Description=research-engine app (${SLUG})
After=network.target
[Service]
WorkingDirectory=${REMOTE_APP}
Environment=PORT=3000
ExecStart=/usr/bin/pnpm start
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now ${SYSTEMD_UNIT_NAME}
  systemctl restart ${SYSTEMD_UNIT_NAME}

  cat > /etc/caddy/Caddyfile <<EOF
:443 {
  reverse_proxy 127.0.0.1:3000
  tls internal
}
:80 {
  redir https://{host}{uri}
}
EOF
  systemctl restart caddy
'"

HOST=$(ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- tailscale status --json | jq -r '.Self.DNSName // .Self.HostName'")
echo "${HOST}"
