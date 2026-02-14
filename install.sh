#!/bin/bash

# =================================================================
# VERSION="1.1.2"
# ZIX ULTIMATE - FIX: UPDATE LOGIC & BT RF-KILL
# Repo: https://github.com/xKaMikax/zix_setup
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="$0"

# --- УЛУЧШЕННОЕ АВТООБНОВЛЕНИЕ ---
echo -e "${BLUE}--- Проверка версии Zix ---${NC}"
REMOTE_VERSION=$(curl -sSL "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)
LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)

echo -e "Локальная: $LOCAL_VERSION | В сети: $REMOTE_VERSION"

if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo -e "${GREEN}Найдена новая версия! Обновляюсь до $REMOTE_VERSION...${NC}"
    curl -sSL "$REPO_RAW_URL" -o "$LOCAL_FILE"
    chmod +x "$LOCAL_FILE"
    echo -e "${GREEN}Скрипт обновлен. Перезапуск...${NC}"
    exec "$LOCAL_FILE" "$@"
else
    echo -e "${GREEN}У вас актуальная версия.${NC}"
fi

# 1. ПАКЕТЫ
echo -e "${GREEN}[1/9] Установка зависимостей...${NC}"
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils curl gmediarender \
shairport-sync python3-pip python3-venv libasound2-dev \
bluetooth bluez bluez-tools ffmpeg expect rfkill

# РЕШАЕМ ПРОБЛЕМУ RF-KILL СРАЗУ
sudo rfkill unblock bluetooth
sudo systemctl start bluetooth
sudo hciconfig hci0 up 2>/dev/null

# 2. ВЫБОР УСТРОЙСТВА ВЫВОДА
echo -e "${BLUE}--- Настройка звука Zix ---${NC}"
echo "1) Обычные колонки (3.5мм / HDMI / USB)"
echo "2) Bluetooth колонка (Поиск и сопряжение)"
read -p "Выбери тип [1-2]: " OUT_TYPE

if [ "$OUT_TYPE" == "2" ]; then
    echo -e "${BLUE}Сканирую Bluetooth (15 сек)... Убедись, что колонка в поиске!${NC}"
    # Очистка старых сканов
    bluetoothctl --timeout 15 scan on > /dev/null & 
    sleep 16
    devices=$(bluetoothctl devices)
    
    if [ -z "$devices" ]; then
        echo -e "${RED}Устройства не найдены.${NC}"
        echo -e "${BLUE}Попробуй вручную: 'sudo rfkill unblock all' и запусти снова.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Список устройств:${NC}"
    mapfile -t device_list <<< "$devices"
    for i in "${!device_list[@]}"; do
        echo "$i) ${device_list[$i]}"
    done

    read -p "Выбери номер: " DEV_NUM
    SELECTED_DEVICE=${device_list[$DEV_NUM]}
    BT_MAC=$(echo $SELECTED_DEVICE | awk '{print $2}')
    BT_NAME=$(echo $SELECTED_DEVICE | cut -d' ' -f3-)

    echo -e "${BLUE}Подключаюсь к $BT_NAME...${NC}"
    bluetoothctl pair $BT_MAC
    bluetoothctl trust $BT_MAC
    bluetoothctl connect $BT_MAC
    
    OUT_DEVICE="pulse"
else
    aplay -l | grep 'card'
    read -p "Номер карты: " CARD_ID
    OUT_DEVICE="hw:$CARD_ID,0"
fi

# 3. МИКРОФОН
echo ""
arecord -l | grep 'card'
read -p "Номер карты микрофона: " IN_CARD

# 4. ПОЛЬЗОВАТЕЛЬ
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi

# 5. MPD
sudo tee /etc/mpd.conf > /dev/null <<EOF
music_directory    "/var/lib/mpd/music"
user               "zix"
bind_to_address    "0.0.0.0"
port               "6600"
audio_output {
    type    "pulse"
    name    "Zix Speaker"
}
EOF

# 6. WYOMING
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
    --auto-gain 7 \
    --noise-suppression 3 \
    --allow-discovery
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# 7. ЗАПУСК
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${GREEN}Готово! Zix (v$LOCAL_VERSION) в строю.${NC}"
