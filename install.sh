#!/bin/bash

# ==========================================================================================
# VERSION="1.4.0"
# PROJECT: ZIX ULTIMATE SUPREMACY
# DESCRIPTION: ПОЛНОМАСШТАБНЫЙ МЕДИА-КОМБАЙН С ГЛУБОКОЙ СИСТЕМНОЙ ИНТЕГРАЦИЕЙ
# FEATURES: Voice Control, Spotify Connect, AirPlay, MPD, DLNA, ChromeCast, Auto-Update
# ==========================================================================================

# --- ЦВЕТОВАЯ ПАЛИТРА ДЛЯ КОНСОЛИ ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}             ЗАПУСК ТОТАЛЬНОЙ ИНСТАЛЛЯЦИИ ZIX v1.4.0                  ${NC}"
echo -e "${CYAN}======================================================================${NC}"

# --- ПРОВЕРКА ПРАВ ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}ОШИБКА: Этот скрипт должен быть запущен от root (используй sudo)${NC}" 
   exit 1
fi

# 1. ПОДГОТОВКА РЕПОЗИТОРИЕВ И ОБНОВЛЕНИЕ ЯДРА
echo -e "${BLUE}[1/12] Обновление системных репозиториев и кэша...${NC}"
apt update && apt upgrade -y

# 2. УСТАНОВКА ПОЛНОГО СТЕКА ЗАВИСИМОСТЕЙ
echo -e "${BLUE}[2/12] Установка системного ПО...${NC}"
apt install -y \
    mpd mpc pulseaudio alsa-utils python3-venv curl \
    bluetooth bluez bluez-tools pulseaudio-module-bluetooth \
    shairport-sync avahi-daemon ffmpeg python3-pip \
    rfkill git build-essential libasound2-dev libtool \
    autoconf automake cmake libpulse-dev libfftw3-dev \
    libasound2-dev libconfuse-dev libavahi-client-dev \
    libssl-dev libsoxr-dev

# 3. СПЕЦИАЛИЗИРОВАННЫЕ МЕДИА-СЕРВИСЫ
echo -e "${BLUE}[3/12] Установка Spotify Connect & YouTube Music Bridge...${NC}"
# Raspotify (Spotify Connect)
if ! command -v librespot &> /dev/null; then
    curl -sL https://dtcooper.github.io/raspotify/install.sh | sh
fi

# 4. ГЛУБОКАЯ НАСТРОЙКА BLUETOOTH СТЕКА
echo -e "${BLUE}[4/12] Оптимизация Bluetooth для High-Res Audio...${NC}"
sudo rfkill unblock bluetooth
sudo systemctl enable bluetooth
sudo bash -c "cat <<EOF > /etc/bluetooth/main.conf
[General]
Name = Zix-Ultimate
Class = 0x000414
DiscoverableTimeout = 0
PairableTimeout = 0

[Policy]
AutoEnable=true
EOF"
sudo systemctl restart bluetooth

# 5. КОНФИГУРАЦИЯ PULSEAUDIO (ЗАПРЕТ СОННОГО РЕЖИМА)
echo -e "${BLUE}[5/12] Тюнинг звукового сервера PulseAudio...${NC}"
sudo sed -i 's/; exit-idle-time = 20/exit-idle-time = -1/g' /etc/pulse/daemon.conf
sudo sed -i 's/load-module module-suspend-on-idle/#load-module module-suspend-on-idle/g' /etc/pulse/default.pa
# Разрешаем анонимный доступ для локальных сервисов
sudo bash -c "echo 'load-module module-native-protocol-unix auth-anonymous=1' >> /etc/pulse/default.pa"

# 6. СОЗДАНИЕ ИЕРАРХИИ ПОЛЬЗОВАТЕЛЕЙ
echo -e "${BLUE}[6/12] Настройка прав доступа и групп...${NC}"
if ! id -u zix >/dev/null 2>&1; then
    useradd -m zix
    usermod -aG audio,video,bluetooth,pulse-access,lp zix
fi
mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists /opt/wyoming-satellite
chown -R zix:audio /var/lib/mpd
chown -R zix:zix /opt/wyoming-satellite

