#!/usr/bin/env bash
# Shows where each build runner lives, what it is connected as, and what it says on start.
for u in /etc/systemd/system/actions.runner.*.service; do
  echo "=== $(basename "$u")"
  grep -E "^(ExecStart|WorkingDirectory|User)=" "$u"
  d=$(dirname "$(grep '^ExecStart=' "$u" | cut -d= -f2-)")
  echo "dir: $d   version: $("$d/bin/Runner.Listener" --version 2>/dev/null)"
  ls -la "$d" | grep -E " \.runner| \.cred| \.env" | awk '{print $1, $3, $NF}'
  grep -oE '"(agentId|agentName|gitHubUrl|serverUrlV2|useV2Flow)": *[^,}]*' "$d/.runner" 2>/dev/null | tr '\n' ' '; echo
done
echo "=== clock: $(date -u)"
systemctl restart 'actions.runner*'
sleep 20
journalctl -u 'actions.runner*' --since "40 sec ago" --no-pager | grep -E "Listening|Failed|deleted|error|Error" | tail -12
