#!/bin/bash

# Скрипт для отката установки Matrix Synapse

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
    print_warning "Файл конфигурации не найден, продолжаем с общими настройками"
fi

confirm_uninstall() {
    print_header "ПОДТВЕРЖДЕНИЕ УДАЛЕНИЯ"
    
    print_warning "ВНИМАНИЕ! Это действие удалит:"
    echo "- Matrix Synapse сервер и все данные"
    echo "- Базу данных PostgreSQL с пользователями и сообщениями"
    echo "- Coturn сервер"
    echo "- Конфигурации Nginx"
    echo "- SSL сертификаты"
    echo "- Все медиафайлы и загрузки"
    echo
    
    read -p "Вы уверены, что хотите удалить Matrix Synapse? (введите 'YES' для подтверждения): " CONFIRM
    
    if [ "$CONFIRM" != "YES" ]; then
        print_info "Удаление отменено"
        exit 0
    fi
    
    print_warning "Последний шанс! Удаление начнется через 10 секунд..."
    print_info "Нажмите Ctrl+C для отмены"
    sleep 10
}

backup_before_uninstall() {
    print_header "СОЗДАНИЕ РЕЗЕРВНОЙ КОПИИ ПЕРЕД УДАЛЕНИЕМ"
    
    BACKUP_DIR="./data/uninstall_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Бэкап базы данных
    if command -v sudo -u postgres psql &> /dev/null; then
        print_info "Создание дампа базы данных..."
        sudo -u postgres pg_dump synapse > "$BACKUP_DIR/synapse_final_backup.sql" 2>/dev/null || true
    fi
    
    # Бэкап конфигураций
    print_info "Сохранение конфигураций..."
    [ -d "/etc/synapse" ] && sudo cp -r /etc/synapse "$BACKUP_DIR/synapse_config" 2>/dev/null || true
    [ -f "/etc/turnserver.conf" ] && sudo cp /etc/turnserver.conf "$BACKUP_DIR/" 2>/dev/null || true
    
    # Бэкап SSL сертификатов
    if [ -n "$MATRIX_DOMAIN" ] && [ -d "/etc/letsencrypt/live/$MATRIX_DOMAIN" ]; then
        print_info "Сохранение SSL сертификатов..."
        sudo cp -r "/etc/letsencrypt/live/$MATRIX_DOMAIN" "$BACKUP_DIR/ssl_certificates" 2>/dev/null || true
    fi
    
    # Сохранение информации об установке
    cat > "$BACKUP_DIR/uninstall_info.txt" << EOF
Резервная копия перед удалением Matrix Synapse
==============================================

Дата удаления: $(date)
Сервер: ${MATRIX_DOMAIN:-"неизвестно"}
Имя сервера: ${SERVER_NAME:-"неизвестно"}

Сохраненные данные:
- База данных: synapse_final_backup.sql
- Конфигурация Synapse: synapse_config/
- Конфигурация Coturn: turnserver.conf
- SSL сертификаты: ssl_certificates/

Примечание: Медиафайлы не были скопированы из-за их размера.
Если нужно сохранить медиафайлы, скопируйте /var/lib/synapse/media отдельно.
EOF
    
    sudo chown -R $USER:$USER "$BACKUP_DIR" 2>/dev/null || true
    print_success "Резервная копия создана: $BACKUP_DIR"
}

stop_services() {
    print_header "ОСТАНОВКА СЕРВИСОВ"
    
    services=("matrix-synapse" "coturn" "nginx" "postgresql")
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet $service 2>/dev/null; then
            print_info "Остановка $service..."
            sudo systemctl stop $service 2>/dev/null || print_warning "Не удалось остановить $service"
        fi
        
        if sudo systemctl is-enabled --quiet $service 2>/dev/null; then
            print_info "Отключение автозапуска $service..."
            sudo systemctl disable $service 2>/dev/null || print_warning "Не удалось отключить автозапуск $service"
        fi
    done
    
    print_success "Сервисы остановлены"
}

remove_systemd_services() {
    print_header "УДАЛЕНИЕ SYSTEMD СЕРВИСОВ"
    
    systemd_files=(
        "/etc/systemd/system/matrix-synapse.service"
    )
    
    for file in "${systemd_files[@]}"; do
        if [ -f "$file" ]; then
            print_info "Удаление $file..."
            sudo rm "$file"
        fi
    done
    
    sudo systemctl daemon-reload
    print_success "Systemd сервисы удалены"
}

