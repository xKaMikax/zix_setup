#!/bin/bash

# =================================================================
# VERSION="1.1.6"
# ZIX ULTIMATE - BT SCAN WITH SKIP OPTION
# Repo: https://github.com/xKaMikax/zix_setup
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="install.sh"

# --- ОБНОВЛЕНИЕ ---
REMOTE_VERSION=$(wget -qO- "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)
LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)

if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    wget -qO "$LOCAL_FILE" "$REPO_RAW_URL" && chmod +x "$LOCAL_FILE" && exec ./"$LOCAL_FILE"
fi

# [Подготовка]
sudo rfkill unblock all
sudo systemctl start bluetooth
sudo bluetoothctl power on
sudo bluetoothctl agent on
sudo bluetoothctl default-agent

echo -e "${BLUE}--- Настройка звука Zix ---${NC}"
echo "1) Провод / USB / HDMI"
echo "2) Bluetooth колонка"
read -p "Выбор: " OUT_TYPE

if [ "$OUT_TYPE" == "2" ]; then
    while true; do
        echo -e "${BLUE}Поиск устройств (20 сек)... Переведи колонку в режим сопряжения!${NC}"
        sudo bluetoothctl scan on > /dev/null &
        SCAN_PID=$!
        sleep 20
        kill $SCAN_PID 2>/dev/null
        
        devices=$(sudo bluetoothctl devices)
        
        if [ -z "$devices" ]; then
            echo -e "${RED}Устройства не найдены.${NC}"
            echo "1) Попробовать еще раз"
            echo "2) Пропустить и использовать проводной выход (Default)"
            read -p "Что делаем? [1-2]: " BT_CHOICE
            
            if [ "$BT_CHOICE" == "2" ]; then
                OUT_DEVICE="pulse" # Переключаем на Pulse по умолчанию
                echo -e "${BLUE}Пропускаем... Звук будет настроен на системный выход.${NC}"
                break
            fi
            # Если выбрали 1, цикл начнется сначала
        else
            echo -e "${GREEN}Найденные устройства:${NC}"
            mapfile -t device_list <<< "$devices"
            for i in "${!device_list[@]}"; do
                echo "$i) ${device_list[$i]}"
            done

            read -p "Выбери номер устройства (или 's' чтобы пропустить): " DEV_INPUT
            if [ "$DEV_INPUT" == "s" ]; then
                OUT_DEVICE="pulse"
                break
            fi
            
            BT_MAC=$(echo ${device_list[$DEV_INPUT]} | awk '{print $2}')
            echo -e "${BLUE}Сопряжение с $BT_MAC...${NC}"
            sudo bluetoothctl pair $BT_MAC
            sudo bluetoothctl trust $BT_MAC
            sudo bluetoothctl connect $BT_MAC
            OUT_DEVICE="pulse"
            break
        fi
    done
else
    aplay -l | grep 'card'
    read -p "Введите номер карты вывода: " CARD_ID
    OUT_DEVICE="hw:$CARD_ID,0"
fi

# --- ДАЛЬШЕ СТАНДАРТНАЯ УСТАНОВКА ---
echo -e "${GREEN}[5/8] Настройка пользователя и сервисов...${NC}"
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi

# Настройка MPD
sudo tee /etc/mpd.conf > /dev/null <<EOF
music_directory    "/var/lib/mpd/music"
user               "zix"
bind_to_address    "0.0.0.0"
audio_output {
    type    "pulse"
    name    "Zix Speaker"
}
EOF

# Настройка Wyoming (Голос)
sudo mkdir -p /opt/wyoming-satellite
sudo chown zix:zix /opt/wyoming-satellite
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

# Определение микрофона (если не задан)
arecord -l | grep 'card'
read -p "Номер карты микрофона: " IN_CARD

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

sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${GREEN}Установка Zix завершена!${NC}"
