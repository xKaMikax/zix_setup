#!/bin/bash
# ZIX UNINSTALLER v1.2.5

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}--- УДАЛЕНИЕ СИСТЕМЫ ZIX ---${NC}"

echo "Остановка всех служб..."
sudo systemctl stop wyoming-satellite mpd shairport-sync avahi-daemon 2>/dev/null
sudo systemctl disable wyoming-satellite mpd shairport-sync avahi-daemon 2>/dev/null

echo "Удаление системных файлов и конфигураций..."
sudo rm /etc/systemd/system/wyoming-satellite.service 2>/dev/null
sudo rm /etc/mpd.conf 2>/dev/null
sudo rm -rf /opt/wyoming-satellite
sudo rm -rf /var/lib/mpd

echo "Обновление демона системы..."
sudo systemctl daemon-reload

echo -e "${GREEN}Zix успешно и полностью удален.${NC}"
