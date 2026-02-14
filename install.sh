#!/bin/bash

# =================================================================
# VERSION="1.1.0"
# ZIX ULTIMATE - SMART SPEAKER & BT SCANNER
# Repo: https://github.com/xKaMikax/zix_setup
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="$0"

# --- АВТООБНОВЛЕНИЕ ---
REMOTE_VERSION=$(curl -s "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)
LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)

if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo -e "${GREEN}Обновление Zix: $LOCAL_VERSION -> $REMOTE_VERSION...${NC}"
    curl -sSL "$REPO_RAW_URL" -o "$LOCAL_FILE"
    chmod +x "$LOCAL_FILE"
    exec "$LOCAL_FILE" "$@"
fi

# 1. ПАКЕТЫ
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils curl gmediarender \
shairport-sync bluealsa python3-pip python3-venv libasound2-dev \
bluetooth bluez bluez-tools ffmpeg expect

# 2. ВЫБОР УСТРОЙСТВА ВЫВОДА
echo -e "${BLUE}--- Настройка звука Zix ---${NC}"
echo "1) Обычные колонки (3.5мм / HDMI / USB)"
echo "2) Bluetooth колонка (Поиск и сопряжение)"
read -p "Выбери тип вывода [1-2]: " OUT_TYPE

if [ "$OUT_TYPE" == "2" ]; then
    echo -e "${BLUE}Включаю Bluetooth и поиск устройств... (Жди 10 сек)${NC}"
    sudo systemctl start bluetooth
    sudo hciconfig hci0 up
    
    # Сканирование
    devices=$(bluetoothctl --timeout 10 scan on > /dev/null & sleep 10; bluetoothctl devices)
    
    if [ -z "$devices" ]; then
        echo -e "${RED}Устройства не найдены. Проверь, что колонка в режиме сопряжения!${NC}"
        exit 1
    fi

    echo -e "${GREEN}Найденные устройства:${NC}"
    mapfile -t device_list <<< "$devices"
    for i in "${!device_list[@]}"; do
        echo "$i) ${device_list[$i]}"
    done

    read -p "Выбери номер устройства: " DEV_NUM
    SELECTED_DEVICE=${device_list[$DEV_NUM]}
    BT_MAC=$(echo $SELECTED_DEVICE | awk '{print $2}')
    BT_NAME=$(echo $SELECTED_DEVICE | cut -d' ' -f3-)

    echo -e "${BLUE}Сопряжение с $BT_NAME ($BT_MAC)...${NC}"
    
    # Автоматическое сопряжение через bluetoothctl
    printf "pair $BT_MAC\ntrust $BT_MAC\nconnect $BT_MAC\nquit" | bluetoothctl
    
    OUT_DEVICE="bluealsa:SRV=org.bluealsa,DEV=$BT_MAC,PROFILE=a2dp"
    echo -e "${GREEN}Успешно подключено к $BT_NAME!${NC}"
else
    aplay -l | grep 'card'
    read -p "Введи номер карты (например, 0): " CARD_ID
    OUT_DEVICE="hw:$CARD_ID,0"
fi

# МИКРОФОН
echo ""
arecord -l | grep 'card'
read -p "Введи номер карты МИКРОФОНА: " IN_CARD

# 3. ПОЛЬЗОВАТЕЛЬ И ПРАВА
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi

# 4. MPD CONFIG
sudo tee /etc/mpd.conf > /dev/null <<EOF
music_directory    "/var/lib/mpd/music"
user               "zix"
bind_to_address    "0.0.0.0"
port               "6600"
audio_output {
    type    "alsa"
    name    "Zix Speaker"
    device  "$OUT_DEVICE"
    mixer_type "software"
}
EOF

# 5. WYOMING (ГОЛОС) С ПРИГЛУШЕНИЕМ
sudo mkdir -p /opt/wyoming-satellite
sudo chown zix:zix /opt/wyoming-satellite
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

sudo tee /etc/systemd/system/wyoming-satellite.service > /dev/null <<EOF
[Unit]
Description=Wyoming Satellite Zix
After=network-online.target bluetooth.service
[Service]
Type=simple
User=zix
ExecStart=/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \
    --name 'Zix' \
    --uri 'tcp://0.0.0.0:10400' \
    --mic-command 'arecord -D hw:$IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \
    --snd-command 'aplay -D $OUT_DEVICE -r 22050 -c 1 -f S16_LE -t raw' \
    --ducking-volume 0.2 \
    --auto-gain 7 \
    --noise-suppression 3 \
    --allow-discovery
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# 6. ЗАПУСК
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${GREEN}Установка завершена! Версия: $LOCAL_VERSION${NC}"
echo -e "Zix работает через: $OUT_DEVICE"
