FROM openjdk:8u212-jre-alpine3.9

WORKDIR /app

# Install deps
RUN apk add --no-cache wget unzip ca-certificates caddy supervisor

# Download IBKR gateway
RUN wget https://download2.interactivebrokers.com/portal/clientportal.gw.zip \
    && unzip clientportal.gw.zip -d . \
    && rm clientportal.gw.zip

# ---- Inline Caddyfile (TLS on :443 only) ----
# Use real certs if DOMAIN+CADDY_EMAIL set, else internal self-signed
RUN <<'EOF' cat > /etc/caddy/Caddyfile
{
    auto_https disable_redirects
}

:443 {
    tls internal

    reverse_proxy https://127.0.0.1:5000 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF

# ---- Inline supervisord.conf ----
RUN <<'EOF' cat > /etc/supervisord.conf
RUN <<'EOF' cat > /etc/supervisord.conf
[supervisord]
nodaemon=true

[program:ibkr_gateway]
directory=/app/bin
command=sh run.sh root/conf.yaml
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:caddy]
command=/usr/sbin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Copy your IBKR config
COPY conf.yaml root/conf.yaml

EXPOSE 443

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
