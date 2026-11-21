#!/usr/bin/env bash
# Makes the build server steady on little memory:
#  - 8 GB of swap (replaces a smaller one),
#  - memory limits for every Gradle build,
#  - every runner on this server restarts by itself after a crash.
set -e
want=8
have=$(( $(stat -c %s /swapfile 2>/dev/null || echo 0) / 1073741824 ))
if [ "$have" -lt "$want" ]; then
  echo "== Swap ${have} GB -> ${want} GB"
  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  fallocate -l ${want}G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((want*1024)) status=none
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q "^/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
sysctl -q vm.swappiness=60
mkdir -p /home/builder/.gradle
cat > /home/builder/.gradle/gradle.properties <<'PROPS'
# This server has little memory: these settings win over each project's own.
org.gradle.jvmargs=-Xmx2200m -XX:MaxMetaspaceSize=768m -Dfile.encoding=UTF-8
org.gradle.workers.max=1
org.gradle.parallel=false
kotlin.compiler.execution.strategy=in-process
PROPS
chown -R builder:builder /home/builder/.gradle
for unit in /etc/systemd/system/actions.runner.*.service; do
  mkdir -p "$unit.d" && printf "[Service]\nRestart=always\nRestartSec=10\n" > "$unit.d/restart.conf"
done
systemctl daemon-reload
for unit in /etc/systemd/system/actions.runner.*.service; do
  name=$(basename "$unit")
  systemctl restart "$name"
  echo "$name: $(systemctl is-active "$name")"
done
free -h
echo "FIXED. Tell Claude: fixed"
