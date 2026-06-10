FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    nginx \
    python3 \
    python3-pip \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/nginx \
             /etc/nginx/ddns \
             /etc/nginx/sites \
             /etc/nginx/certs \
             /var/log/nginx \
             /data

WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt --break-system-packages

COPY app/main.py .
COPY nginx/conf/nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
