#!/bin/bash

# =================================================================
# VERSION="0.0.1"  <-- МЕНЯЙ ЭТОТ ID ДЛЯ ОБНОВЛЕНИЯ
# ZIX ULTIMATE SMART SPEAKER - VERSIONED AUTO-UPDATE
# Repo: https://github.com/xKaMikax/zix_setup
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="$0"

echo -e "${BLUE}--- Система Zix (Проверка версии) ---${NC}"

# 1. ПОЛУЧЕНИЕ ВЕРСИИ ИЗ СЕТИ
REMOTE_VERSION=$(curl -s "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)
LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)

if [ -z "$REMOTE_VERSION" ]; then
    echo -e "${RED}Не удалось проверить версию в сети. Работаем на локальной.${NC}"
elif [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo -e "${GREEN}Доступно обновление: $LOCAL_VERSION -> $REMOTE_VERSION${NC}"
    echo -e "${BLUE}Скачивание новой версии...${NC}"
    curl -sSL "$REPO_RAW_URL" -o "$LOCAL_FILE"
    chmod +x "$LOCAL_FILE"
    echo -e "${GREEN}Обновление завершено! Перезапуск...${NC}"
    exec "$LOCAL_FILE" "$@"
else
    echo -e "${GREEN}У вас актуальная версия: $LOCAL_VERSION${NC}"
fi

# =================================================================
# ДАЛЬШЕ ИДЕТ ОСНОВНОЙ КОД УСТАНОВКИ
# =================================================================

echo -e "${BLUE}[1/9] Проверка системных зависимостей...${NC}"
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils curl gmediarender \
shairport-sync bluealsa python3-pip python3-venv libasound2-dev \
bluetooth bluez-tools ffmpeg git

# 2. Настройка аудио
echo -e "${BLUE}--- Настройка звука ---${NC}"
aplay -l | grep 'card'
read -p "Номер карты для ВЫВОДА (Колонки): " OUT_CARD
echo ""
arecord -l | grep 'card'
read -p "Номер карты для ВВОДА (Микрофон): " IN_CARD

# 3. Пользователь zix
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists
sudo chown -R zix:audio /var/lib/mpd /var/log/mpd

# 4. Настройка MPD
sudo tee /etc/mpd.conf > /dev/null <<EOF
music_directory    "/var/lib/mpd/music"
playlist_directory "/var/lib/mpd/playlists"
db_file            "/var/lib/mpd/tag_cache"
user               "zix"
bind_to_address    "0.0.0.0"
port               "6600"
auto_update        "yes"
volume_normalization "yes"
audio_output {
    type    "alsa"
    name    "Zix Speaker"
    device  "hw:$OUT_CARD,0"
    mixer_type "software"
}
EOF

# 5. Spotify (Raspotify)
if ! command -v raspotify &> /dev/null; then
    curl -sL https://dtcooper.github.io/raspotify/install.sh | sh
fi
sudo sed -i "s/.*LIBRESPOT_NAME=.*/LIBRESPOT_NAME=\"Zix Speaker\"/" /etc/raspotify/conf
sudo sed -i "s/.*LIBRESPOT_DEVICE=.*/LIBRESPOT_DEVICE=\"hw:$OUT_CARD,0\"/" /etc/raspotify/conf

# 6. AirPlay & DLNA
sudo sed -i "s/name = .*/name = \"Zix Speaker\"/" /etc/shairport-sync.conf
sudo sed -i "s/ENABLED=0/ENABLED=1/" /etc/default/gmediarender
sudo sed -i "s/UPNP_DEVICE_NAME=.*/UPNP_DEVICE_NAME=\"Zix Speaker\"/" /etc/default/gmediarender

# 7. Bluetooth
sudo tee /etc/bluetooth/main.conf > /dev/null <<EOF
[General]
Name = Zix Speaker
Class = 0x20041C
DiscoverableTimeout = 0
EOF

# 8. Wyoming Satellite (Zix Barge-in)
sudo mkdir -p /opt/wyoming-satellite
sudo chown zix:zix /opt/wyoming-satellite
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

sudo tee /etc/systemd/system/wyoming-satellite.service > /dev/null <<EOF
[Unit]
Description=Wyoming Satellite Zix
After=network-online.target pulseaudio.service
[Service]
Type=simple
User=zix
ExecStart=/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \
    --name 'Zix' \
    --uri 'tcp://0.0.0.0:10400' \
    --mic-command 'arecord -D hw:$IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \
    --snd-command 'aplay -D hw:$OUT_CARD,0 -r 22050 -c 1 -f S16_LE -t raw' \
    --ducking-volume 0.2 \
    --auto-gain 7 \
    --noise-suppression 3 \
    --allow-discovery
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

# 9. Финализация
sudo systemctl daemon-reload
sudo systemctl enable mpd raspotify gmediarender shairport-sync wyoming-satellite bluetooth
sudo systemctl restart mpd raspotify gmediarender shairport-sync wyoming-satellite bluetooth

echo -e "${GREEN}Система Zix (v$LOCAL_VERSION) готова к работе!${NC}"