remove_matrix_synapse() {
    print_header "УДАЛЕНИЕ MATRIX SYNAPSE"
    
    # Удаление пользователя synapse
    if id "synapse" &>/dev/null; then
        print_info "Удаление пользователя synapse..."
        sudo userdel -r synapse 2>/dev/null || print_warning "Не удалось полностью удалить пользователя synapse"
    fi
    
    # Удаление директорий
    directories=(
        "/var/lib/synapse"
        "/var/log/synapse"
        "/etc/synapse"
    )
    
    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            print_info "Удаление директории $dir..."
            sudo rm -rf "$dir"
        fi
    done
    
    print_success "Matrix Synapse удален"
}

remove_database() {
    print_header "УДАЛЕНИЕ БАЗЫ ДАННЫХ"
    
    if command -v sudo -u postgres psql &> /dev/null; then
        print_info "Удаление базы данных synapse..."
        sudo -u postgres psql << EOF 2>/dev/null || true
DROP DATABASE IF EXISTS synapse;
DROP USER IF EXISTS synapse;
\q
EOF
        print_success "База данных удалена"
    else
        print_warning "PostgreSQL не найден или недоступен"
    fi
}

remove_coturn() {
    print_header "УДАЛЕНИЕ COTURN"
    
    # Удаление пакета
    if dpkg -l | grep -q coturn; then
        print_info "Удаление пакета coturn..."
        sudo apt remove --purge -y coturn 2>/dev/null || print_warning "Не удалось удалить coturn"
    fi
    
    # Удаление конфигурации
    if [ -f "/etc/turnserver.conf" ]; then
        print_info "Удаление конфигурации coturn..."
        sudo rm "/etc/turnserver.conf"
    fi
    
    print_success "Coturn удален"
}

remove_nginx_config() {
    print_header "УДАЛЕНИЕ КОНФИГУРАЦИИ NGINX"
    
    if [ -n "$MATRIX_DOMAIN" ]; then
        nginx_files=(
            "/etc/nginx/sites-available/$MATRIX_DOMAIN"
            "/etc/nginx/sites-enabled/$MATRIX_DOMAIN"
            "/etc/nginx/sites-available/temp-$MATRIX_DOMAIN"
        )
        
        for file in "${nginx_files[@]}"; do
            if [ -f "$file" ] || [ -L "$file" ]; then
                print_info "Удаление $file..."
                sudo rm "$file"
            fi
        done
        
        # Восстановление default сайта
        if [ -f "/etc/nginx/sites-available/default" ] && [ ! -L "/etc/nginx/sites-enabled/default" ]; then
            sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
        fi
        
        # Перезагрузка nginx если он запущен
        if sudo systemctl is-active --quiet nginx 2>/dev/null; then
            sudo systemctl reload nginx 2>/dev/null || print_warning "Не удалось перезагрузить nginx"
        fi
    fi
    
    print_success "Конфигурация Nginx очищена"
}

remove_ssl_certificates() {
    print_header "УДАЛЕНИЕ SSL СЕРТИФИКАТОВ"
    
    if [ -n "$MATRIX_DOMAIN" ] && [ -d "/etc/letsencrypt/live/$MATRIX_DOMAIN" ]; then
        read -p "Удалить SSL сертификаты для $MATRIX_DOMAIN? (y/N): " REMOVE_SSL
        
        if [[ "$REMOVE_SSL" =~ ^[Yy]$ ]]; then
            print_info "Удаление SSL сертификатов..."
            sudo certbot delete --cert-name "$MATRIX_DOMAIN" --non-interactive 2>/dev/null || print_warning "Не удалось удалить сертификаты через certbot"
            
            # Принудительное удаление
            [ -d "/etc/letsencrypt/live/$MATRIX_DOMAIN" ] && sudo rm -rf "/etc/letsencrypt/live/$MATRIX_DOMAIN"
            [ -d "/etc/letsencrypt/archive/$MATRIX_DOMAIN" ] && sudo rm -rf "/etc/letsencrypt/archive/$MATRIX_DOMAIN"
            [ -d "/etc/letsencrypt/renewal/$MATRIX_DOMAIN.conf" ] && sudo rm -f "/etc/letsencrypt/renewal/$MATRIX_DOMAIN.conf"
            
            print_success "SSL сертификаты удалены"
        else
            print_info "SSL сертификаты оставлены"
        fi
    else
        print_info "SSL сертификаты не найдены"
    fi
}

