#!/bin/bash

# =================================================================
# VERSION="1.2.0"
# ZIX ULTIMATE MEDIA CENTER (Full Edition)
# Стек: Wyoming (Voice), MPD (Music), Spotify, AirPlay
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}--- Интеллектуальная медиа-система Zix v1.2.0 ---${NC}"

# 1. ОБНОВЛЕНИЕ И УСТАНОВКА ПАКЕТОВ
echo -e "${GREEN}[1/7] Установка системных компонентов...${NC}"
sudo apt update
sudo apt install -y mpd mpc pulseaudio alsa-utils python3-venv curl \
bluetooth bluez pulseaudio-module-bluetooth shairport-sync \
avahi-daemon librespot ffmpeg python3-pip

# 2. НАСТРОЙКА МИКРОФОНА (ЕДИНСТВЕННЫЙ ШАГ)
echo -e "${BLUE}--- Настройка аудио-входа ---${NC}"
arecord -l | grep 'card'
read -p "Введите НОМЕР карты микрофона: " FINAL_IN_CARD

# 3. ПОЛЬЗОВАТЕЛЬ И ПРАВА
if ! id -u zix >/dev/null 2>&1; then
    sudo useradd -m zix
    sudo usermod -aG audio,video,bluetooth zix
fi
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists /opt/wyoming-satellite
sudo chown -R zix:audio /var/lib/mpd
sudo chown -R zix:zix /opt/wyoming-satellite

# 4. УСТАНОВКА WYOMING (ГОЛОСОВОЙ ПОМОЩНИК)
echo -e "${GREEN}[3/7] Установка Wyoming Satellite...${NC}"
[ ! -d "/opt/wyoming-satellite/.venv" ] && sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip wyoming-satellite

# Создание стабильного runner.sh
sudo bash -c "cat <<EOF > /opt/wyoming-satellite/run_zix.sh
#!/bin/bash
/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \\
    --name 'Zix' \\
    --uri 'tcp://0.0.0.0:10400' \\
    --mic-command 'arecord -D hw:$FINAL_IN_CARD,0 -r 16000 -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D pulse -r 22050 -c 1 -f S16_LE -t raw' \\
    --mic-auto-gain 7 \\
    --mic-noise-suppression 3 \\
    --allow-discovery
EOF"
sudo chmod +x /opt/wyoming-satellite/run_zix.sh
sudo chown zix:zix /opt/wyoming-satellite/run_zix.sh

# 5. КОНФИГУРАЦИЯ МУЗЫКАЛЬНЫХ СЕРВИСОВ
echo -e "${GREEN}[4/7] Настройка MPD и Spotify...${NC}"

# Конфиг MPD
sudo bash -c "cat <<EOF > /etc/mpd.conf
music_directory    \"/var/lib/mpd/music\"
playlist_directory \"/var/lib/mpd/playlists\"
user               \"zix\"
bind_to_address    \"0.0.0.0\"
audio_output {
    type    \"pulse\"
    name    \"Zix Audio Output\"
}
EOF"

# 6. СОЗДАНИЕ СИСТЕМНЫХ СЛУЖБ
echo -e "${GREEN}[5/7] Регистрация сервисов...${NC}"

# Сервис Wyoming
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

# 7. ЗАПУСК И МАРШРУТИЗАЦИЯ
echo -e "${GREEN}[6/7] Финальный запуск...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable bluetooth mpd wyoming-satellite avahi-daemon shairport-sync
sudo systemctl restart bluetooth mpd wyoming-satellite avahi-daemon shairport-sync

# Авто-подхват Bluetooth колонки (если она уже подключена)
BT_SINK=$(pactl list sinks short | grep "bluez_sink" | awk '{print $2}')
if [ ! -z "$BT_SINK" ]; then
    pactl set-default-sink $BT_SINK
    pactl set-sink-volume $BT_SINK 100%
fi

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Zix v1.2.0 УСПЕШНО УСТАНОВЛЕН!${NC}"
echo -e "Spotify/AirPlay: Виден в сети как '$(hostname)'"
echo -e "Voice Assistant: Порт 10400"
echo -e "IP: $(hostname -I | awk '{print $1}')"
echo -e "${BLUE}====================================================${NC}"
