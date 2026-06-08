FROM python:3.12-alpine

# Install nginx and supervisord
RUN apk add --no-cache nginx supervisor

# Create required directories
RUN mkdir -p /run/nginx \
             /etc/nginx/ddns \
             /etc/nginx/sites \
             /etc/nginx/certs \
             /var/log/nginx \
             /data

# Install Python dependencies
WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/main.py .

# nginx config
COPY nginx/conf/nginx.conf /etc/nginx/nginx.conf

# supervisord config
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 80 443

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
