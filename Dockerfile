FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

RUN apk add --no-cache wget unzip ca-certificates supervisor tailscale

# IBKR gateway
RUN wget https://download2.interactivebrokers.com/portal/clientportal.gw.zip \
    && unzip clientportal.gw.zip -d . \
    && rm clientportal.gw.zip

COPY conf.yaml root/conf.yaml

RUN mkdir -p /var/lib/tailscale /var/run/tailscale

# tailscale init (Option B: HTTPS upstream)
RUN <<'EOF' cat > /usr/local/bin/tailscale-init.sh
#!/bin/sh
set -eu

# Wait for tailscaled
until [ -S /var/run/tailscale/tailscaled.sock ]; do sleep 0.2; done

HOST_ARG=""
if [ "${TS_HOSTNAME:-}" != "" ]; then
  HOST_ARG="--hostname=${TS_HOSTNAME}"
fi

# IMPORTANT: no --tun here (userspace is on tailscaled)
tailscale --socket=/var/run/tailscale/tailscaled.sock up \
  --authkey="${TS_AUTHKEY}" \
  --state=/var/lib/tailscale/tailscaled.state \
  ${HOST_ARG} \
  ${TS_EXTRA_ARGS:-}

tailscale --socket=/var/run/tailscale/tailscaled.sock serve reset || true

# Tailnet :443 -> local HTTPS :5000
tailscale --socket=/var/run/tailscale/tailscaled.sock serve https:443 https://127.0.0.1:5000

exit 0
EOF
RUN chmod +x /usr/local/bin/tailscale-init.sh

# Supervisor
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

[program:tailscaled]
command=/usr/sbin/tailscaled --tun=userspace-networking --socket=/var/run/tailscale/tailscaled.sock --state=/var/lib/tailscale/tailscaled.state
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:tailscale_init]
command=/usr/local/bin/tailscale-init.sh
autostart=true
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

EXPOSE 443
CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
