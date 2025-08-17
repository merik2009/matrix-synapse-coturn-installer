#!/bin/bash

# Скрипт для резервного копирования Matrix Synapse

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
    print_error "Файл конфигурации не найден!"
    exit 1
fi

# Создание директории для резервных копий
BACKUP_DIR="./data/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

backup_database() {
    print_header "РЕЗЕРВНОЕ КОПИРОВАНИЕ БАЗЫ ДАННЫХ"
    
    print_info "Создание дампа базы данных PostgreSQL..."
    sudo -u postgres pg_dump synapse > "$BACKUP_DIR/synapse_database.sql"
    
    # Сжатие дампа
    gzip "$BACKUP_DIR/synapse_database.sql"
    
    print_success "База данных сохранена в $BACKUP_DIR/synapse_database.sql.gz"
}

backup_configs() {
    print_header "РЕЗЕРВНОЕ КОПИРОВАНИЕ КОНФИГУРАЦИЙ"
    
    print_info "Копирование конфигурационных файлов..."
    
    # Конфигурация Synapse
    sudo cp -r /etc/synapse "$BACKUP_DIR/synapse_config"
    
    # Конфигурация Coturn
    sudo cp /etc/turnserver.conf "$BACKUP_DIR/turnserver.conf"
    
    # Конфигурация Nginx
    sudo cp -r /etc/nginx/sites-available "$BACKUP_DIR/nginx_sites"
    
    # SSL сертификаты
    if [ -d "/etc/letsencrypt/live/$MATRIX_DOMAIN" ]; then
        sudo cp -r "/etc/letsencrypt/live/$MATRIX_DOMAIN" "$BACKUP_DIR/ssl_certificates"
    fi
    
    # Ключи подписи
    if [ -f "/etc/synapse/homeserver.signing.key" ]; then
        sudo cp "/etc/synapse/homeserver.signing.key" "$BACKUP_DIR/"
    fi
    
    print_success "Конфигурации сохранены в $BACKUP_DIR/"
}

backup_media() {
    print_header "РЕЗЕРВНОЕ КОПИРОВАНИЕ МЕДИАФАЙЛОВ"
    
    print_info "Копирование медиафайлов (это может занять время)..."
    
    # Медиафайлы Synapse
    if [ -d "/var/lib/synapse/media" ]; then
        sudo tar -czf "$BACKUP_DIR/synapse_media.tar.gz" -C /var/lib/synapse media
        print_success "Медиафайлы сохранены в $BACKUP_DIR/synapse_media.tar.gz"
    else
        print_warning "Директория медиафайлов не найдена"
    fi
}

backup_logs() {
    print_header "РЕЗЕРВНОЕ КОПИРОВАНИЕ ЛОГОВ"
    
    print_info "Копирование логов..."
    
    # Логи Synapse
    if [ -d "/var/log/synapse" ]; then
        sudo tar -czf "$BACKUP_DIR/synapse_logs.tar.gz" -C /var/log synapse
    fi
    
    # Логи системы
    sudo journalctl -u matrix-synapse --since "7 days ago" > "$BACKUP_DIR/synapse_systemd.log"
    sudo journalctl -u coturn --since "7 days ago" > "$BACKUP_DIR/coturn_systemd.log"
    sudo journalctl -u nginx --since "7 days ago" > "$BACKUP_DIR/nginx_systemd.log"
    
    print_success "Логи сохранены в $BACKUP_DIR/"
}

create_backup_info() {
    print_header "СОЗДАНИЕ ИНФОРМАЦИИ О РЕЗЕРВНОЙ КОПИИ"
    
    cat > "$BACKUP_DIR/backup_info.txt" << EOF
Резервная копия Matrix Synapse
==============================

Дата создания: $(date)
Сервер: $MATRIX_DOMAIN
Имя сервера: $SERVER_NAME

Содержимое резервной копии:
- База данных PostgreSQL (synapse_database.sql.gz)
- Конфигурации Synapse (/etc/synapse -> synapse_config/)
- Конфигурация Coturn (turnserver.conf)
- Конфигурация Nginx (nginx_sites/)
- SSL сертификаты (ssl_certificates/)
- Ключи подписи (homeserver.signing.key)
- Медиафайлы (synapse_media.tar.gz)
- Логи (synapse_logs.tar.gz, *_systemd.log)

Информация о системе:
$(uname -a)

Версии ПО:
Matrix Synapse: $(sudo -u synapse /var/lib/synapse/venv/bin/python -c "import synapse; print(synapse.__version__)" 2>/dev/null || echo "Неизвестно")
PostgreSQL: $(sudo -u postgres psql --version 2>/dev/null || echo "Неизвестно")
Nginx: $(nginx -v 2>&1 || echo "Неизвестно")

Размер резервной копии:
$(du -sh "$BACKUP_DIR" 2>/dev/null || echo "Неизвестно")
EOF
    
    print_success "Информация о резервной копии сохранена"
}

cleanup_old_backups() {
    print_header "ОЧИСТКА СТАРЫХ РЕЗЕРВНЫХ КОПИЙ"
    
    # Удаление резервных копий старше 30 дней
    find ./data/backups -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    
    print_info "Старые резервные копии (>30 дней) удалены"
}

main() {
    print_header "СОЗДАНИЕ РЕЗЕРВНОЙ КОПИИ MATRIX SYNAPSE"
    
    print_info "Создание резервной копии в $BACKUP_DIR"
    
    backup_database
    backup_configs
    backup_media
    backup_logs
    create_backup_info
    cleanup_old_backups
    
    # Изменение владельца
    sudo chown -R $USER:$USER "$BACKUP_DIR"
    
    # Итоговая информация
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    print_success "Резервная копия создана успешно!"
    print_info "Местоположение: $BACKUP_DIR"
    print_info "Размер: $BACKUP_SIZE"
    
    # Предложение создать архив
    read -p "Создать единый архив резервной копии? (y/N): " CREATE_ARCHIVE
    if [[ "$CREATE_ARCHIVE" =~ ^[Yy]$ ]]; then
        ARCHIVE_NAME="./data/matrix_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$ARCHIVE_NAME" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
        ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" | cut -f1)
        print_success "Архив создан: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
    fi
}

main "$@"
