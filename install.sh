#!/bin/bash

# =================================================================
VERSION="1.1.14"
# ZIX ULTIMATE - THE UNBREAKABLE SETUP
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

# 2. ПОДГОТОВКА СИСТЕМЫ
echo -e "${GREEN}[1/8] Установка пакетов и чистка Bluetooth...${NC}"
sudo apt update && sudo apt install -y mpd mpc pulseaudio alsa-utils curl \
bluetooth bluez bluez-tools rfkill pulseaudio-module-bluetooth python3-venv

# Жесткий сброс BT
sudo systemctl stop bluetooth
sudo rfkill unblock bluetooth
sudo hciconfig hci0 down 2>/dev/null
sudo hciconfig hci0 up 2>/dev/null
sudo systemctl start bluetooth
sleep 2
sudo bluetoothctl power on

# 3. НАСТРОЙКА ЗВУКА
while true; do
    echo -e "${BLUE}--- Вывод звука ---${NC}"
    echo "1) Провод / HDMI"
    echo "2) Bluetooth колонка"
    read -p "Выбор: " OUT_TYPE

    if [ "$OUT_TYPE" == "2" ]; then
        # Проверка активного подключения
        CONN_MAC=$(bluetoothctl devices Connected | awk '{print $2}')
        if [ ! -z "$CONN_MAC" ]; then
            echo -e "${GREEN}Колонка уже подключена! Использую текущую.${NC}"
            BT_MAC=$CONN_MAC
            OUT_DEVICE="pulse"
        else
            echo -e "${BLUE}Поиск (25 сек)... Включи Pairing Mode на колонке!${NC}"
            sudo bluetoothctl scan on > /dev/null &
            SCAN_PID=$!
            for i in {25..1}; do echo -ne "Ищу... $i сек. \r"; sleep 1; done
            kill $SCAN_PID 2>/dev/null
            
            devices=$(bluetoothctl devices)
            if [ -z "$devices" ]; then echo -e "${RED}Пусто! Попробуем еще раз.${NC}"; continue; fi
            
            mapfile -t device_list <<< "$devices"
            for i in "${!device_list[@]}"; do echo "$i) ${device_list[$i]}"; done
            read -p "Выбери номер: " DEV_IN
            BT_MAC=$(echo ${device_list[$DEV_IN]} | awk '{print $2}')
            
            bluetoothctl pair $BT_MAC && bluetoothctl trust $BT_MAC && bluetoothctl connect $BT_MAC
            OUT_DEVICE="pulse"
        fi
    else
        aplay -l | grep 'card'
        read -p "Номер карты вывода (0, 1...): " CARD_ID
        OUT_DEVICE="hw:$CARD_ID,0"
    fi

    # Тест
    speaker-test -t sine -f 440 -l 1 -d $OUT_DEVICE > /dev/null 2>&1 &
    sleep 3
    read -p "Слышал звук? (y/n/r): " T_ANS
    [ "$T_ANS" == "y" ] && break
done

# 4. МИКРОФОН
arecord -l | grep 'card'
read -p "Введите НОМЕР карты микрофона: " IN_CARD

# 5. ПОЛЬЗОВАТЕЛЬ И ПАПКИ
if ! id -u zix >/dev/null 2>&1; then sudo useradd -m zix; sudo usermod -aG audio,bluetooth zix; fi
sudo mkdir -p /var/lib/mpd/music /opt/wyoming-satellite
sudo chown -R zix:audio /var/lib/mpd
sudo chown zix:zix /opt/wyoming-satellite

# 6. WYOMING VENV
echo -e "${GREEN}Настройка Python окружения...${NC}"
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

# 7. СОЗДАНИЕ СЕРВИСА (БЕЗ ОБРЕЗАНИЯ)
echo -e "${GREEN}Создание службы Wyoming...${NC}"
sudo bash -c "cat > /etc/systemd/system/wyoming-satellite.service <<EOF
[Unit]
Description=Wyoming Satellite Zix
After=network-online.target bluetooth.service pulseaudio.service

[Service]
Type=simple
User=zix
ExecStart=/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \\
    --name 'Zix' \\
    --uri 'tcp://0.0.0.0:10400' \\
    --mic-command 'arecord -D hw:$IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D $OUT_DEVICE -r 22050 -c 1 -f S16_LE -t raw' \\
    --ducking-volume 0.2 \\
    --auto-gain 7 \\
    --noise-suppression 3 \\
    --allow-discovery
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

# 8. MPD CONFIG
sudo bash -c "cat > /etc/mpd.conf <<EOF
music_directory \"/var/lib/mpd/music\"
user \"zix\"
bind_to_address \"0.0.0.0\"
audio_output {
    type \"pulse\"
    name \"Zix Bluetooth\"
}
EOF"

# ФИНАЛ
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite
sudo systemctl restart bluetooth mpd wyoming-satellite

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Zix v$VERSION ГОТОВ!${NC}"
echo -e "IP малинки: $(hostname -I | awk '{print $1}')"
echo -e "Порт для HA: 10400"
echo -e "${BLUE}====================================================${NC}"
