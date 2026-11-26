#!/usr/bin/env bash
# Installs the "reconnect-runner" command on the build server.
# Use it when GitHub has forgotten a runner ("The runner registration has been deleted").
#   reconnect-runner ./config.sh --url https://github.com/OWNER/REPO --token XXXX
set -e
cat > /usr/local/bin/reconnect-runner <<'C'
#!/usr/bin/env bash
set -e
[ "$1" = "./config.sh" ] && shift
url=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "--url" ] && url="${args[$((i+1))]}"; done
[ -n "$url" ] || { echo "Paste the whole ./config.sh line from GitHub after reconnect-runner."; exit 1; }
owner_repo=$(echo "$url" | sed -E 's#https://github.com/##; s#/$##')
key=$(echo "$owner_repo" | tr '/' '-')
unit=$(ls /etc/systemd/system | grep -E "^actions\.runner\.${key}\.[^.]+\.service$" | head -1 || true)
if [ -z "$unit" ]; then
  echo "No runner for $owner_repo yet: adding it fresh."
  exec connect-runner "$@"
fi
dir=$(systemctl show -p WorkingDirectory --value "$unit")
name=$(grep -o '"agentName": *"[^"]*"' "$dir/.runner" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/' || true)
[ -n "$name" ] || name=$(echo "$unit" | sed -E "s/^actions\.runner\.${key}\.(.*)\.service$/\1/")
systemctl stop "$unit" || true
rm -f "$dir/.runner" "$dir/.credentials" "$dir/.credentials_rsaparams"
cd "$dir"
sudo -u builder ./config.sh --unattended --replace --name "$name" --labels android "$@"
systemctl reset-failed "$unit" 2>/dev/null || true
systemctl start "$unit"
sleep 8
if journalctl -u "$unit" -n 15 --no-pager | grep -q "Listening for Jobs"; then
  echo "RECONNECTED: $owner_repo"
else
  journalctl -u "$unit" -n 15 --no-pager
fi
C
chmod 755 /usr/local/bin/reconnect-runner
echo "reconnect-runner is ready."
