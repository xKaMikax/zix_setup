#!/bin/bash
# ZIX UNINSTALLER

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}--- Полное удаление системы Zix ---${NC}"

echo "Остановка служб..."
sudo systemctl stop wyoming-satellite mpd shairport-sync avahi-daemon 2>/dev/null
sudo systemctl disable wyoming-satellite mpd shairport-sync avahi-daemon 2>/dev/null

echo "Удаление файлов и конфигов..."
sudo rm /etc/systemd/system/wyoming-satellite.service 2>/dev/null
sudo rm /etc/mpd.conf 2>/dev/null
sudo rm -rf /opt/wyoming-satellite
sudo rm -rf /var/lib/mpd

sudo systemctl daemon-reload
echo -e "${GREEN}Система Zix полностью удалена.${NC}"
