#!/usr/bin/env bash
# Makes the build server steady on little memory, for every app connected to it:
#  - 8 GB of swap (replaces a smaller one),
#  - memory limits for every Gradle build,
#  - one build at a time: other apps' builds wait in line,
#  - every runner restarts by itself after a crash,
#  - connect-runner adds each new app as its own runner.
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

# The line: a job starts only when no other app is building. A lock left by a crash
# is cleared after 2 hours.
cat > /usr/local/bin/build-queue-start <<'Q'
#!/usr/bin/env bash
lock=/var/tmp/build-queue.lock
while ! mkdir "$lock" 2>/dev/null; do
  if [ -n "$(find "$lock" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rm -rf "$lock"; continue; fi
  echo "Another app is building on this server. Waiting in line..."
  sleep 20
done
echo "${GITHUB_REPOSITORY:-?} $(date)" > "$lock/owner"
echo "Our turn."
Q
cat > /usr/local/bin/build-queue-end <<'Q'
#!/usr/bin/env bash
rm -rf /var/tmp/build-queue.lock
pkill -u builder -f GradleDaemon 2>/dev/null || true
Q
chmod 755 /usr/local/bin/build-queue-start /usr/local/bin/build-queue-end

hook_env() {
  local env="$1/.env"
  touch "$env"
  grep -q ACTIONS_RUNNER_HOOK_JOB_STARTED "$env" || echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/bin/build-queue-start" >> "$env"
  grep -q ACTIONS_RUNNER_HOOK_JOB_COMPLETED "$env" || echo "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/usr/local/bin/build-queue-end" >> "$env"
  grep -q ANDROID_HOME "$env" || printf "ANDROID_HOME=/opt/android-sdk\nANDROID_SDK_ROOT=/opt/android-sdk\nLANG=C.UTF-8\n" >> "$env"
}
for dir in $(find / -xdev -name .runner -path "*/home/*" -printf "%h\n" 2>/dev/null; find /opt /root -maxdepth 4 -name .runner -printf "%h\n" 2>/dev/null); do
  hook_env "$dir"
done

# Adds one app: connect-runner ./config.sh --url https://github.com/OWNER/REPO --token XXXX
cat > /usr/local/bin/connect-runner <<'C'
#!/usr/bin/env bash
set -e
[ "$1" = "./config.sh" ] && shift
url=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "--url" ] && url="${args[$((i+1))]}"; done
repo=$(basename "$url")
dir=/home/builder/runners/$repo
if [ ! -x "$dir/config.sh" ]; then
  mkdir -p "$dir"
  version=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')
  curl -fsSL "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-x64-${version}.tar.gz" | tar xz -C "$dir"
fi
printf "ANDROID_HOME=/opt/android-sdk\nANDROID_SDK_ROOT=/opt/android-sdk\nLANG=C.UTF-8\nACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/bin/build-queue-start\nACTIONS_RUNNER_HOOK_JOB_COMPLETED=/usr/local/bin/build-queue-end\n" > "$dir/.env"
chown -R builder:builder /home/builder
cd "$dir"
sudo -u builder ./config.sh --unattended --replace --name "$(hostname)-$repo" --labels android "$@"
./svc.sh install builder
unit=$(ls -t /etc/systemd/system/actions.runner.*.service | head -1)
mkdir -p "$unit.d" && printf "[Service]\nRestart=always\nRestartSec=10\n" > "$unit.d/restart.conf"
systemctl daemon-reload
./svc.sh start
echo "CONNECTED: $repo. Tell Claude: done"
C
chmod 755 /usr/local/bin/connect-runner
chown -R builder:builder /home/builder

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
