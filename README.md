# ddns-ip-reporter

[English](#english) | [中文](#中文)

---

## English

A self-hosted dynamic IP reporting service with built-in nginx. Client nodes periodically report their public IP; the service automatically updates nginx config and reloads. Supports two deployment modes depending on whether you have a host nginx.

### How It Works

```
Client node (dynamic IP)
    │  POST /update  {"node": "home", "port": 443}
    │  Authorization: Bearer <token>
    │  (IP auto-detected from request source)
    ▼
Container (Alpine nginx + Flask API, managed by supervisord)
    │  1. Validate token
    │  2. Write nginx/ddns/home_ip.conf
    │     → set $home_ip x.x.x.x;
    │  3. Send SIGHUP to nginx (reload without restart)
    ▼
nginx serves traffic to the latest IP
```

### Directory Structure

```
ddns-ip-reporter/
├── docker-compose.yml
├── .env.example
├── nginx/
│   ├── sites/          # ← Your location block configs (one per node)
│   ├── certs/          # ← SSL certificates (not committed to git)
│   └── ddns/           # ← Auto-generated IP variable files (do not edit)
├── app/
│   └── main.py
└── .github/
    └── workflows/
        └── docker-publish.yml
```

---

## Deployment

### 1. Clone

```bash
git clone https://github.com/<your-username>/ddns-ip-reporter.git
cd ddns-ip-reporter
```

### 2. Configure token

```bash
cp .env.example .env
nano .env   # Fill in a token: openssl rand -hex 32
```

### 3. Choose a deployment mode

---

## Mode 1: Standalone (no host nginx)

Container nginx handles SSL and traffic directly. Users put their full server block configs in `nginx/sites/`.

> ⚠️ **Note**: LuCI (OpenWrt/ImmortalWrt web UI) and similar apps use hardcoded absolute paths and **cannot** be served under a path prefix (e.g. `/router/`). Use a dedicated subdomain per device instead.

**docker-compose.yml** — expose ports 80 and 443:

```yaml
ports:
  - "80:80"
  - "443:443"
```

**nginx/sites/cahome.conf** — full server block with SSL:

```nginx
server {
    listen 443 ssl http2;
    server_name cahome.example.com;

    ssl_certificate     /etc/nginx/certs/example.com.pem;
    ssl_certificate_key /etc/nginx/certs/example.com.key;

    # $cahome_ip is auto-maintained by ddns
    location / {
        proxy_pass https://$cahome_ip:<port>;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_ssl_name cahome.example.com;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 60s;
        proxy_connect_timeout 30s;
    }
}
```

**nginx/certs/** — place your certificates here:

```bash
cp example.com.pem nginx/certs/
cp example.com.key nginx/certs/
```

---

## Mode 2: Behind host nginx (recommended if host nginx already exists)

Container only handles IP reporting API. Host nginx handles SSL, domain routing, and proxying to backend nodes.

**docker-compose.yml** — expose only to localhost:

```yaml
ports:
  - "127.0.0.1:8080:80"
```

**Host nginx** — one server block per subdomain, reads the auto-generated IP variable file:

```nginx
# /etc/nginx/sites-available/cahome.conf
server {
    listen 443 ssl http2;
    server_name cahome.example.com;

    ssl_certificate     /etc/ssl/example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/example.com/key.pem;

    # Include the auto-generated IP variable (managed by ddns container)
    include /path/to/ddns-ip-reporter/nginx/ddns/cahome_ip.conf;

    location / {
        proxy_pass https://$cahome_ip:<port>;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_ssl_name cahome.example.com;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 60s;
        proxy_connect_timeout 30s;
    }
}

# ddns API entry point
server {
    listen 443 ssl http2;
    server_name ddns.example.com;

    ssl_certificate     /etc/ssl/example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/example.com/key.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header CF-Connecting-IP $http_cf_connecting_ip;
    }
}
```

### Multiple nodes (multiple routers/servers)

Each node gets its own subdomain and IP variable file:

```
node=cahome  → nginx/ddns/cahome_ip.conf  → set $cahome_ip  x.x.x.x;
node=office  → nginx/ddns/office_ip.conf  → set $office_ip  x.x.x.x;
node=jp      → nginx/ddns/jp_ip.conf      → set $jp_ip      x.x.x.x;
```

Add one host nginx server block per node, each including its own `_ip.conf` file.

---

## Start

```bash
docker compose up -d
```

Verify:

```bash
curl http://localhost/health
# {"status":"ok"}
```

---

## Client IP Reporting

Add a cron job on the client machine (home router, dynamic IP server, etc.):

```bash
crontab -e
```

```
*/10 * * * * curl -sf -X POST https://<your-ddns-domain>/update \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"node":"cahome","port":443}' >> /var/log/ddns.log 2>&1
```

`node` name determines the variable: `cahome` → `$cahome_ip`, `office` → `$office_ip`.

---

## API Reference

All endpoints except `/health` require: `Authorization: Bearer <token>`

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (no auth) |
| POST | `/update` | Report IP |
| GET | `/status` | View all nodes and current IPs |
| DELETE | `/node/<node>` | Remove a node |

### POST /update

| Field | Required | Description |
|-------|----------|-------------|
| `node` | ✅ | Node name (alphanumeric, hyphens, underscores) |
| `port` | ❌ | Target port, default 80 |
| `ip` | ❌ | Explicit IP, auto-detected if omitted |

### GET /status

```json
{
  "cahome": {
    "ip": "x.x.x.x",
    "port": 443,
    "updated": "2026-06-10T00:00:00Z"
  }
}
```

---

## Update Image

```bash
docker compose pull && docker compose up -d
```

---

## GitHub Actions

Add to repository **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub Personal Access Token |

Push to `main` to automatically build and push `linux/amd64` + `linux/arm64` images.

---

## 中文

动态公网 IP 上报服务，内置 nginx。客户端定期上报 IP，服务自动更新 nginx 配置并 reload。支持两种部署模式，根据是否有宿主机 nginx 灵活选择。

### 工作原理

```
客户端（IP 会变动）
    │  POST /update  {"node": "cahome", "port": 443}
    │  Authorization: Bearer <token>
    │  （IP 自动从请求来源识别）
    ▼
容器（Alpine nginx + Flask API，由 supervisord 管理）
    │  1. 验证 token
    │  2. 写入 nginx/ddns/cahome_ip.conf
    │     → set $cahome_ip x.x.x.x;
    │  3. 向 nginx 发送 SIGHUP（热重载，不重启）
    ▼
nginx 用最新 IP 转发流量
```

### 目录结构

```
ddns-ip-reporter/
├── docker-compose.yml
├── .env.example
├── nginx/
│   ├── sites/          # ← 放你的 location 块配置（每个节点一个）
│   ├── certs/          # ← 放 SSL 证书（不提交到 git）
│   └── ddns/           # ← 自动生成的 IP 变量文件（勿手动编辑）
├── app/
│   └── main.py
└── .github/
    └── workflows/
        └── docker-publish.yml
```

---

## 部署

### 1. 克隆仓库

```bash
git clone https://github.com/<your-username>/ddns-ip-reporter.git
cd ddns-ip-reporter
```

### 2. 配置 token

```bash
cp .env.example .env
nano .env   # 填入：openssl rand -hex 32
```

### 3. 选择部署模式

---

## 模式一：独立部署（宿主机无 nginx）

容器 nginx 直接处理 SSL 和流量，用户把完整的 server 块配置放到 `nginx/sites/`。

> ⚠️ **注意**：LuCI（OpenWrt/ImmortalWrt 管理界面）等应用使用硬编码绝对路径，**无法**通过路径前缀（如 `/router/`）访问。每台设备请使用独立子域名。

**docker-compose.yml** — 暴露 80 和 443：

```yaml
ports:
  - "80:80"
  - "443:443"
```

**nginx/sites/cahome.conf** — 完整 server 块：

```nginx
server {
    listen 443 ssl http2;
    server_name cahome.example.com;

    ssl_certificate     /etc/nginx/certs/example.com.pem;
    ssl_certificate_key /etc/nginx/certs/example.com.key;

    # $cahome_ip 由 ddns 自动维护
    location / {
        proxy_pass https://$cahome_ip:<port>;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_ssl_name cahome.example.com;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 60s;
        proxy_connect_timeout 30s;
    }
}
```

**nginx/certs/** — 放入证书：

```bash
cp example.com.pem nginx/certs/
cp example.com.key nginx/certs/
```

---

## 模式二：宿主机 nginx 反代（推荐，已有宿主机 nginx 时）

容器只负责 IP 上报 API，宿主机 nginx 处理 SSL、域名分流和流量转发。

**docker-compose.yml** — 只监听本地：

```yaml
ports:
  - "127.0.0.1:8080:80"
```

**宿主机 nginx** — 每个子域名一个 server 块，include 对应的 IP 变量文件：

```nginx
# /etc/nginx/sites-available/cahome.conf
server {
    listen 443 ssl http2;
    server_name cahome.example.com;

    ssl_certificate     /etc/ssl/example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/example.com/key.pem;

    # 引入由 ddns 容器自动维护的 IP 变量文件
    include /path/to/ddns-ip-reporter/nginx/ddns/cahome_ip.conf;

    location / {
        proxy_pass https://$cahome_ip:<port>;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_ssl_name cahome.example.com;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 60s;
        proxy_connect_timeout 30s;
    }
}

# ddns API 入口
server {
    listen 443 ssl http2;
    server_name ddns.example.com;

    ssl_certificate     /etc/ssl/example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/example.com/key.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header CF-Connecting-IP $http_cf_connecting_ip;
    }
}
```

### 多节点（多台路由器/服务器）

每个节点对应独立的子域名和 IP 变量文件：

```
node=cahome  → nginx/ddns/cahome_ip.conf  → set $cahome_ip  x.x.x.x;
node=office  → nginx/ddns/office_ip.conf  → set $office_ip  x.x.x.x;
node=jp      → nginx/ddns/jp_ip.conf      → set $jp_ip      x.x.x.x;
```

每个节点在宿主机 nginx 里加一个 server 块，include 对应的变量文件即可。

---

## 启动

```bash
docker compose up -d
```

验证：

```bash
curl http://localhost/health
# {"status":"ok"}
```

---

## 客户端上报 IP

在客户端机器（家庭路由器、动态 IP 服务器等）上加 cron：

```bash
crontab -e
```

```
*/10 * * * * curl -sf -X POST https://<your-ddns-domain>/update \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"node":"cahome","port":443}' >> /var/log/ddns.log 2>&1
```

`node` 名称决定变量名：`cahome` → `$cahome_ip`，`office` → `$office_ip`。

---

## API 参考

所有接口（除 `/health`）需要鉴权：`Authorization: Bearer <token>`

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/health` | 健康检查（无需鉴权） |
| POST | `/update` | 上报 IP |
| GET | `/status` | 查看所有节点当前 IP |
| DELETE | `/node/<node>` | 删除节点 |

### POST /update

| 字段 | 必填 | 说明 |
|------|------|------|
| `node` | ✅ | 节点名（字母/数字/连字符/下划线） |
| `port` | ❌ | 目标端口，默认 80 |
| `ip` | ❌ | 显式指定 IP，不填则自动识别 |

---

## 更新镜像

```bash
docker compose pull && docker compose up -d
```

## GitHub Actions 配置

在仓库 **Settings → Secrets and variables → Actions** 添加：

| Secret | 说明 |
|--------|------|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub Personal Access Token |

push 到 `main` 自动构建 `linux/amd64` + `linux/arm64` 双架构镜像。
