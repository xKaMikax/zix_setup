#!/bin/bash

# =================================================================
VERSION="1.1.13"
# ZIX ULTIMATE - SMART AUTO-CONNECT & BYPASS
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="install.sh"

echo -e "${BLUE}--- Интеллектуальная система Zix v$VERSION ---${NC}"

# 1. ОБНОВЛЕНИЕ
REMOTE_VERSION=$(wget -qO- "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)
if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$VERSION" ]; then
    echo -e "${GREEN}Найдена новая версия $REMOTE_VERSION. Обновляюсь...${NC}"
    wget -qO "$LOCAL_FILE" "$REPO_RAW_URL" && chmod +x "$LOCAL_FILE" && exec ./"$LOCAL_FILE"
fi

# 2. ПОДГОТОВКА
sudo apt update && sudo apt install -y pulseaudio bluetooth bluez bluez-tools rfkill pulseaudio-module-bluetooth

# Старт сервисов
sudo rfkill unblock all
sudo systemctl start bluetooth
pulseaudio --start --exit-idle-time=-1 2>/dev/null

# 3. ВЫБОР ЗВУКА
while true; do
    echo -e "${BLUE}--- Настройка вывода звука ---${NC}"
    echo "1) Провод / USB / HDMI"
    echo "2) Bluetooth колонка"
    read -p "Выбор: " OUT_TYPE

    if [ "$OUT_TYPE" == "2" ]; then
        # ПРОВЕРКА: А не подключена ли колонка уже сейчас?
        echo -e "${BLUE}Проверяю текущие Bluetooth подключения...${NC}"
        CONNECTED_MAC=$(bluetoothctl devices Connected | awk '{print $2}')

        if [ ! -z "$CONNECTED_MAC" ]; then
            DEVICE_NAME=$(bluetoothctl info "$CONNECTED_MAC" | grep "Name:" | cut -d' ' -f2-)
            echo -e "${GREEN}Обнаружено активное подключение: $DEVICE_NAME [$CONNECTED_MAC]${NC}"
            echo -e "${BLUE}Пропускаю шаг поиска, использую текущее устройство.${NC}"
            BT_MAC=$CONNECTED_MAC
            OUT_DEVICE="pulse"
        else
            # Если ничего не подключено — запускаем стандартный поиск
            echo -e "${RED}Активных подключений не найдено. Начинаю поиск...${NC}"
            sudo bluetoothctl power on
            sudo bluetoothctl scan on > /dev/null &
            SCAN_PID=$!
            for i in {20..1}; do echo -ne "Сканирую... $i сек. \r"; sleep 1; done
            kill $SCAN_PID 2>/dev/null
            
            devices=$(bluetoothctl devices)
            if [ -z "$devices" ]; then
                echo -e "${RED}Устройства не найдены!${NC}"; continue
            fi

            mapfile -t device_list <<< "$devices"
            for i in "${!device_list[@]}"; do echo "$i) ${device_list[$i]}"; done
            read -p "Выбери номер: " DEV_INPUT
            BT_MAC=$(echo ${device_list[$DEV_INPUT]} | awk '{print $2}')
            
            echo -e "${BLUE}Подключаю $BT_MAC...${NC}"
            bluetoothctl trust "$BT_MAC"
            bluetoothctl pair "$BT_MAC"
            bluetoothctl connect "$BT_MAC"
            OUT_DEVICE="pulse"
        fi
    else
        aplay -l | grep 'card'
        read -p "Номер карты вывода: " CARD_ID
        OUT_DEVICE="hw:$CARD_ID,0"
    fi

    # ПРОВЕРКА ЗВУКА (С переспросом)
    while true; do
        echo -e "${BLUE}Слушай! Подаю сигнал...${NC}"
        speaker-test -t sine -f 440 -l 1 -d $OUT_DEVICE > /dev/null 2>&1 &
        sleep 3
        echo -e "${GREEN}Что я сейчас сделал? (Слышал звук?)${NC}"
        echo "y - Да, всё работает"
        echo "n - Нет, тишина (Вернуться на шаг назад)"
        echo "r - Не понял/Не расслышал (Повторить)"
        read -p "Ответ: " TEST_ANS
        
        if [ "$TEST_ANS" == "y" ]; then
            break 2
        elif [ "$TEST_ANS" == "n" ]; then
            [ "$OUT_TYPE" == "2" ] && bluetoothctl disconnect "$BT_MAC"
            break 
        elif [ "$TEST_ANS" == "r" ]; then
            continue
        fi
    done
done

# 4. МИКРОФОН
echo -e "${BLUE}--- Настройка микрофона ---${NC}"
arecord -l | grep 'card'
read -p "Введите НОМЕР карты микрофона: " IN_CARD

# 5. ПОЛЬЗОВАТЕЛЬ И ПРАВА
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists
sudo chown -R zix:audio /var/lib/mpd

# 6. MPD
sudo tee /etc/mpd.conf > /dev/null <<EOF
music_directory    "/var/lib/mpd/music"
user               "zix"
bind_to_address    "0.0.0.0"
audio_output {
    type    "pulse"
    name    "Zix Speaker"
}
EOF

# 7. WYOMING SATELLITE
echo -e "${GREEN}[7/8] Установка голосового движка...${NC}"
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

# 8. ЗАПУСК
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Zix v$VERSION Готов!${NC}"
echo -e "${BLUE}====================================================${NC}"
