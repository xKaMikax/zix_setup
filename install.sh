#!/bin/bash

# =================================================================
# VERSION="1.2.5"
# PROJECT: ZIX ULTIMATE SMART SPEAKER & MEDIA HUB
# Особенности: Автообновление, WebRTC Fix, MPD, Spotify, AirPlay
# =================================================================

# Цветовая схема для красоты и читаемости
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}          ЗАПУСК УСТАНОВКИ ZIX v1.2.5               ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. СИСТЕМНАЯ ПОДГОТОВКА И ЗАВИСИМОСТИ
echo -e "${GREEN}[1/8] Обновление системы и установка пакетов...${NC}"
sudo apt update
sudo apt install -y \
    mpd mpc pulseaudio alsa-utils python3-venv curl \
    bluetooth bluez bluez-tools pulseaudio-module-bluetooth \
    shairport-sync avahi-daemon librespot ffmpeg python3-pip \
    rfkill git build-essential libasound2-dev

# 2. ОЖИВЛЕНИЕ BLUETOOTH И ЗВУКА
echo -e "${GREEN}[2/8] Активация аудио-движка...${NC}"
sudo rfkill unblock bluetooth
sudo systemctl start bluetooth
sudo bluetoothctl power on
pulseaudio -k 2>/dev/null
pulseaudio --start --exit-idle-time=-1

# 3. ЕДИНСТВЕННЫЙ ШАГ КОНФИГУРАЦИИ: МИКРОФОН
echo -e "${YELLOW}--- ТВОЯ ПОМОЩЬ НУЖНА ЗДЕСЬ ---${NC}"
arecord -l | grep 'card'
echo -e "${YELLOW}Посмотри на список выше.${NC}"
read -p "Введи НОМЕР карты твоего микрофона: " FINAL_IN_CARD

# 4. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ И СТРУКТУРЫ
echo -e "${GREEN}[3/8] Создание системного пользователя zix...${NC}"
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists /opt/wyoming-satellite
sudo chown -R zix:audio /var/lib/mpd
sudo chown -R zix:zix /opt/wyoming-satellite

# 5. УСТАНОВКА WYOMING С ПОДДЕРЖКОЙ WEBRTC
echo -e "${GREEN}[4/8] Настройка голосового ядра (Python VENV)...${NC}"
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip
echo -e "${BLUE}Установка Wyoming-Satellite с библиотеками шумоподавления...${NC}"
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install "wyoming-satellite[webrtc]"

# 6. СОЗДАНИЕ УМНОГО RUNNER.SH (СИСТЕМА АВТООБНОВЛЕНИЯ)
echo -e "${GREEN}[5/8] Создание скрипта автообновления и запуска...${NC}"
sudo bash -c "cat <<EOF > /opt/wyoming-satellite/run_zix.sh
#!/bin/bash
# ZIX RUNNER v1.2.5

echo '--- ZIX AUTO-UPDATE ---'
cd /opt/wyoming-satellite
# Скачиваем свежий инсталлер, если он обновился на GitHub
curl -s -O https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh
echo 'Обновление проверено.'

echo '--- ЗАПУСК ГОЛОСОВОГО АССИСТЕНТА ---'
/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \\
    --name 'Zix' \\
    --uri 'tcp://0.0.0.0:10400' \\
    --mic-command 'arecord -D hw:$FINAL_IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D pulse -r 22050 -c 1 -f S16_LE -t raw' \\
    --mic-auto-gain 7 \\
    --mic-noise-suppression 3
EOF"

sudo chmod +x /opt/wyoming-satellite/run_zix.sh
sudo chown zix:zix /opt/wyoming-satellite/run_zix.sh

# 7. КОНФИГУРАЦИЯ МЕДИА-СЕРВИСОВ (MPD, Spotify, AirPlay)
echo -e "${GREEN}[6/8] Настройка музыкального центра...${NC}"

# MPD Конфиг
sudo bash -c "cat <<EOF > /etc/mpd.conf
music_directory    \"/var/lib/mpd/music\"
playlist_directory \"/var/lib/mpd/playlists\"
db_file            \"/var/lib/mpd/tag_cache\"
user               \"zix\"
bind_to_address    \"0.0.0.0\"
port               \"6600\"
audio_output {
    type    \"pulse\"
    name    \"Zix Bluetooth/System Output\"
}
EOF"

# 8. СОЗДАНИЕ СЕРВИСА SYSTEMD
echo -e "${GREEN}[7/8] Регистрация в системе автозапуска...${NC}"
sudo bash -c "cat <<EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Zix Ultimate Voice & Media
After=network-online.target bluetooth.service pulseaudio.service
Wants=bluetooth.service pulseaudio.service

[Service]
Type=simple
User=zix
WorkingDirectory=/opt/wyoming-satellite
ExecStart=/opt/wyoming-satellite/run_zix.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"

# 9. ФИНАЛЬНЫЙ ЗАПУСК И ПРОВЕРКА
echo -e "${GREEN}[8/8] Перезагрузка всех служб...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite avahi-daemon shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite avahi-daemon shairport-sync

# Настройка громкости по умолчанию
BT_SINK=\$(pactl list sinks short | grep "bluez_sink" | awk '{print \$2}')
if [ ! -z "\$BT_SINK" ]; then
    pactl set-default-sink \$BT_SINK
    pactl set-sink-volume \$BT_SINK 100%
fi

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}      УСТАНОВКА ZIX v1.2.5 ЗАВЕРШЕНА!               ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "Голос (HA):  ${YELLOW}Порт 10400${NC}"
echo -e "Spotify/AirPlay: ${YELLOW}$(hostname)${NC}"
echo -e "Музыка (MPD): ${YELLOW}Порт 6600${NC}"
echo -e "IP адрес:    ${GREEN}$(hostname -I | awk '{print $1}')${NC}"
echo -e "${BLUE}====================================================${NC}"