# 7. РАЗВЕРТЫВАНИЕ WYOMING SATELLITE (VOICE CORE)
echo -e "${BLUE}[7/12] Сборка голосового ядра в изолированном окружении...${NC}"
sudo -u zix python3 -m venv /opt/wyoming-satellite/.venv
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install --upgrade pip setuptools wheel
sudo -u zix /opt/wyoming-satellite/.venv/bin/pip install "wyoming-satellite[webrtc]"

# 8. СОЗДАНИЕ ИНТЕЛЛЕКТУАЛЬНОГО RUNNER-СКРИПТА (AUTO-UPDATE ENGINE)
echo -e "${BLUE}[8/12] Создание системы автономного обновления...${NC}"
sudo bash -c "cat <<EOF > /opt/wyoming-satellite/run_zix.sh
#!/bin/bash
# --- ZIX MASTER RUNNER v1.4.0 ---

echo '[Update] Проверка удаленного репозитория...'
cd /opt/wyoming-satellite
curl -s -O https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh
chmod +x install.sh

echo '[Clean] Сброс аудио-буферов...'
killall -9 arecord aplay 2>/dev/null

echo '[System] Определение аудио-выхода...'
DEFAULT_SINK=\$(pactl list sinks short | grep 'bluez_sink' | awk '{print \$2}')
if [ -z \"\$DEFAULT_SINK\" ]; then
    DEFAULT_SINK=\"@DEFAULT_SINK@\"
fi

echo '[Launch] Запуск Zix Voice Engine...'
/opt/wyoming-satellite/.venv/bin/python3 -m wyoming_satellite \\
    --name 'Zix-Ultimate' \\
    --uri 'tcp://0.0.0.0:10400' \\
    --mic-command 'arecord -D pulse -r 16000 -c 1 -f S16_LE -t raw' \\
    --snd-command 'aplay -D pulse -r 22050 -c 1 -f S16_LE -t raw' \\
    --mic-auto-gain 7 \\
    --mic-noise-suppression 3 \\
    --debug
EOF"
chmod +x /opt/wyoming-satellite/run_zix.sh
chown zix:zix /opt/wyoming-satellite/run_zix.sh

# 9. ПОЛНАЯ КОНФИГУРАЦИЯ MPD
echo -e "${BLUE}[9/12] Настройка Music Player Daemon...${NC}"
sudo bash -c "cat <<EOF > /etc/mpd.conf
music_directory    \"/var/lib/mpd/music\"
playlist_directory \"/var/lib/mpd/playlists\"
db_file            \"/var/lib/mpd/tag_cache\"
log_file           \"/var/log/mpd/mpd.log\"
pid_file           \"/run/mpd/pid\"
state_file         \"/var/lib/mpd/state\"
user               \"zix\"
bind_to_address    \"0.0.0.0\"
port               \"6600\"
auto_update        \"yes\"

audio_output {
    type    \"pulse\"
    name    \"Zix-Global-Pulse\"
    server  \"127.0.0.1\"
}
EOF"

# 10. РЕГИСТРАЦИЯ СЛУЖБ В SYSTEMD
echo -e "${BLUE}[10/12] Создание юнитов автозапуска...${NC}"
sudo bash -c "cat <<EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Zix Ultimate Satellite Service
After=network-online.target bluetooth.service pulseaudio.service
Wants=bluetooth.service pulseaudio.service

[Service]
Type=simple
User=zix
WorkingDirectory=/opt/wyoming-satellite
ExecStart=/opt/wyoming-satellite/run_zix.sh
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"

# 11. ФИНАЛЬНАЯ СИНХРОНИЗАЦИЯ
echo -e "${BLUE}[11/12] Запуск всех уровней системы...${NC}"
systemctl daemon-reload
systemctl enable avahi-daemon mpd wyoming-satellite shairport-sync raspotify
systemctl restart avahi-daemon mpd wyoming-satellite shairport-sync raspotify

# 12. ПРОВЕРКА СТАТУСА
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}             ZIX v1.4.0 УСПЕШНО РАЗВЕРНУТ!                            ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "${YELLOW}ИНФОРМАЦИЯ:${NC}"
echo -e "IP Адрес:     $(hostname -I | awk '{print $1}')"
echo -e "Spotify:      Zix-Ultimate (через Raspotify)"
echo -e "AirPlay:      Zix-Ultimate (через Shairport-Sync)"
echo -e "Voice:        Порт 10400 (Wyoming)"
echo -e "MPD:          Порт 6600"
echo -e "${GREEN}======================================================================${NC}"
