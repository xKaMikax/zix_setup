#!/bin/bash

# =================================================================
# VERSION="1.2.6"
# PROJECT: ZIX ULTIMATE - THE STABLE EDITION
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}          ЗАПУСК УСТАНОВКИ ZIX v1.2.6               ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. СИСТЕМНАЯ ПОДГОТОВКА
echo -e "${GREEN}[1/8] Установка системных компонентов...${NC}"
sudo apt update
sudo apt install -y \
    mpd mpc pulseaudio alsa-utils python3-venv curl \
    bluetooth bluez bluez-tools pulseaudio-module-bluetooth \
    shairport-sync avahi-daemon ffmpeg python3-pip \
    rfkill git build-essential libasound2-dev

# Попытка поставить librespot (Spotify) альтернативным методом
if ! command -v librespot &> /dev/null; then
    echo -e "${YELLOW}Librespot не найден, пробую Raspotify...${NC}"
    curl -sL https://dtcooper.github.io/raspotify/install.sh | sh
fi

# 2. АКТИВАЦИЯ ЗВУКА
echo -e "${GREEN}[2/8] Активация аудио-движка...${NC}"
sudo rfkill unblock bluetooth
sudo systemctl start bluetooth
sudo bluetoothctl power on
pulseaudio -k 2>/dev/null
pulseaudio --start --exit-idle-time=-1

# 3. МИКРОФОН
echo -e "${YELLOW}--- ВВОД ДАННЫХ ---${NC}"
arecord -l | grep 'card'
read -p "Введи НОМЕР карты твоего микрофона: " FINAL_IN_CARD

# 4. ПОЛЬЗОВАТЕЛЬ И ПРАВА
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists /opt/wyoming-satellite
sudo chown -R zix:audio /var/lib/mpd
sudo chown -R zix:zix /opt/wyoming-satellite

# 5. УСТАНОВКА WYOMING (WebRTC уже собран, будет быстро)
echo -e "${GREEN}[4/8] Проверка Python VENV и Wyoming...${NC}"
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install "wyoming-satellite[webrtc]"

# 6. СОЗДАНИЕ RUNNER.SH (С АВТООБНОВЛЕНИЕМ)
echo -e "${GREEN}[5/8] Создание скрипта запуска...${NC}"
sudo bash -c "cat <<EOF > /opt/wyoming-satellite/run_zix.sh
#!/bin/bash
cd /opt/wyoming-satellite
curl -s -O https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh
/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \\
    --name 'Zix' \\
    --uri 'tcp://0.0.0.0:10400' \\
    --mic-command 'arecord -D hw:$FINAL_IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D pulse -r 22050 -c 1 -f S16_LE -t raw' \\
    --mic-auto-gain 7 \\
    --mic-noise-suppression 3
EOF"
sudo chmod +x /opt/wyoming-satellite/run_zix.sh
sudo chown zix:zix /opt/wyoming-satellite/run_zix.sh

# 7. КОНФИГУРАЦИЯ MPD
sudo bash -c "cat <<EOF > /etc/mpd.conf
music_directory    \"/var/lib/mpd/music\"
playlist_directory \"/var/lib/mpd/playlists\"
user               \"zix\"
bind_to_address    \"0.0.0.0\"
audio_output {
    type    \"pulse\"
    name    \"Zix Output\"
}
EOF"

# 8. СЕРВИС SYSTEMD
sudo bash -c "cat <<EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Zix Ultimate Voice & Media
After=network-online.target bluetooth.service pulseaudio.service
[Service]
Type=simple
User=zix
ExecStart=/opt/wyoming-satellite/run_zix.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF"

# 9. ЗАПУСК И ГРОМКОСТЬ
echo -e "${GREEN}[8/8] Финальная настройка...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite shairport-sync

# Ищем колонку и включаем её
BT_SINK=$(pactl list sinks short | grep "bluez_sink" | awk '{print $2}')
if [ ! -z "$BT_SINK" ]; then
    pactl set-default-sink $BT_SINK
    pactl set-sink-volume $BT_SINK 100%
fi

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}      УСТАНОВКА ZIX v1.2.6 ЗАВЕРШЕНА!               ${NC}"
echo -e "${BLUE}====================================================${NC}"
