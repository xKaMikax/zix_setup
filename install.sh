#!/bin/bash

# =================================================================
# VERSION="1.1.5"
# ZIX ULTIMATE - FORCE BT POWER & DISCOVERY
# Repo: https://github.com/xKaMikax/zix_setup
# =================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/xKaMikax/zix_setup/main/install.sh"
LOCAL_FILE="install.sh"

# --- ОБНОВЛЕНИЕ ---
REMOTE_VERSION=$(wget -qO- "$REPO_RAW_URL" | grep -m 1 "VERSION=" | cut -d'"' -f2)
LOCAL_VERSION=$(grep -m 1 "VERSION=" "$LOCAL_FILE" | cut -d'"' -f2)

if [ ! -z "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    wget -qO "$LOCAL_FILE" "$REPO_RAW_URL" && chmod +x "$LOCAL_FILE" && exec ./"$LOCAL_FILE"
fi

# [Подготовка]
sudo rfkill unblock all
sudo systemctl start bluetooth
# Ждем инициализации драйвера
sleep 2

# Пробуждаем контроллер программно
echo -e "${BLUE}Активация контроллера Bluetooth...${NC}"
sudo bluetoothctl power on
sudo bluetoothctl agent on
sudo bluetoothctl default-agent

echo -e "${BLUE}--- Настройка звука Zix ---${NC}"
echo "1) Провод / USB"
echo "2) Bluetooth колонка"
read -p "Выбор: " OUT_TYPE

if [ "$OUT_TYPE" == "2" ]; then
    echo -e "${BLUE}Поиск устройств Zix (20 сек)... Включи на колонке поиск!${NC}"
    
    # Запускаем сканирование в фоне
    sudo bluetoothctl --timeout 20 scan on > /dev/null &
    sleep 21
    
    devices=$(sudo bluetoothctl devices)
    
    if [ -z "$devices" ]; then
        echo -e "${RED}Устройства всё еще не найдены.${NC}"
        echo -e "${BLUE}Попробуй выполнить команду:${NC} bluetoothctl show"
        echo -e "Если там написано 'Powered: no', значит адаптер спит."
        exit 1
    fi

    echo -e "${GREEN}Найденные устройства:${NC}"
    mapfile -t device_list <<< "$devices"
    for i in "${!device_list[@]}"; do
        echo "$i) ${device_list[$i]}"
    done

    read -p "Выбери номер: " DEV_NUM
    BT_MAC=$(echo ${device_list[$DEV_NUM]} | awk '{print $2}')
    
    echo -e "${BLUE}Сопряжение с $BT_MAC...${NC}"
    sudo bluetoothctl pair $BT_MAC
    sudo bluetoothctl trust $BT_MAC
    sudo bluetoothctl connect $BT_MAC
    OUT_DEVICE="pulse"
else
    # [Тут старый код для проводного вывода]
    aplay -l | grep 'card'
    read -p "Номер карты: " CARD_ID
    OUT_DEVICE="hw:$CARD_ID,0"
fi

# ... [Остальной код (Пользователь, MPD, Wyoming) остается прежним] ...
