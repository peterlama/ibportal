FROM openjdk:8u212-jre-alpine3.9

WORKDIR /app

RUN apk add --no-cache wget unzip ca-certificates supervisor

# latest Caddy v2
RUN wget -qO- https://caddyserver.com/api/download?os=linux&arch=amd64 \
    | tar -xz -C /usr/local/bin caddy \
    && chmod +x /usr/local/bin/caddy

# IBKR gateway
RUN wget https://download2.interactivebrokers.com/portal/clientportal.gw.zip \
    && unzip clientportal.gw.zip -d . \
    && rm clientportal.gw.zip

COPY conf.yaml root/conf.yaml

# Caddy config
RUN <<'EOF' cat > /etc/caddy/Caddyfile
:443 {
    tls internal
    reverse_proxy https://127.0.0.1:5000 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF

# Supervisor config
RUN <<'EOF' cat > /etc/supervisord.conf
[supervisord]
nodaemon=true

[program:ibkr_gateway]
directory=/app
command=sh bin/run.sh root/conf.yaml
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:caddy]
command=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

EXPOSE 443

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
