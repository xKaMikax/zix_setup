#!/bin/bash

# =================================================================
# VERSION="1.1.4"
# ZIX ULTIMATE - FIX: DEBIAN TRIXIE & WGET
# Repo: https://github.com/xKaMikax/zix_setup
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="install.sh"

echo -e "${BLUE}--- Система Zix: Обновление через wget ---${NC}"

# Снимаем RF-kill СРАЗУ (до любых проверок)
sudo apt update && sudo apt install -y rfkill
sudo rfkill unblock all

# 1. АВТООБНОВЛЕНИЕ
REMOTE_VERSION=$(wget -qO- "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)

if [ -f "$LOCAL_FILE" ]; then
    LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)
else
    LOCAL_VERSION="0.0.0"
fi

if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo -e "${GREEN}Найдена версия $REMOTE_VERSION. Обновляюсь...${NC}"
    wget -qO "$LOCAL_FILE" "$REPO_RAW_URL"
    chmod +x "$LOCAL_FILE"
    exec ./"$LOCAL_FILE"
fi

# 2. УСТАНОВКА ПАКЕТОВ (БЕЗ bluealsa!)
echo -e "${GREEN}[1/8] Установка системного софта...${NC}"
# Устанавливаем по одному, чтобы не падать из-за отсутствующих пакетов
for pkg in mpd mpc pulseaudio alsa-utils gmediarender shairport-sync python3-pip python3-venv libasound2-dev bluetooth bluez bluez-tools ffmpeg expect; do
    sudo apt install -y $pkg || echo "Пропускаем $pkg..."
done

# 3. НАСТРОЙКА BLUETOOTH
sudo systemctl start bluetooth
sudo hciconfig hci0 up 2>/dev/null

echo -e "${BLUE}--- Настройка звука Zix ---${NC}"
echo "1) Провод / USB"
echo "2) Bluetooth колонка"
read -p "Выбор: " OUT_TYPE

if [ "$OUT_TYPE" == "2" ]; then
    echo -e "${BLUE}Поиск Bluetooth (15 сек)...${NC}"
    # Очистка и старт сканирования
    bluetoothctl scan on > /dev/null &
    SCAN_PID=$!
    sleep 15
    kill $SCAN_PID 2>/dev/null
    
    devices=$(bluetoothctl devices)
    if [ -z "$devices" ]; then
        echo -e "${RED}Устройства не найдены! Попробуй еще раз или проверь rfkill list.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Доступные устройства:${NC}"
    mapfile -t device_list <<< "$devices"
    for i in "${!device_list[@]}"; do
        echo "$i) ${device_list[$i]}"
    done

    read -p "Номер устройства: " DEV_NUM
    BT_MAC=$(echo ${device_list[$DEV_NUM]} | awk '{print $2}')
    
    echo -e "${BLUE}Подключение к $BT_MAC...${NC}"
    bluetoothctl pair $BT_MAC
    bluetoothctl trust $BT_MAC
    bluetoothctl connect $BT_MAC
    OUT_DEVICE="pulse"
else
    aplay -l | grep 'card'
    read -p "Номер карты вывода (0, 1...): " CARD_ID
    OUT_DEVICE="hw:$CARD_ID,0"
fi

# 4. МИКРОФОН
arecord -l | grep 'card'
read -p "Номер карты микрофона: " IN_CARD

# 5. ПОЛЬЗОВАТЕЛЬ И КОНФИГИ
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi

# Настройка MPD под Pulse
sudo tee /etc/mpd.conf > /dev/null <<EOF
music_directory    "/var/lib/mpd/music"
user               "zix"
bind_to_address    "0.0.0.0"
audio_output {
    type    "pulse"
    name    "Zix Speaker"
}
EOF

# 6. WYOMING SATELLITE (ZIX)
sudo mkdir -p /opt/wyoming-satellite
sudo chown zix:zix /opt/wyoming-satellite
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

sudo tee /etc/systemd/system/wyoming-satellite.service > /dev/null <<EOF
[Unit]
Description=Wyoming Satellite Zix
After=network-online.target bluetooth.service pulseaudio.service
[Service]
Type=simple
User=zix
ExecStart=/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \
    --name 'Zix' \
    --uri 'tcp://0.0.0.0:10400' \
    --mic-command 'arecord -D hw:$IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \
    --snd-command 'aplay -D $OUT_DEVICE -r 22050 -c 1 -f S16_LE -t raw' \
    --ducking-volume 0.2 \
    --allow-discovery
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# 7. ФИНАЛ
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${GREEN}Zix v$VERSION установлен!${NC}"
