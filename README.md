# ddns-ip-reporter

动态公网 IP 上报服务。客户端节点（家庭宽带、动态 IP 服务器等）定期向本服务上报自己的出口 IP，服务自动更新宿主机 Nginx 的变量配置并 reload，实现无需重启 Nginx 的动态反代。

## 架构

```
客户端节点（公网 IP 会变动）
    │
    │  POST /update
    │  Authorization: Bearer <token>
    │  Body: {"node": "home", "port": <port>}
    │  （IP 自动从请求来源识别，无需手动填写）
    ▼
ddns Docker 容器
    │  1. 验证 token
    │  2. 写入 /etc/nginx/conf.d/home_ip.conf
    │     → set $home_ip x.x.x.x;
    │  3. nginx -s reload（通过 pid: host 共享 PID namespace）
    ▼
宿主机 Nginx
    │  include /etc/nginx/conf.d/home_ip.conf;
    │  proxy_pass https://$home_ip:<port>;
    ▼
流量转发到最新的公网 IP
```

## 文件结构

```
ddns-ip-reporter/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── .gitignore
├── app/
│   ├── main.py              # Flask API 主程序
│   └── requirements.txt
└── .github/
    └── workflows/
        └── docker-publish.yml   # push 到 main 时自动构建推送 Docker Hub
```

---

## 一、服务端部署

### 1. 克隆仓库

```bash
git clone https://github.com/<your-username>/ddns-ip-reporter.git /docker/ddns-ip-reporter
cd /docker/ddns-ip-reporter
```

### 2. 创建 .env

先生成一个随机 token：

```bash
openssl rand -hex 32
# 输出示例：<your-generated-token>
```

复制 `.env.example` 并填入生成的值：

```bash
cp .env.example .env
nano .env
```

把 `CHANGE_ME_use_openssl_rand_hex_32` 替换为你自己的 token：

```env
DDNS_TOKEN=<your-generated-token>
```

> `.env` 已在 `.gitignore` 中排除，不会被提交到 Git。

### 3. 启动容器

```bash
docker compose up -d
```

### 4. 验证服务正常

```bash
curl http://localhost:8081/health
# {"status":"ok","time":"2026-06-08T10:00:00Z"}
```

### 5. 手动测试一次 IP 上报

```bash
curl -X POST http://localhost:8081/update \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"node": "home", "port": <your-port>}'
```

成功响应：

```json
{
  "status": "ok",
  "node": "home",
  "ip": "x.x.x.x",
  "port": 12345,
  "changed": true,
  "old_ip": null
}
```

验证 nginx conf 已写入：

```bash
cat /etc/nginx/conf.d/home_ip.conf
# set $home_ip x.x.x.x;
```

验证 nginx 正常：

```bash
nginx -t
```

---

## 二、Nginx 配置（宿主机）

`/etc/nginx/sites-available/your-site.conf` 结构示例：

```nginx
server {
    listen 443 ssl http2;
    server_name <your-domain>;

    ssl_certificate     /etc/ssl/<your-cert>.pem;
    ssl_certificate_key /etc/ssl/<your-cert>.key;

    # 引入由 ddns 自动维护的 IP 变量（不要手动编辑此文件）
    include /etc/nginx/conf.d/home_ip.conf;

    location / {
        proxy_pass https://$home_ip:<your-port>;
        proxy_ssl_server_name on;
        proxy_ssl_name <your-domain>;
        proxy_ssl_verify off;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_read_timeout 60s;
        proxy_connect_timeout 30s;
    }
}
```

**`/etc/nginx/conf.d/home_ip.conf` 由 ddns 容器自动维护，不要手动编辑。**

多节点示例：

```nginx
# 第二个节点，直接上报 node: "office"
# ddns 自动创建 /etc/nginx/conf.d/office_ip.conf
include /etc/nginx/conf.d/office_ip.conf;
proxy_pass https://$office_ip:<port>;
```

---

## 三、GitHub Actions 配置

### Build & Push 到 Docker Hub

在本仓库 **Settings → Secrets and variables → Actions** 添加：

| Secret | 说明 |
|--------|------|
| `DOCKERHUB_USERNAME` | 你的 Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub → Account Settings → Personal Access Tokens 生成 |

push 到 `main` 分支时自动触发，构建 `linux/amd64` + `linux/arm64` 双架构镜像。

---

## 四、客户端上报 IP

在客户端机器上用 cron 定时上报：

```bash
crontab -e
```

添加：

```
*/10 * * * * curl -sf -X POST https://<your-ddns-domain>/update \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"node":"home","port":<your-port>}' >> /var/log/ddns.log 2>&1
```

OpenWrt / 梅林路由器同样支持 cron，直接在路由器上配即可。

---

## 五、API 参考

所有接口（除 `/health`）需要鉴权，请求头加：

```
Authorization: Bearer <token>
```

### `POST /update` — 上报 IP

| 字段 | 必填 | 说明 |
|------|------|------|
| `node` | ✅ | 节点名（字母/数字/连字符/下划线） |
| `port` | ❌ | 目标端口，默认 80 |
| `ip` | ❌ | 显式指定 IP，不填则自动识别请求来源 IP |

### `GET /status` — 查看所有节点

```bash
curl -H "Authorization: Bearer <token>" https://<your-ddns-domain>/status
```

```json
{
  "home": {
    "ip": "x.x.x.x",
    "port": 12345,
    "updated": "2026-06-08T10:00:00Z"
  }
}
```

### `DELETE /node/<node>` — 删除节点

删除对应的 conf 文件并 reload nginx。

### `GET /health` — 健康检查（无需鉴权）

---

## 六、更新镜像

```bash
cd /docker/ddns-ip-reporter
docker compose pull
docker compose up -d
```

---

## 七、常见问题

**nginx reload 失败**

```bash
docker compose logs ddns
ls -la /run/nginx.pid
```

确认 `pid: host` 在 `docker-compose.yml` 中已启用。

**IP 识别不对**

流量经过 Cloudflare 时，ddns 优先读取 `CF-Connecting-IP` 头获取真实 IP。也可以在请求 body 里显式传 `"ip": "x.x.x.x"` 覆盖自动识别。

**多节点**

```
home   → /etc/nginx/conf.d/home_ip.conf   → set $home_ip   x.x.x.x;
office → /etc/nginx/conf.d/office_ip.conf → set $office_ip x.x.x.x;
jp     → /etc/nginx/conf.d/jp_ip.conf     → set $jp_ip     x.x.x.x;
```
