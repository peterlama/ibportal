FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

RUN apk add --no-cache wget unzip ca-certificates supervisor tailscale

# IBKR gateway
RUN wget https://download2.interactivebrokers.com/portal/clientportal.gw.zip \
    && unzip clientportal.gw.zip -d . \
    && rm clientportal.gw.zip

COPY conf.yaml root/conf.yaml

RUN mkdir -p /var/lib/tailscale /var/run/tailscale

# One-shot config: wait for tailscaled, then tailscale up + serve (Option B: HTTPS upstream)
RUN <<'EOF' cat > /usr/local/bin/tailscale-init.sh
#!/bin/sh
set -eu

# Wait for tailscaled control socket (daemon is running)
i=0
while [ ! -S /var/run/tailscale/tailscaled.sock ]; do
  i=$((i+1))
  [ "$i" -gt 120 ] && echo "tailscaled socket not ready" >&2 && exit 1
  sleep 0.25
done

HOST_ARG=""
if [ "${TS_HOSTNAME:-}" != "" ]; then
  HOST_ARG="--hostname=${TS_HOSTNAME}"
fi

# Login / bring up tailnet (retry until it works)
i=0
while :; do
  if tailscale up --authkey="${TS_AUTHKEY}" ${HOST_ARG} ${TS_EXTRA_ARGS:-}; then
    break
  fi
  i=$((i+1))
  [ "$i" -gt 60 ] && echo "tailscale up failed too many times" >&2 && exit 1
  sleep 1
done

# Publish tailnet HTTPS :443 -> local HTTPS :5000
tailscale serve reset || true
tailscale serve --https=443 https+insecure://127.0.0.1:5000
EOF
RUN chmod +x /usr/local/bin/tailscale-init.sh

# Supervisor with ordering via priority
RUN <<'EOF' cat > /etc/supervisord.conf
[supervisord]
nodaemon=true

[program:tailscaled]
command=/usr/sbin/tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state
priority=10
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:tailscale_init]
command=/usr/local/bin/tailscale-init.sh
priority=20
autostart=true
autorestart=false
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:ibkr_gateway]
directory=/app
command=sh bin/run.sh root/conf.yaml
priority=30
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Tailnet-only; no host port publish required.
EXPOSE 443

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