cleanup_firewall() {
    print_header "ОЧИСТКА ПРАВИЛ БРАНДМАУЭРА"
    
    read -p "Удалить правила брандмауэра для Matrix? (y/N): " CLEANUP_UFW
    
    if [[ "$CLEANUP_UFW" =~ ^[Yy]$ ]]; then
        print_info "Удаление правил брандмауэра..."
        
        # Удаление специфичных правил Matrix
        sudo ufw delete allow $HTTP_PORT/tcp 2>/dev/null || true
        sudo ufw delete allow $HTTPS_PORT/tcp 2>/dev/null || true
        sudo ufw delete allow $COTURN_PORT/tcp 2>/dev/null || true
        sudo ufw delete allow $COTURN_PORT/udp 2>/dev/null || true
        sudo ufw delete allow 5349/tcp 2>/dev/null || true
        sudo ufw delete allow 49152:65535/udp 2>/dev/null || true
        
        print_success "Правила брандмауэра удалены"
    else
        print_info "Правила брандмауэра оставлены"
    fi
}

remove_packages() {
    print_header "УДАЛЕНИЕ ДОПОЛНИТЕЛЬНЫХ ПАКЕТОВ"
    
    read -p "Удалить установленные пакеты Python и зависимости? (y/N): " REMOVE_PACKAGES
    
    if [[ "$REMOVE_PACKAGES" =~ ^[Yy]$ ]]; then
        print_info "Удаление Python пакетов..."
        
        # Список пакетов для удаления (осторожно, могут использоваться другими приложениями)
        packages_to_remove=(
            "build-essential"
            "libffi-dev"
            "libssl-dev"
            "libxml2-dev"
            "libxslt1-dev"
            "libjpeg-dev"
            "libpq-dev"
            "zlib1g-dev"
        )
        
        print_warning "Будут удалены пакеты разработки. Они могут использоваться другими приложениями!"
        read -p "Продолжить? (y/N): " CONFIRM_PACKAGES
        
        if [[ "$CONFIRM_PACKAGES" =~ ^[Yy]$ ]]; then
            for package in "${packages_to_remove[@]}"; do
                sudo apt remove -y "$package" 2>/dev/null || print_warning "Не удалось удалить $package"
            done
            
            sudo apt autoremove -y 2>/dev/null || true
            print_success "Пакеты удалены"
        fi
    else
        print_info "Пакеты оставлены"
    fi
}

cleanup_project_files() {
    print_header "ОЧИСТКА ФАЙЛОВ ПРОЕКТА"
    
    read -p "Удалить конфигурационные файлы проекта? (y/N): " CLEANUP_PROJECT
    
    if [[ "$CLEANUP_PROJECT" =~ ^[Yy]$ ]]; then
        print_info "Очистка файлов проекта..."
        
        # Удаление конфигурационных файлов (кроме бэкапов)
        [ -f "./configs/install_config.env" ] && rm "./configs/install_config.env"
        
        print_success "Файлы проекта очищены"
    else
        print_info "Файлы проекта оставлены"
    fi
}

show_final_info() {
    print_header "УДАЛЕНИЕ ЗАВЕРШЕНО"
    
    print_success "Matrix Synapse полностью удален с сервера"
    echo
    print_info "Что было удалено:"
    echo "- Matrix Synapse сервер и все компоненты"
    echo "- База данных PostgreSQL (synapse)"
    echo "- Coturn TURN/STUN сервер"
    echo "- Конфигурации Nginx для Matrix"
    echo "- Systemd сервисы"
    echo "- Пользователь системы synapse"
    echo
    
    if [ -d "./data/uninstall_backup_"* ] 2>/dev/null; then
        echo "Резервная копия сохранена в:"
        ls -la ./data/ | grep uninstall_backup || true
        echo
    fi
    
    print_warning "Что НЕ было удалено автоматически:"
    echo "- PostgreSQL сервер (может использоваться другими приложениями)"
    echo "- Nginx (может использоваться другими сайтами)"
    echo "- Certbot и Let's Encrypt (могут использоваться для других сайтов)"
    echo
    
    print_info "Для полной очистки системы выполните вручную:"
    echo "sudo apt remove --purge postgresql postgresql-contrib"
    echo "sudo apt remove --purge nginx"
    echo "sudo apt remove --purge certbot python3-certbot-nginx"
    echo "sudo apt autoremove"
}

main() {
    print_header "УДАЛЕНИЕ MATRIX SYNAPSE И COTURN"
    
    # Проверка прав
    if [[ $EUID -eq 0 ]]; then
        print_error "Не запускайте скрипт от имени root!"
        exit 1
    fi
    
    confirm_uninstall
    backup_before_uninstall
    stop_services
    remove_systemd_services
    remove_matrix_synapse
    remove_database
    remove_coturn
    remove_nginx_config
    remove_ssl_certificates
    cleanup_firewall
    remove_packages
    cleanup_project_files
    show_final_info
    
    print_success "Процесс удаления завершен!"
}

main "$@"
