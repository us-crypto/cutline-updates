#!/usr/bin/env bash
# Restarts the build runner, makes it come back by itself after a crash, and shows memory.
set -e
unit=$(ls /etc/systemd/system/actions.runner.*.service | head -1)
mkdir -p "$unit.d" && printf "[Service]\nRestart=always\nRestartSec=10\n" > "$unit.d/restart.conf"
swapon --show | grep -q /swapfile || swapon /swapfile || true
mkdir -p /home/builder/.gradle
cat > /home/builder/.gradle/gradle.properties <<'PROPS'
# This server has little memory: these settings win over each project's own.
org.gradle.jvmargs=-Xmx2560m -XX:MaxMetaspaceSize=768m -Dfile.encoding=UTF-8
org.gradle.workers.max=2
org.gradle.parallel=false
kotlin.daemon.jvmargs=-Xmx1536m
PROPS
chown -R builder:builder /home/builder/.gradle
systemctl daemon-reload
systemctl restart "$(basename "$unit")"
sleep 3
systemctl is-active "$(basename "$unit")"
echo "Memory (GB):"; free -g | head -2
echo "Out-of-memory kills:"; dmesg 2>/dev/null | grep -ci "killed process" || true
echo "FIXED. Tell Claude: fixed"
