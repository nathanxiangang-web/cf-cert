# cf-cert

Cloudflare DNS + Let's Encrypt 一键申请 SSL 证书脚本。

适合已经把域名 DNS 托管到 Cloudflare 的用户。运行后只需要输入：

1. 域名，例如 `example.com`
2. Cloudflare Zone ID
3. Cloudflare API Token

脚本会自动申请：

```text
example.com
*.example.com
```

并将证书安装到：

```text
/etc/ssl/example.com/fullchain.pem
/etc/ssl/example.com/privkey.pem
```

## 一键使用

```bash
curl -fsSL https://raw.githubusercontent.com/nathanxiangang-web/cf-cert/main/cf-cert.sh | sudo bash
```

运行后按提示输入：

```text
域名（例如 example.com）: example.com
Cloudflare Zone ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Cloudflare API Token:
```

> API Token 输入时终端不会显示字符，直接粘贴后按 Enter 即可。

## Cloudflare API Token 权限

建议创建专用 Token，不要使用 Global API Key。

权限：

```text
Zone -> DNS -> Edit
```

资源范围建议限制到目标域名：

```text
Zone Resources
Include
Specific zone
example.com
```

Zone ID 可在 Cloudflare 对应域名的 `Overview` 页面找到。

## 自动完成的操作

```text
检查 root 权限
    ↓
安装/检查 acme.sh
    ↓
调用 Cloudflare DNS API
    ↓
自动创建 ACME DNS 验证记录
    ↓
Let's Encrypt DNS-01 验证
    ↓
签发 根域名 + *.泛域名 证书
    ↓
安装 fullchain.pem / privkey.pem
    ↓
检测到 Nginx 时自动 reload
    ↓
检查 acme.sh 自动续期 cron
    ↓
校验证书文件及证书/私钥匹配
```

## 重复运行

脚本支持重复执行。

当同一组域名已经存在有效证书且尚未进入续期窗口时，acme.sh 会返回 `2`（skipped）。脚本会把它视为正常状态，并继续：

```text
检查现有证书
    ↓
重新确认安装路径
    ↓
检查自动续期 cron
    ↓
验证证书与私钥
```

因此重复运行不会因为 `Domains not changed. Skipping.` 而提前退出，也不会强制向 Let's Encrypt 重复签发证书。

如确实需要强制重新签发，应直接使用 acme.sh 的 `--force`，不建议日常使用。

## 自动续期

acme.sh 安装时通常会自动创建 cron。脚本还会额外检查 root 的 crontab；若没有发现 acme.sh 的续期任务，会执行：

```bash
/root/.acme.sh/acme.sh --install-cronjob
```

可手动检查：

```bash
crontab -l | grep acme.sh
```

acme.sh 会定期检查证书，进入续期窗口后自动完成 DNS-01 验证、更新已安装证书，并执行保存的 reload command。

## Nginx 配置

假设输入的域名是 `example.com`：

```nginx
ssl_certificate     /etc/ssl/example.com/fullchain.pem;
ssl_certificate_key /etc/ssl/example.com/privkey.pem;
```

例如：

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    ssl_certificate     /etc/ssl/example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
```

## 证书覆盖范围

如果输入 `example.com`，会申请 `example.com` 与 `*.example.com`。

可以覆盖：

```text
example.com
www.example.com
api.example.com
pan.example.com
```

不能覆盖：

```text
a.api.example.com
```

因为 `*.example.com` 只匹配一级子域名。

## 手动检查证书

```bash
openssl x509 \
  -in /etc/ssl/example.com/fullchain.pem \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName
```

查看 acme.sh 管理的证书：

```bash
/root/.acme.sh/acme.sh --list
```

## 安全说明

- Cloudflare API Token 输入时不会明文显示。
- 建议 Token 只授予目标 Zone 的 DNS Edit 权限。
- 不要把 API Token 提交到 GitHub。
- 私钥安装后权限为 `600`，域名证书目录权限为 `700`。
- 一键命令会直接执行远程脚本；如需先审查代码，可先打开 `cf-cert.sh` 查看后再运行。

## 环境

推荐 Linux 服务器，以 root 权限运行。脚本需要 `curl`；如果系统存在 Nginx，会在证书安装后执行配置检查和 reload。若安装了 `openssl`，脚本会额外验证证书可解析，并确认公钥与私钥匹配。

## License

Apache License 2.0
