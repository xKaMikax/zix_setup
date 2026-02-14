#!/bin/bash

# =================================================================
# VERSION="1.1.3"
# ZIX ULTIMATE - FIXED SELF-UPDATE
# Repo: https://github.com/xKaMikax/zix_setup
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
# Указываем фиксированное имя файла для обновлений
LOCAL_FILE="install.sh"

echo -e "${BLUE}--- Система Zix: Проверка обновлений ---${NC}"

# 1. ПОЛУЧАЕМ ВЕРСИЮ ИЗ СЕТИ
REMOTE_VERSION=$(curl -sSL "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)

# Проверяем локальную версию (если файл существует)
if [ -f "$LOCAL_FILE" ]; then
    LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)
else
    LOCAL_VERSION="0.0.0"
fi

echo -e "Локальная версия: [$LOCAL_VERSION] | В сети: [$REMOTE_VERSION]"

# СРАВНЕНИЕ
if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo -e "${GREEN}Найдена новая версия! Скачиваю обновление...${NC}"
    curl -sSL "$REPO_RAW_URL" -o "$LOCAL_FILE"
    chmod +x "$LOCAL_FILE"
    echo -e "${GREEN}Скрипт обновлен. Запускаю новую версию...${NC}"
    # Перезапускаем уже локальный файл
    exec ./"$LOCAL_FILE"
fi

# =================================================================
# ДАЛЬШЕ ИДЕТ ОСНОВНОЙ КОД (ВЫПОЛНИТСЯ ЕСЛИ ВЕРСИИ СОВПАЛИ)
# =================================================================

echo -e "${GREEN}[1/9] Установка зависимостей (Debian Trixie Fix)...${NC}"
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils curl gmediarender \
shairport-sync python3-pip python3-venv libasound2-dev \
bluetooth bluez bluez-tools ffmpeg expect rfkill

# Снимаем блокировку Bluetooth
sudo rfkill unblock bluetooth
sudo systemctl start bluetooth
sudo hciconfig hci0 up 2>/dev/null

# 2. НАСТРОЙКА ЗВУКА
echo -e "${BLUE}--- Настройка вывода звука ---${NC}"
echo "1) Аналоговый выход / USB"
echo "2) Bluetooth колонка"
read -p "Твой выбор: " OUT_TYPE

if [ "$OUT_TYPE" == "2" ]; then
    echo -e "${BLUE}Сканирую устройства (15 сек)...${NC}"
    bluetoothctl --timeout 15 scan on > /dev/null & 
    sleep 16
    devices=$(bluetoothctl devices)
    
    if [ -z "$devices" ]; then
        echo -e "${RED}Устройства не найдены!${NC}"
        exit 1
    fi

    echo -e "${GREEN}Доступные устройства:${NC}"
    mapfile -t device_list <<< "$devices"
    for i in "${!device_list[@]}"; do
        echo "$i) ${device_list[$i]}"
    done

    read -p "Выбери номер: " DEV_NUM
    SELECTED_DEVICE=${device_list[$DEV_NUM]}
    BT_MAC=$(echo $SELECTED_DEVICE | awk '{print $2}')
    
    echo -e "${BLUE}Сопряжение с $BT_MAC...${NC}"
    bluetoothctl pair $BT_MAC
    bluetoothctl trust $BT_MAC
    bluetoothctl connect $BT_MAC
    OUT_DEVICE="pulse"
else
    aplay -l | grep 'card'
    read -p "Введите номер карты вывода: " CARD_ID
    OUT_DEVICE="hw:$CARD_ID,0"
fi

# 3. МИКРОФОН
arecord -l | grep 'card'
read -p "Введите номер карты микрофона: " IN_CARD

# 4. КОНФИГУРАЦИЯ СЕРВИСОВ (ZIX)
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi

# Настройка MPD
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

# Настройка Wyoming (Голос)
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

# ЗАПУСК
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${GREEN}Установка Zix v$REMOTE_VERSION завершена!${NC}"
