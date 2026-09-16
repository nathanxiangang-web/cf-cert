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
后续由 acme.sh 自动续期
```

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

## 安全说明

- Cloudflare API Token 输入时不会明文显示。
- 建议 Token 只授予目标 Zone 的 DNS Edit 权限。
- 不要把 API Token 提交到 GitHub。
- 一键命令会直接执行远程脚本；如需先审查代码，可先打开 `cf-cert.sh` 查看后再运行。

## 环境

推荐 Linux 服务器，以 root 权限运行。脚本需要 `curl`；如果系统存在 Nginx，会在证书安装后执行配置检查和 reload。

## License

MIT
