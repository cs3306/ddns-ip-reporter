FROM python:3.12-alpine

# nginx binary needed for `nginx -t` and `nginx -s reload`
# these talk to the HOST nginx via the bind-mounted /run/nginx.pid / unix socket
RUN apk add --no-cache nginx

WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/main.py .

EXPOSE 8080

CMD ["gunicorn", "main:app", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "2", \
     "--timeout", "30", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
