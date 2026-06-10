FROM python:3.12-alpine

RUN apk add --no-cache nginx supervisor

RUN mkdir -p /run/nginx \
             /etc/nginx/ddns \
             /etc/nginx/sites \
             /etc/nginx/certs \
             /var/log/nginx \
             /data

WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/main.py .
COPY nginx/conf/nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
