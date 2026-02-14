#!/bin/bash

# =================================================================
VERSION="1.1.11"
# ZIX ULTIMATE - FULL FIX: NO BUSY BT & FULL CONFIG
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="install.sh"

echo -e "${BLUE}--- Интеллектуальная система Zix v$VERSION ---${NC}"

# 1. БЛОК АВТООБНОВЛЕНИЯ
REMOTE_VERSION=$(wget -qO- "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)
if [ -f "$LOCAL_FILE" ]; then
    LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)
else
    LOCAL_VERSION="0.0.0"
fi

if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo -e "${GREEN}Обнаружена новая версия $REMOTE_VERSION. Обновляюсь...${NC}"
    wget -qO "$LOCAL_FILE" "$REPO_RAW_URL"
    chmod +x "$LOCAL_FILE"
    exec ./"$LOCAL_FILE"
fi

# 2. ЖЕСТКАЯ ПОДГОТОВКА BLUETOOTH (Лечим Busy Error)
echo -e "${GREEN}[1/8] Очистка и сброс Bluetooth адаптера...${NC}"
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils curl gmediarender \
shairport-sync python3-pip python3-venv libasound2-dev \
bluetooth bluez bluez-tools ffmpeg expect rfkill pulseaudio-module-bluetooth

# Убиваем процессы, которые могут блокировать hci0
sudo systemctl stop bluetooth
sudo rfkill unblock bluetooth
sudo hciconfig hci0 down 2>/dev/null
sudo hciconfig hci0 up 2>/dev/null
# Очистка кэша старых (глючных) соединений
sudo rm -rf /var/lib/bluetooth/*
sudo systemctl start bluetooth
sleep 2

# Пробуждаем контроллер
sudo bluetoothctl power on
sudo bluetoothctl agent on
sudo bluetoothctl default-agent

# Стартуем звуковой сервер
pulseaudio -k 2>/dev/null
pulseaudio --start --exit-idle-time=-1

# 3. ЦИКЛ ВЫБОРА И ПРОВЕРКИ ЗВУКА
while true; do
    echo -e "${BLUE}--- Настройка вывода звука ---${NC}"
    echo "1) Провод / USB / HDMI"
    echo "2) Bluetooth колонка"
    read -p "Твой выбор: " OUT_TYPE

    if [ "$OUT_TYPE" == "2" ]; then
        echo -e "${BLUE}Запуск сканирования (30 сек)... Включи поиск на колонке!${NC}"
        sudo bluetoothctl scan on > /dev/null &
        SCAN_PID=$!
        
        for i in {30..1}; do
            echo -ne "Ищу устройства... осталось $i сек. \r"
            sleep 1
        done
        echo -e "\n"
        
        devices=$(sudo bluetoothctl devices)
        kill $SCAN_PID 2>/dev/null
        
        if [ -z "$devices" ]; then
            echo -e "${RED}Устройства не найдены. Пробую сброс адаптера...${NC}"
            sudo hciconfig hci0 reset
            sleep 2
            continue
        fi

        echo -e "${GREEN}Найдены устройства:${NC}"
        mapfile -t device_list <<< "$devices"
        for i in "${!device_list[@]}"; do echo "$i) ${device_list[$i]}"; done
        
        read -p "Выбери номер устройства: " DEV_INPUT
        BT_MAC=$(echo ${device_list[$DEV_INPUT]} | awk '{print $2}')
        
        echo -e "${BLUE}Подключаю $BT_MAC...${NC}"
        sudo bluetoothctl remove $BT_MAC >/dev/null 2>&1
        sleep 1
        sudo bluetoothctl pair $BT_MAC
        sudo bluetoothctl trust $BT_MAC
        sudo bluetoothctl connect $BT_MAC
        OUT_DEVICE="pulse"
    else
        aplay -l | grep 'card'
        read -p "Введите НОМЕР карты вывода (обычно 0): " CARD_ID
        OUT_DEVICE="hw:$CARD_ID,0"
    fi

    # ПЕТЛЯ ПРОВЕРКИ ЗВУКА
    while true; do
        echo -e "${BLUE}Слушай! Подаю сигнал на $OUT_DEVICE...${NC}"
        speaker-test -t sine -f 440 -l 1 -d $OUT_DEVICE > /dev/null 2>&1 &
        TEST_PID=$!
        sleep 3
        kill $TEST_PID 2>/dev/null

        echo -e "${GREEN}Ты слышал звук?${NC}"
        echo "y - Да | n - Нет (назад) | r - Повторить"
        read -p "Ответ: " TEST_ANSWER

        if [ "$TEST_ANSWER" == "y" ]; then
            break 2
        elif [ "$TEST_ANSWER" == "n" ]; then
            [ "$OUT_TYPE" == "2" ] && sudo bluetoothctl remove $BT_MAC >/dev/null 2>&1
            break
        elif [ "$TEST_ANSWER" == "r" ]; then
            continue
        fi
    done
done

# 4. НАСТРОЙКА МИКРОФОНА
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

# 6. КОНФИГУРАЦИЯ MPD
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

# 7. WYOMING SATELLITE (ZIX VOICE)
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
    --auto-gain 7 \
    --noise-suppression 3 \
    --allow-discovery
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# 8. ЗАПУСК ВСЕХ СЕРВИСОВ
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Zix v$VERSION УСПЕШНО УСТАНОВЛЕН!${NC}"
echo -e "Теперь Zix транслирует звук на твою колонку."
echo -e "${BLUE}====================================================${NC}"
