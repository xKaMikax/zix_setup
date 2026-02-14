#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}--- Удаление Zix Smart Speaker ---${NC}"

# 1. Остановка сервисов
sudo systemctl stop wyoming-satellite mpd
sudo systemctl disable wyoming-satellite mpd

# 2. Удаление файлов
sudo rm /etc/systemd/system/wyoming-satellite.service
sudo rm -rf /opt/wyoming-satellite
sudo rm /etc/mpd.conf

# 3. Удаление пользователя (опционально)
# sudo userdel zix

sudo systemctl daemon-reload

echo -e "${GREEN}Все компоненты Zix удалены.${NC}"
