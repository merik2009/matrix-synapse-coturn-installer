#!/bin/bash

# Скрипт для обновления Matrix Synapse

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Загрузка конфигурации
if [ -f "./configs/install_config.env" ]; then
    source ./configs/install_config.env
    print_info "Конфигурация загружена"
else
    print_error "Файл конфигурации не найден! Запустите install.sh сначала."
    exit 1
fi

update_synapse() {
    print_header "ОБНОВЛЕНИЕ MATRIX SYNAPSE"
    
    # Создание резервной копии
    print_info "Создание резервной копии..."
    sudo systemctl stop matrix-synapse
    sudo -u postgres pg_dump synapse > "./data/synapse_backup_$(date +%Y%m%d_%H%M%S).sql"
    sudo cp -r /etc/synapse "./data/synapse_config_backup_$(date +%Y%m%d_%H%M%S)"
    
    # Обновление Synapse
    print_info "Обновление Matrix Synapse..."
    sudo -u synapse /var/lib/synapse/venv/bin/pip install --upgrade matrix-synapse[postgres]
    
    # Запуск сервиса
    sudo systemctl start matrix-synapse
    
    # Проверка статуса
    if sudo systemctl is-active --quiet matrix-synapse; then
        print_success "Matrix Synapse успешно обновлен и запущен"
    else
        print_error "Ошибка при запуске Matrix Synapse"
        exit 1
    fi
}

update_coturn() {
    print_header "ОБНОВЛЕНИЕ COTURN"
    
    print_info "Обновление Coturn..."
    sudo apt update
    sudo apt upgrade -y coturn
    
    sudo systemctl restart coturn
    
    if sudo systemctl is-active --quiet coturn; then
        print_success "Coturn успешно обновлен и перезапущен"
    else
        print_error "Ошибка при перезапуске Coturn"
        exit 1
    fi
}

update_ssl_certificates() {
    print_header "ОБНОВЛЕНИЕ SSL СЕРТИФИКАТОВ"
    
    print_info "Проверка и обновление SSL сертификатов..."
    sudo certbot renew --quiet
    sudo systemctl reload nginx
    sudo systemctl restart coturn
    
    print_success "SSL сертификаты проверены и обновлены"
}

show_status() {
    print_header "СТАТУС СЕРВИСОВ"
    
    services=("postgresql" "matrix-synapse" "coturn" "nginx")
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet $service; then
            print_success "$service: активен"
        else
            print_error "$service: неактивен"
        fi
    done
    
    # Проверка версии Synapse
    SYNAPSE_VERSION=$(sudo -u synapse /var/lib/synapse/venv/bin/python -c "import synapse; print(synapse.__version__)")
    print_info "Версия Matrix Synapse: $SYNAPSE_VERSION"
}

main() {
    print_header "ОБНОВЛЕНИЕ MATRIX SYNAPSE И COTURN"
    
    read -p "Выберите действие (1 - Обновить Synapse, 2 - Обновить Coturn, 3 - Обновить SSL, 4 - Все, 5 - Статус): " ACTION
    
    case $ACTION in
        1)
            update_synapse
            ;;
        2)
            update_coturn
            ;;
        3)
            update_ssl_certificates
            ;;
        4)
            update_synapse
            update_coturn
            update_ssl_certificates
            ;;
        5)
            show_status
            ;;
        *)
            print_error "Неверный выбор"
            exit 1
            ;;
    esac
    
    show_status
    print_success "Операция завершена!"
}

main "$@"
