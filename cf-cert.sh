#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[INFO] %s\n' "$*"
}

die() {
  echo
  echo "[ERROR] $*" >&2
  exit 1
}

on_err() {
  local rc=$?
  echo "[ERROR] 脚本执行失败（退出码：$rc，行号：${BASH_LINENO[0]:-unknown}）" >&2
  exit "$rc"
}
trap on_err ERR

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

  acme.sh 安装/检查
  -> Cloudflare DNS-01 验证
  -> Let's Encrypt 签发
  -> 根域名 + 泛域名证书
  -> 安装证书
  -> Nginx reload（如检测到 Nginx）
  -> 配置/检查自动续期
  -> 验证证书和私钥

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
FULLCHAIN="${CERT_DIR}/fullchain.pem"
PRIVKEY="${CERT_DIR}/privkey.pem"

echo
echo "申请内容："
echo "  ${DOMAIN}"
echo "  *.${DOMAIN}"
echo

echo "[1/6] 检查 acme.sh..."
if [ ! -x "$ACME" ]; then
  command -v curl >/dev/null 2>&1 || die "未检测到 curl，请先安装 curl"
  log "正在安装 acme.sh..."
  curl -fsSL https://get.acme.sh | sh
fi

[ -x "$ACME" ] || die "acme.sh 安装失败"

echo "[2/6] 设置 Let's Encrypt..."
"$ACME" --set-default-ca --server letsencrypt

echo "[3/6] 申请/检查证书..."
ISSUE_RC=0
if "$ACME" \
  --issue \
  --server letsencrypt \
  --dns dns_cf \
  -d "$DOMAIN" \
  -d "*.${DOMAIN}" \
  --keylength ec-256; then
  ISSUE_RC=0
else
  ISSUE_RC=$?
fi

case "$ISSUE_RC" in
  0)
    log "证书申请或续期成功"
    ;;
  2)
    log "现有证书仍在有效期内，本次无需重新签发，继续安装/校验现有证书"
    ;;
  *)
    die "证书申请失败，acme.sh 返回码：$ISSUE_RC"
    ;;
esac

echo "[4/6] 安装证书..."
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
  --key-file "$PRIVKEY" \
  --fullchain-file "$FULLCHAIN" \
  --reloadcmd "$RELOAD_CMD"

[ -s "$PRIVKEY" ] || die "私钥安装失败：$PRIVKEY"
[ -s "$FULLCHAIN" ] || die "证书安装失败：$FULLCHAIN"

chmod 600 "$PRIVKEY"
chmod 644 "$FULLCHAIN"

echo "[5/6] 检查自动续期..."
if ! crontab -l 2>/dev/null | grep -Fq '/root/.acme.sh/acme.sh'; then
  log "未发现 acme.sh cron，正在补充安装自动续期任务..."
  "$ACME" --install-cronjob
fi

if crontab -l 2>/dev/null | grep -Fq '/root/.acme.sh/acme.sh'; then
  log "自动续期任务已配置"
else
  die "未检测到 acme.sh 自动续期 cron，请手动检查 crontab"
fi

echo "[6/6] 验证证书..."
if command -v openssl >/dev/null 2>&1; then
  openssl x509 -in "$FULLCHAIN" -noout >/dev/null 2>&1 || die "证书文件无法被 openssl 解析"

  CERT_PUBKEY="$(openssl x509 -in "$FULLCHAIN" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform pem 2>/dev/null | sha256sum | awk '{print $1}')"
  KEY_PUBKEY="$(openssl pkey -in "$PRIVKEY" -pubout -outform pem 2>/dev/null | sha256sum | awk '{print $1}')"

  if [ -z "$CERT_PUBKEY" ] || [ "$CERT_PUBKEY" != "$KEY_PUBKEY" ]; then
    die "证书与私钥不匹配"
  fi
  log "证书与私钥匹配"
else
  log "未检测到 openssl，跳过证书内容校验"
fi

cat <<EOF

============================================================
证书配置完成

域名：
  ${DOMAIN}
  *.${DOMAIN}

证书：
  ${FULLCHAIN}

私钥：
  ${PRIVKEY}

Nginx：
  ssl_certificate     ${FULLCHAIN};
  ssl_certificate_key ${PRIVKEY};

自动续期：
  acme.sh cron 已检查并启用
============================================================

EOF

if command -v openssl >/dev/null 2>&1; then
  openssl x509 \
    -in "$FULLCHAIN" \
    -noout \
    -issuer \
    -subject \
    -dates \
    -ext subjectAltName || true
fi
