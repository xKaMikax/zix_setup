#!/bin/bash

# =================================================================
# ZIX UNINSTALLER - CLEAN SWEEP
# =================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}--- Полное удаление системы Zix ---${NC}"

# 1. Останавливаем и отключаем службы
echo "Остановка служб..."
sudo systemctl stop wyoming-satellite mpd shairport-sync avahi-daemon 2>/dev/null
sudo systemctl disable wyoming-satellite mpd shairport-sync avahi-daemon 2>/dev/null

# 2. Удаляем системные файлы
echo "Удаление конфигов и сервисов..."
sudo rm /etc/systemd/system/wyoming-satellite.service 2>/dev/null
sudo rm /etc/mpd.conf 2>/dev/null

# 3. Удаляем папки проекта
echo "Удаление файлов приложения..."
sudo rm -rf /opt/wyoming-satellite
sudo rm -rf /var/lib/mpd

# 4. Очистка
sudo systemctl daemon-reload
echo -e "${GREEN}Zix полностью удален из системы.${NC}"
