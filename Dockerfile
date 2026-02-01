FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

RUN apk add --no-cache wget unzip ca-certificates supervisor curl

# Install latest Caddy v2 (raw binary download)
RUN curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" \
  -o /usr/local/bin/caddy \
  && chmod +x /usr/local/bin/caddy \
  && /usr/local/bin/caddy version

# Download IBKR gateway
RUN wget https://download2.interactivebrokers.com/portal/clientportal.gw.zip \
    && unzip clientportal.gw.zip -d . \
    && rm clientportal.gw.zip

COPY conf.yaml root/conf.yaml

# Caddy v2 config (443 only)
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
