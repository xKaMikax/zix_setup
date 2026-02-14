#!/bin/bash

# =================================================================
# VERSION="1.1.17"
# ZIX ULTIMATE - FULL SYSTEM DEPLOYMENT
# Стек: MPD, AirPlay (Shairport), Spotify (GMediaRender), Wyoming
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}--- Интеллектуальная система Zix v1.1.17 ---${NC}"

# 1. ОБНОВЛЕНИЕ И УСТАНОВКА ПАКЕТОВ
echo -e "${GREEN}[1/8] Установка системных пакетов...${NC}"
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils curl gmediarender \
shairport-sync python3-pip python3-venv libasound2-dev \
bluetooth bluez bluez-tools ffmpeg expect rfkill pulseaudio-module-bluetooth

# Принудительный сброс Bluetooth
sudo rfkill unblock bluetooth
sudo systemctl start bluetooth
sudo bluetoothctl power on
sudo bluetoothctl agent on
sudo bluetoothctl default-agent

# Старт звука
pulseaudio -k 2>/dev/null
pulseaudio --start --exit-idle-time=-1

# 2. НАСТРОЙКА ВЫВОДА ЗВУКА
while true; do
    echo -e "${BLUE}--- Настройка вывода звука ---${NC}"
    echo "1) Провод / USB / HDMI"
    echo "2) Bluetooth колонка"
    read -p "Твой выбор: " OUT_TYPE

    if [ "$OUT_TYPE" == "2" ]; then
        echo -e "${BLUE}Запуск сканирования (20 сек)... Включи поиск на колонке!${NC}"
        sudo bluetoothctl scan on > /dev/null &
        SCAN_PID=$!
        for i in {20..1}; do echo -ne "Ищу устройства... осталось $i сек. \r"; sleep 1; done
        kill $SCAN_PID 2>/dev/null
        echo -e "\n"

        devices=$(sudo bluetoothctl devices)
        if [ -z "$devices" ]; then
            echo -e "${RED}Список пуст. Попробуй еще раз.${NC}"; continue
        fi

        mapfile -t device_list <<< "$devices"
        for i in "${!device_list[@]}"; do echo "$i) ${device_list[$i]}"; done
        read -p "Номер устройства: " DEV_INPUT
        BT_MAC=$(echo ${device_list[$DEV_INPUT]} | awk '{print $2}')

        echo -e "${BLUE}Подключение к $BT_MAC...${NC}"
        bluetoothctl trust $BT_MAC
        # Если уже спарено, pair выдаст ошибку, но мы идем дальше к connect
        bluetoothctl pair $BT_MAC
        bluetoothctl connect $BT_MAC
        
        sleep 2
        FINAL_OUT_DEVICE="pulse"
    else
        aplay -l | grep 'card'
        read -p "Номер карты вывода (0, 1...): " CARD_ID
        FINAL_OUT_DEVICE="hw:$CARD_ID,0"
    fi

    echo -e "${BLUE}Проверка звука...${NC}"
    speaker-test -t sine -f 440 -l 1 -d $FINAL_OUT_DEVICE > /dev/null 2>&1 &
    sleep 3
    read -p "Звук был? (y/n/r): " TEST_OK
    [ "$TEST_OK" == "y" ] && break
done

# 3. НАСТРОЙКА МИКРОФОНА
echo -e "${BLUE}--- Настройка микрофона ---${NC}"
arecord -l | grep 'card'
read -p "Введите НОМЕР карты микрофона: " FINAL_IN_CARD

# 4. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ И ПРАВА
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists /opt/wyoming-satellite
sudo chown -R zix:audio /var/lib/mpd
sudo chown -R zix:zix /opt/wyoming-satellite

# 5. КОНФИГУРАЦИЯ MPD
echo -e "${GREEN}[5/8] Настройка MPD...${NC}"
sudo bash -c "cat <<EOF > /etc/mpd.conf
music_directory    \"/var/lib/mpd/music\"
playlist_directory \"/var/lib/mpd/playlists\"
user               \"zix\"
bind_to_address    \"0.0.0.0\"
audio_output {
    type    \"pulse\"
    name    \"Zix Speaker\"
}
EOF"

# 6. УСТАНОВКА WYOMING VENV
echo -e "${GREEN}[6/8] Установка Wyoming...${NC}"
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

# 7. СОЗДАНИЕ СТАБИЛЬНОГО RUNNER.SH
# Мы используем EOF без кавычек, чтобы переменные FINAL_ вписались в файл навсегда
echo -e "${GREEN}[7/8] Создание runner-скрипта...${NC}"
sudo bash -c "cat <<EOF > /opt/wyoming-satellite/run_zix.sh
#!/bin/bash
/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \\
    --name 'Zix' \\
    --uri 'tcp://0.0.0.0:10400' \\
    --mic-command 'arecord -D hw:$FINAL_IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D $FINAL_OUT_DEVICE -r 22050 -c 1 -f S16_LE -t raw' \\
    --ducking-volume 0.2 \\
    --auto-gain 7 \\
    --noise-suppression 3 \\
    --allow-discovery
EOF"

sudo chmod +x /opt/wyoming-satellite/run_zix.sh
sudo chown zix:zix /opt/wyoming-satellite/run_zix.sh

# 8. СОЗДАНИЕ СЕРВИСА SYSTEMD
echo -e "${GREEN}[8/8] Создание системной службы...${NC}"
sudo bash -c "cat <<EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Wyoming Satellite Zix
After=network-online.target bluetooth.service pulseaudio.service

[Service]
Type=simple
User=zix
ExecStart=/opt/wyoming-satellite/run_zix.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

# ФИНАЛ
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite gmediarender shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite gmediarender shairport-sync

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Zix v$VERSION ГОТОВ!${NC}"
echo -e "IP: $(hostname -I | awk '{print $1}') | Port: 10400"
echo -e "${BLUE}====================================================${NC}"
