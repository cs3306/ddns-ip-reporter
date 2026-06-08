# ddns-ip-reporter

动态公网 IP 上报服务，内置 nginx。客户端定期上报 IP，服务自动更新 nginx 配置并 reload。用户只需提供自己的 nginx server 块配置和证书，无需在宿主机安装任何依赖。

## 架构

```
客户端（IP 会变动）
    │  POST /update  {"node": "home", "port": 443}
    │  Authorization: Bearer <token>
    ▼
容器（nginx + Flask API）
    │  写入 nginx/ddns/home_ip.conf
    │     → set $home_ip x.x.x.x;
    │  nginx -s reload
    ▼
nginx 用最新 IP 转发流量
```

## 目录结构

```
ddns-ip-reporter/
├── docker-compose.yml
├── .env.example
├── nginx/
│   ├── sites/                  # ← 放你自己的 server 块配置
│   │   └── example.conf.template
│   ├── certs/                  # ← 放你的 SSL 证书（不提交到 git）
│   └── ddns/                   # ← 自动生成，不要手动编辑
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
nano .env   # 填入 openssl rand -hex 32 生成的 token
```

### 3. 放入 nginx 配置

参考 `nginx/sites/example.conf.template`，在 `nginx/sites/` 下创建自己的配置文件：

```nginx
# nginx/sites/my-site.conf
server {
    listen 443 ssl http2;
    server_name <your-domain>;

    ssl_certificate     /etc/nginx/certs/<your-domain>.pem;
    ssl_certificate_key /etc/nginx/certs/<your-domain>.key;

    # $home_ip 由 ddns 自动维护，node 名称对应变量前缀
    location / {
        proxy_pass https://$home_ip:<port>;
        proxy_ssl_server_name on;
        proxy_ssl_name <your-domain>;
        proxy_ssl_verify off;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

### 4. 放入证书

```bash
cp your-domain.pem nginx/certs/
cp your-domain.key nginx/certs/
```

### 5. 启动

```bash
docker compose up -d
```

### 6. 验证

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
*/10 * * * * curl -sf -X POST https://<your-domain>/update \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"node":"home","port":443}' >> /var/log/ddns.log 2>&1
```

`node` 名称决定变量名：`home` → `$home_ip`，`office` → `$office_ip`。

---

## API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/health` | 健康检查（无需鉴权） |
| POST | `/update` | 上报 IP |
| GET | `/status` | 查看所有节点当前 IP |
| DELETE | `/node/<node>` | 删除节点 |

鉴权方式：`Authorization: Bearer <token>`

---

## 更新镜像

```bash
docker compose pull && docker compose up -d
```
