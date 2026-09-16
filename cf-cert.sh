#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  echo
  echo "[ERROR] $*" >&2
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  die "请使用 root 运行，例如：curl -fsSL <RAW_URL> | sudo bash"
fi

TTY="/dev/tty"
[ -r "$TTY" ] || die "未检测到可交互终端"

clear 2>/dev/null || true

cat <<'EOF'
============================================================
        Cloudflare SSL 证书一键申请
============================================================

准备以下 3 项：

  1. 域名，例如：example.com
  2. Cloudflare Zone ID
  3. Cloudflare API Token

API Token 建议权限：

  Zone -> DNS -> Edit

并仅授权需要申请证书的 Zone。

脚本会自动完成：

  acme.sh 安装
  -> Cloudflare DNS-01 验证
  -> Let's Encrypt 签发
  -> 根域名 + 泛域名证书
  -> 安装证书
  -> Nginx reload（如检测到 Nginx）
  -> 配置后续自动续期

============================================================

EOF

printf "域名（例如 example.com）: " >"$TTY"
IFS= read -r DOMAIN <"$TTY"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%%/*}"
DOMAIN="${DOMAIN%.}"
DOMAIN="${DOMAIN,,}"

[ -n "$DOMAIN" ] || die "域名不能为空"

if ! [[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]]; then
  die "域名格式不正确：$DOMAIN"
fi

printf "Cloudflare Zone ID: " >"$TTY"
IFS= read -r CF_Zone_ID <"$TTY"

printf "Cloudflare API Token: " >"$TTY"
IFS= read -r -s CF_Token <"$TTY"
printf "\n" >"$TTY"

[ -n "$CF_Zone_ID" ] || die "Zone ID 不能为空"
[ -n "$CF_Token" ] || die "API Token 不能为空"

export CF_Zone_ID CF_Token

ACME="/root/.acme.sh/acme.sh"
CERT_DIR="/etc/ssl/${DOMAIN}"

echo
echo "申请内容："
echo "  ${DOMAIN}"
echo "  *.${DOMAIN}"
echo

echo "[1/5] 检查 acme.sh..."
if [ ! -x "$ACME" ]; then
  command -v curl >/dev/null 2>&1 || die "未检测到 curl，请先安装 curl"
  echo "[INFO] 正在安装 acme.sh..."
  curl -fsSL https://get.acme.sh | sh
fi

[ -x "$ACME" ] || die "acme.sh 安装失败"

echo "[2/5] 设置 Let's Encrypt..."
"$ACME" --set-default-ca --server letsencrypt

echo "[3/5] 申请证书..."
"$ACME" \
  --issue \
  --server letsencrypt \
  --dns dns_cf \
  -d "$DOMAIN" \
  -d "*.${DOMAIN}" \
  --keylength ec-256

echo "[4/5] 安装证书..."
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

RELOAD_CMD="true"
if command -v nginx >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1; then
    RELOAD_CMD="nginx -t && systemctl reload nginx"
  else
    RELOAD_CMD="nginx -t && nginx -s reload"
  fi
fi

"$ACME" \
  --install-cert \
  -d "$DOMAIN" \
  --ecc \
  --key-file "$CERT_DIR/privkey.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --reloadcmd "$RELOAD_CMD"

chmod 600 "$CERT_DIR/privkey.pem"
chmod 644 "$CERT_DIR/fullchain.pem"

echo "[5/5] 完成"

cat <<EOF

============================================================
证书申请成功

域名：
  ${DOMAIN}
  *.${DOMAIN}

证书：
  ${CERT_DIR}/fullchain.pem

私钥：
  ${CERT_DIR}/privkey.pem

Nginx：
  ssl_certificate     ${CERT_DIR}/fullchain.pem;
  ssl_certificate_key ${CERT_DIR}/privkey.pem;

后续由 acme.sh 自动续期。
============================================================

EOF

if command -v openssl >/dev/null 2>&1; then
  openssl x509 \
    -in "$CERT_DIR/fullchain.pem" \
    -noout \
    -issuer \
    -subject \
    -dates \
    -ext subjectAltName || true
fi
