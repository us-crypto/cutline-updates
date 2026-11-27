#!/usr/bin/env bash
# The build server's clock drifted hours behind, so GitHub rejected every runner login.
# This sets the clock right now, keeps it right for good, and restarts the runners.
# The 15-minute check waits while a build is running, so builds are never cut off.
set -e
timedatectl set-ntp true 2>/dev/null || true
systemctl enable --now systemd-timesyncd 2>/dev/null || true

cat > /usr/local/bin/clock-check <<'C'
#!/usr/bin/env bash
# Sets the clock from GitHub's own time when it is more than a minute off.
web=$(curl -fsSI --max-time 15 https://api.github.com | tr -d '\r' | sed -n 's/^[Dd]ate: //p')
[ -n "$web" ] || exit 0
# Never touch the clock or the runners while a build is running: it kills the build.
pgrep -f Runner.Worker >/dev/null && exit 0
diff=$(( $(date -u -d "$web" +%s) - $(date -u +%s) ))
if [ ${diff#-} -gt 60 ]; then
  date -u -s "$web" >/dev/null
  echo "clock corrected by ${diff}s"
  systemctl restart 'actions.runner*'
fi
C
chmod 755 /usr/local/bin/clock-check

cat > /etc/systemd/system/clock-check.service <<'C'
[Unit]
Description=Keep the clock right for the build runners
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/clock-check
C
cat > /etc/systemd/system/clock-check.timer <<'C'
[Unit]
Description=Check the clock every 15 minutes and at start
[Timer]
OnBootSec=1min
OnUnitActiveSec=15min
[Install]
WantedBy=timers.target
C
systemctl daemon-reload
systemctl enable --now clock-check.timer >/dev/null
/usr/local/bin/clock-check || true
echo "clock now: $(date -u)"
systemctl reset-failed 'actions.runner*' 2>/dev/null || true
systemctl restart 'actions.runner*'
sleep 25
for u in $(systemctl list-units 'actions.runner*' --no-legend --plain | awk '{print $1}'); do
  if journalctl -u "$u" --since "40 sec ago" --no-pager | grep -q "Listening for Jobs"; then echo "OK      $u"; else echo "NOT YET $u"; fi
done
