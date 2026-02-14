#!/bin/bash

# =================================================================
# VERSION="1.1.16"
# ZIX ULTIMATE - WRAPPER & STABILITY EDITION
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}--- Интеллектуальная система Zix v1.1.16 ---${NC}"

# 1. ПАКЕТЫ
echo -e "${GREEN}[1/8] Установка системного стека...${NC}"
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils bluetooth bluez python3-venv curl rfkill

# Чиним Bluetooth
sudo rfkill unblock bluetooth
sudo systemctl start bluetooth
sudo bluetoothctl power on

# 2. ВЫБОР ЗВУКА
while true; do
    echo -e "${BLUE}--- Настройка вывода звука ---${NC}"
    echo "1) Провод / HDMI"
    echo "2) Bluetooth колонка"
    read -p "Выбор: " OUT_TYPE

    if [ "$OUT_TYPE" == "2" ]; then
        echo -e "${BLUE}Поиск устройств...${NC}"
        sudo bluetoothctl scan on > /dev/null &
        SCAN_PID=$!
        sleep 15
        kill $SCAN_PID 2>/dev/null
        
        devices=$(bluetoothctl devices)
        if [ -z "$devices" ]; then echo "Не найдено!"; continue; fi
        
        mapfile -t device_list <<< "$devices"
        for i in "${!device_list[@]}"; do echo "$i) ${device_list[$i]}"; done
        read -p "Выбери номер: " DEV_IN
        BT_MAC=$(echo ${device_list[$DEV_IN]} | awk '{print $2}')

        # Умное подключение
        bluetoothctl trust $BT_MAC
        bluetoothctl pair $BT_MAC
        bluetoothctl connect $BT_MAC
        OUT_DEVICE="pulse"
    else
        aplay -l | grep 'card'
        read -p "Номер карты вывода: " CARD_ID
        OUT_DEVICE="hw:$CARD_ID,0"
    fi

    speaker-test -t sine -f 440 -l 1 -d $OUT_DEVICE > /dev/null 2>&1 &
    sleep 3
    read -p "Звук был? (y/n): " T_ANS
    [ "$T_ANS" == "y" ] && break
done

# 3. МИКРОФОН
arecord -l | grep 'card'
read -p "Введите НОМЕР карты микрофона: " IN_CARD

# 4. ПОЛЬЗОВАТЕЛЬ И ПАПКИ
if ! id -u zix >/dev/null 2>&1; then 
    sudo useradd -m zix
    sudo usermod -aG audio,bluetooth zix
fi
sudo mkdir -p /var/lib/mpd/music /opt/wyoming-satellite
sudo chown -R zix:audio /var/lib/mpd
sudo chown -R zix:zix /opt/wyoming-satellite

# 5. PYTHON VENV
echo -e "${GREEN}Установка Wyoming...${NC}"
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

# 6. СОЗДАНИЕ RUNNER-СКРИПТА (Чтобы не ломались строки)
echo -e "${GREEN}Создание runner.sh...${NC}"
sudo bash -c "cat <<'RUN' > /opt/wyoming-satellite/run_zix.sh
#!/bin/bash
/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \\
    --name 'Zix' \\
    --uri 'tcp://0.0.0.0:10400' \\
    --mic-command 'arecord -D hw:$IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D $OUT_DEVICE -r 22050 -c 1 -f S16_LE -t raw' \\
    --ducking-volume 0.2 \\
    --auto-gain 7 \\
    --noise-suppression 3 \\
    --allow-discovery
RUN"
sudo chmod +x /opt/wyoming-satellite/run_zix.sh
sudo chown zix:zix /opt/wyoming-satellite/run_zix.sh

# 7. СЕРВИС
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

# 8. СТАРТ
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite
sudo systemctl restart bluetooth mpd wyoming-satellite

echo -e "${GREEN}Установка v$VERSION завершена!${NC}"
