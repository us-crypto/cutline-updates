#!/usr/bin/env bash
# Sets up an Ubuntu 24.04 server as the build machine for all apps (a GitHub self-hosted runner).
# Run as root. Afterwards, register it with GitHub using the line from the repository's
# Settings > Actions > Runners > New self-hosted runner page (see the steps you were given).
set -euo pipefail

echo "== Checking that Google's Android tools can be downloaded here"
code=$(curl -s -o /dev/null -w "%{http_code}" https://dl.google.com/android/repository/repository2-3.xml || true)
if [ "$code" != "200" ]; then
  echo "STOP: Google answered $code instead of 200. Android apps can't be built on this server."
  exit 1
fi

echo "== Extra memory (swap), so big builds don't run out"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 8G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q /swapfile /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

echo "== Tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl unzip zip jq ffmpeg espeak-ng build-essential openjdk-17-jdk-headless ca-certificates >/dev/null
if ! command -v gh >/dev/null; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq && apt-get install -y -qq gh >/dev/null
fi

echo "== Builder account (builds never run as root)"
id builder >/dev/null 2>&1 || useradd -m -s /bin/bash builder

echo "== Android SDK"
SDK=/opt/android-sdk
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  mkdir -p "$SDK/cmdline-tools"
  curl -fsSL -o /tmp/cmdline.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  unzip -q -o /tmp/cmdline.zip -d /tmp/cmdline && rm -rf "$SDK/cmdline-tools/latest" && mv /tmp/cmdline/cmdline-tools "$SDK/cmdline-tools/latest"
  rm -rf /tmp/cmdline /tmp/cmdline.zip
fi
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null || true
"$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" \
  "platform-tools" "platforms;android-36" "build-tools;36.0.0" "build-tools;35.0.0" \
  "ndk;27.3.13750724" "cmake;3.22.1" >/dev/null
chown -R builder:builder "$SDK"
cat > /etc/profile.d/android.sh <<EOF
export ANDROID_HOME=$SDK
export ANDROID_SDK_ROOT=$SDK
export PATH=\$PATH:$SDK/platform-tools:$SDK/cmdline-tools/latest/bin
EOF

echo "== GitHub runner program"
RUNNER_DIR=/home/builder/runner
if [ ! -x "$RUNNER_DIR/config.sh" ]; then
  version=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')
  mkdir -p "$RUNNER_DIR"
  curl -fsSL -o /tmp/runner.tgz "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-x64-${version}.tar.gz"
  tar xzf /tmp/runner.tgz -C "$RUNNER_DIR" && rm /tmp/runner.tgz
  "$RUNNER_DIR/bin/installdependencies.sh" >/dev/null
fi
printf "ANDROID_HOME=%s\nANDROID_SDK_ROOT=%s\nLANG=C.UTF-8\n" "$SDK" "$SDK" > "$RUNNER_DIR/.env"
chown -R builder:builder /home/builder

# Lets the runner start itself as a service once registered.
cat > /usr/local/bin/connect-runner <<'EOF'
#!/usr/bin/env bash
# Usage: connect-runner <the ./config.sh ... line from GitHub, pasted after it>
set -e
[ "$1" = "./config.sh" ] && shift
cd /home/builder/runner
sudo -u builder ./config.sh --unattended --labels android "$@"
./svc.sh install builder
# Start again by itself after a crash or a restart of the server.
unit=$(ls /etc/systemd/system/actions.runner.*.service | head -1)
mkdir -p "$unit.d" && printf "[Service]\nRestart=always\nRestartSec=10\n" > "$unit.d/restart.conf"
systemctl daemon-reload
./svc.sh start
echo "CONNECTED. Tell Claude: done"
EOF
chmod +x /usr/local/bin/connect-runner

echo
echo "READY. Memory: $(free -g | awk '/Mem/{print $2}') GB, cores: $(nproc), free disk: $(df -h / | awk 'NR==2{print $4}')"
echo "Next: type  connect-runner  then a space, then paste the ./config.sh line from GitHub, and press Enter."
