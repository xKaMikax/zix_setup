#!/bin/bash
# ZIX UNINSTALLER

RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}--- Полное удаление системы Zix ---${NC}"

# Останавливаем всё
sudo systemctl stop wyoming-satellite mpd gmediarender shairport-sync bluetooth
sudo systemctl disable wyoming-satellite mpd gmediarender shairport-sync

# Удаляем сервис и папки
sudo rm /etc/systemd/system/wyoming-satellite.service
sudo rm -rf /opt/wyoming-satellite
sudo rm /etc/mpd.conf

sudo systemctl daemon-reload
echo "Zix успешно удален."
