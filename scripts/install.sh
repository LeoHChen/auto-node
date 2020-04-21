#!/usr/bin/env bash
set -e

echo "[AutoNode] Starting installation for user $USER (with home: $HOME)"

sleep 5

# Do prechecks for absolute requirements..
if [ "$(uname)" != "Linux" ]; then
  echo "[AutoNode] not on a Linux machine, exiting."
  exit
fi
if (( "$EUID" == 0 )); then
  echo "Do not install as root"
  exit
fi
if ! command -v systemctl > /dev/null; then
  echo "[AutoNode] distro does not have systemd, exiting."
  exit
fi

function check_and_install(){
  pkg=$1
  if ! command -v "$pkg" > /dev/null; then
    if [ -z "$PKG_INSTALL" ]; then
      echo "[AutoNode] Unknown package manager, please install $pkg and run install again."
      exit 2
    else
      echo "[AutoNode] Installing $pkg"
      $PKG_INSTALL "$pkg"
    fi
  fi
}

function yes_or_exit(){
  read -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    exit 1
  fi
}

echo "[AutoNode] Installing for user $USER"
echo "[AutoNode] Checking dependencies..."
unset PKG_INSTALL
if command -v yum > /dev/null; then
  sudo yum update
  PKG_INSTALL='sudo yum install -y'
fi
if command -v apt-get > /dev/null; then
  sudo apt update
  PKG_INSTALL='sudo apt-get install -y'
fi
for dependency in "python3" "python3-pip" "jq" "unzip" "nano" "curl"; do
  check_and_install "$dependency"
done
echo "[AutoNode] Removing existing AutoNode installation"
pip3 uninstall AutoNode -y || sudo pip3 uninstall AutoNode -y || echo "[AutoNode] Was not installed..."
echo "[AutoNode] Installing main python3 library (as sudo)"
sudo pip3 install AutoNode --upgrade
echo "[AutoNode] Initilizing python3 library"
python3 -c "from AutoNode import common; common.save_validator_config()" > /dev/null

daemon_name=$(python3 -c "from AutoNode.daemon import Daemon; print(Daemon.name)")
if systemctl --type=service --state=active | grep -e ^"$daemon_name"; then
  echo "[AutoNode] Detected running AutoNode. Must stop existing AutoNode to continue. Proceed (y/n)?"
  yes_or_exit
fi
if pgrep harmony; then
  echo "[AutoNode] Harmony process is running, kill it for upgrade (y/n)?"
  yes_or_exit
  killall harmony
fi
if [ -f "$HOME"/auto_node.sh ]; then
  echo "[AutoNode] Would you like to replace existing $HOME/auto_node.sh (y/n)?"
  yes_or_exit
  rm "$HOME"/auto_node.sh
fi

systemd_service="[Unit]
Description=Harmony AutoNode %I service

[Service]
Type=simple
ExecStart=$(command -v python3) -u $HOME/bin/autonode_service.py %I
User=$USER

[Install]
WantedBy=multi-user.target
"

echo "[AutoNode] Installing Harmony CLI"
curl -s -LO https://harmony.one/hmycli && mv hmycli "$HOME"/hmy && chmod +x "$HOME"/hmy
harmony_dir=$(python3 -c "from AutoNode import common; print(common.harmony_dir)")
mkdir -p "$harmony_dir"
echo "[AutoNode] Installing AutoNode wrapper script"
curl -s -o "$HOME"/auto_node.sh  https://raw.githubusercontent.com/harmony-one/auto-node/migrate_off_docker/scripts/auto_node.sh  # TODO: change back url
chmod +x "$HOME"/auto_node.sh
curl -s -o "$harmony_dir"/init.py https://raw.githubusercontent.com/harmony-one/auto-node/migrate_off_docker/init.py  # TODO: change back url
daemon_name=$(python3 -c "from AutoNode.daemon import Daemon; print(Daemon.name)")
echo "[AutoNode] Installing AutoNode daemon: $daemon_name"
mkdir -p "$HOME"/bin
curl -s -o "$HOME"/bin/autonode_service.py https://raw.githubusercontent.com/harmony-one/auto-node/migrate_off_docker/autonode_service.py # TODO: change back url
sudo echo "$systemd_service" | sudo tee /etc/systemd/system/"$daemon_name"@.service > /dev/null
sudo chmod 644 /etc/systemd/system/"$daemon_name"@.service
sudo systemctl daemon-reload

if ! command -v rclone > /dev/null; then
  echo "[AutoNode] Installing rclone dependency for fast db syncing"
  curl https://rclone.org/install.sh | sudo bash
  mkdir -p ~/.config/rclone
fi
if ! grep -q 'hmy' ~/.config/rclone/rclone.conf 2> /dev/null; then
  echo "[AutoNode] Adding [hmy] profile to rclone.conf"
  cat<<-EOT>>~/.config/rclone/rclone.conf
[hmy]
type = s3
provider = AWS
env_auth = false
region = us-west-1
acl = public-read
EOT
fi

echo "[AutoNode] Installation complete!"
echo "[AutoNode] Help message for auto_node.sh:"
"$HOME"/auto_node.sh -h
echo ""
echo "[AutoNode] Note that you have to import your wallet using the Harmony CLI before"
echo "           you can use validator features of AutoNode."
run_cmd="$HOME/auto_node.sh run --auto-active --clean"
echo -e "[AutoNode] Start your AutoNode with: \e[38;5;0;48;5;255m$run_cmd\e[0m"
echo ""
