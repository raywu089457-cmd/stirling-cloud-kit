#!/usr/bin/env bash
#
# Stirling PDF 雲端部署包 — 一鍵安裝腳本
# 適用：全新 Ubuntu 22.04 / 24.04 VM（Oracle Cloud、Hetzner、Vultr 都可以）
#
# 用法：
#   TS_AUTHKEY="tskey-auth-xxxxx" bash setup.sh
#
# 沒有 TS_AUTHKEY 也能跑，會印出一個網址讓你點進去登入 Tailscale。

set -euo pipefail

TS_AUTHKEY="${TS_AUTHKEY:-}"
TS_HOSTNAME="${TS_HOSTNAME:-stirling-vm}"
APP_DIR="${APP_DIR:-/opt/stirling}"
SERVE_PORT="${SERVE_PORT:-8080}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m[!] %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

# ---------------------------------------------------------------- 1. Docker
log "安裝 Docker"
if command -v docker >/dev/null 2>&1; then
  echo "已經裝了，跳過"
else
  curl -fsSL https://get.docker.com | $SUDO sh
fi
$SUDO systemctl enable --now docker

if ! docker compose version >/dev/null 2>&1; then
  warn "docker compose plugin 不見了，嘗試補裝"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y docker-compose-plugin
fi

# 讓目前的非 root 使用者不用 sudo 也能跑 docker
if [ -n "$SUDO" ] && ! id -nG "$USER" | grep -qw docker; then
  $SUDO usermod -aG docker "$USER"
  warn "已把你加入 docker 群組。重新登入後才生效（這次安裝仍會用 sudo）。"
fi

# ------------------------------------------------------------- 2. Tailscale
log "安裝 Tailscale"
if command -v tailscale >/dev/null 2>&1; then
  echo "已經裝了，跳過"
else
  curl -fsSL https://tailscale.com/install.sh | sh
fi

log "加入你的 tailnet"
if [ -n "$TS_AUTHKEY" ]; then
  $SUDO tailscale up --authkey "$TS_AUTHKEY" --hostname "$TS_HOSTNAME" --ssh --accept-routes=false
else
  warn "沒有提供 TS_AUTHKEY，等等要點網址登入"
  $SUDO tailscale up --hostname "$TS_HOSTNAME" --ssh --accept-routes=false
fi

TS_IP="$($SUDO tailscale ip -4 2>/dev/null | head -1 || true)"
echo "這台機器的 Tailscale IP：${TS_IP:-未知}"

# ------------------------------------------------------------ 3. Stirling PDF
log "準備 Stirling PDF"
mkdir -p "$APP_DIR/data/configs" "$APP_DIR/data/tessdata" "$APP_DIR/data/logs"
cd "$APP_DIR"

if [ ! -f docker-compose.yml ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    cp "$SCRIPT_DIR/docker-compose.yml" .
  else
    warn "找不到 docker-compose.yml，請手動放到 $APP_DIR"
    exit 1
  fi
fi

$SUDO docker compose up -d

log "等服務起來（第一次要拉 image，可能要幾分鐘）"
for i in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://localhost:8080/api/v1/info/status" 2>/dev/null; then
    echo "服務活了！"
    break
  fi
  [ "$i" -eq 60 ] && warn "等超過 5 分鐘，先繼續，等等用 log 檢查"
  sleep 5
done

# ------------------------------------------------- 4. 用 Tailscale 代理出去
log "設定 Tailscale 代理（不對外開 port）"
$SUDO tailscale serve --bg --http="$SERVE_PORT" "http://127.0.0.1:8080" || {
  warn "tailscale serve 失敗。可能是 tailnet 沒開 HTTPS/MagicDNS。"
  warn "手動重試：sudo tailscale serve --bg --http=$SERVE_PORT http://127.0.0.1:8080"
}

DNS_NAME="$($SUDO tailscale status --json 2>/dev/null \
  | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//' || true)"

cat <<EOF

────────────────────────────────────────────────
  裝好了
────────────────────────────────────────────────

  打開這個網址（你的裝置要先連上 Tailscale）：

    http://${TS_HOSTNAME}.<你的-tailnet>.ts.net:${SERVE_PORT}
$( [ -n "$DNS_NAME" ] && echo "
  完整網址應該是：

    http://${DNS_NAME}:${SERVE_PORT}
" )
  只有你自己 tailnet 裡的裝置連得到，網際網路掃不到。

  常用指令：
    cd $APP_DIR
    sudo docker compose logs -f      # 看 log
    sudo docker compose restart      # 重啟
    sudo docker compose down         # 關掉

  資料放在：
    $APP_DIR/data/configs            # 設定、資料庫
    $APP_DIR/data/logs               # log

────────────────────────────────────────────────
EOF
