#!/bin/bash

# Скрипт для мониторинга Matrix Synapse

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
elif [ -f "../configs/install_config.env" ]; then
    source ../configs/install_config.env
    print_info "Конфигурация загружена"
else
    print_warning "Файл конфигурации не найден, используются значения по умолчанию"
    MATRIX_DOMAIN="localhost"
    SERVER_NAME="localhost" 
    HTTP_PORT=8008
    HTTPS_PORT=8448
    COTURN_PORT=3478
fi

check_services() {
    print_header "СТАТУС СЕРВИСОВ"
    
    services=("postgresql" "matrix-synapse" "coturn" "nginx")
    all_running=true
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet $service; then
            print_success "$service: запущен"
        else
            print_error "$service: остановлен"
            all_running=false
        fi
    done
    
    if $all_running; then
        print_success "Все сервисы работают корректно"
    else
        print_warning "Некоторые сервисы не запущены"
    fi
}

check_ports() {
    print_header "ПРОВЕРКА ПОРТОВ"
    
    ports=("80:nginx" "443:nginx" "$HTTP_PORT:synapse" "$HTTPS_PORT:synapse" "$COTURN_PORT:coturn" "5432:postgresql")
    
    for port_service in "${ports[@]}"; do
        port=$(echo $port_service | cut -d: -f1)
        service=$(echo $port_service | cut -d: -f2)
        
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            print_success "Порт $port ($service): открыт"
        else
            print_error "Порт $port ($service): закрыт"
        fi
    done
}

check_ssl() {
    print_header "ПРОВЕРКА SSL СЕРТИФИКАТОВ"
    
    if [ -f "/etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem" ]; then
        EXPIRE_DATE=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem" | cut -d= -f2)
        EXPIRE_TIMESTAMP=$(date -d "$EXPIRE_DATE" +%s)
        CURRENT_TIMESTAMP=$(date +%s)
        DAYS_UNTIL_EXPIRE=$(( ($EXPIRE_TIMESTAMP - $CURRENT_TIMESTAMP) / 86400 ))
        
        if [ $DAYS_UNTIL_EXPIRE -gt 30 ]; then
            print_success "SSL сертификат действителен ($DAYS_UNTIL_EXPIRE дней до истечения)"
        elif [ $DAYS_UNTIL_EXPIRE -gt 7 ]; then
            print_warning "SSL сертификат истекает через $DAYS_UNTIL_EXPIRE дней"
        else
            print_error "SSL сертификат истекает через $DAYS_UNTIL_EXPIRE дней - требуется обновление!"
        fi
    else
        print_error "SSL сертификат не найден"
    fi
}

check_database() {
    print_header "ПРОВЕРКА БАЗЫ ДАННЫХ"
    
    # Проверка подключения к БД
    if sudo -u postgres psql -d synapse -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "Подключение к базе данных: успешно"
        
        # Размер базы данных
        DB_SIZE=$(sudo -u postgres psql -d synapse -t -c "SELECT pg_size_pretty(pg_database_size('synapse'));" | xargs)
        print_info "Размер базы данных: $DB_SIZE"
        
        # Количество пользователей
        USER_COUNT=$(sudo -u postgres psql -d synapse -t -c "SELECT COUNT(*) FROM users;" | xargs)
        print_info "Количество пользователей: $USER_COUNT"
        
        # Количество комнат
        ROOM_COUNT=$(sudo -u postgres psql -d synapse -t -c "SELECT COUNT(*) FROM rooms;" | xargs)
        print_info "Количество комнат: $ROOM_COUNT"
        
    else
        print_error "Не удается подключиться к базе данных"
    fi
}

check_disk_space() {
    print_header "ПРОВЕРКА ДИСКОВОГО ПРОСТРАНСТВА"
    
    # Корневая файловая система
    ROOT_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $ROOT_USAGE -lt 80 ]; then
        print_success "Корневая ФС: ${ROOT_USAGE}% используется"
    elif [ $ROOT_USAGE -lt 90 ]; then
        print_warning "Корневая ФС: ${ROOT_USAGE}% используется"
    else
        print_error "Корневая ФС: ${ROOT_USAGE}% используется - мало места!"
    fi
    
    # Директория с медиафайлами
    if [ -d "/var/lib/synapse/media" ]; then
        MEDIA_SIZE=$(du -sh /var/lib/synapse/media 2>/dev/null | cut -f1)
        print_info "Размер медиафайлов: $MEDIA_SIZE"
    fi
    
    # Логи
    LOGS_SIZE=$(du -sh /var/log/synapse 2>/dev/null | cut -f1)
    print_info "Размер логов: $LOGS_SIZE"
}

check_memory() {
    print_header "ПРОВЕРКА ПАМЯТИ"
    
    # Общее использование памяти
    MEMORY_INFO=$(free -h | grep "Mem:")
    TOTAL_MEM=$(echo $MEMORY_INFO | awk '{print $2}')
    USED_MEM=$(echo $MEMORY_INFO | awk '{print $3}')
    FREE_MEM=$(echo $MEMORY_INFO | awk '{print $4}')
    
    print_info "Память: $USED_MEM / $TOTAL_MEM используется, $FREE_MEM свободно"
    
    # Использование памяти процессами Matrix
    if pgrep -f "synapse" >/dev/null; then
        SYNAPSE_MEM=$(ps -o pid,vsz,rss,comm -p $(pgrep -f "synapse") | tail -n +2 | awk '{sum+=$3} END {print sum/1024 " MB"}')
        print_info "Память Synapse: $SYNAPSE_MEM"
    fi
}

check_network() {
    print_header "ПРОВЕРКА СЕТЕВОГО ПОДКЛЮЧЕНИЯ"
    
    # Проверка доступности сервера
    if curl -s -o /dev/null -w "%{http_code}" "https://$MATRIX_DOMAIN" | grep -q "200\|403"; then
        print_success "HTTPS доступность: сервер доступен"
    else
        print_error "HTTPS доступность: сервер недоступен"
    fi
    
    # Проверка федерации
    if curl -s -o /dev/null -w "%{http_code}" "https://$MATRIX_DOMAIN:$HTTPS_PORT/_matrix/federation/v1/version" | grep -q "200"; then
        print_success "Федерация Matrix: работает"
    else
        print_error "Федерация Matrix: не работает"
    fi
    
    # Проверка well-known
    if curl -s "https://$MATRIX_DOMAIN/.well-known/matrix/server" | grep -q "m.server"; then
        print_success "Well-known сервер: настроен"
    else
        print_warning "Well-known сервер: не настроен или недоступен"
    fi
    
    if curl -s "https://$MATRIX_DOMAIN/.well-known/matrix/client" | grep -q "m.homeserver"; then
        print_success "Well-known клиент: настроен"
    else
        print_warning "Well-known клиент: не настроен или недоступен"
    fi
}

check_logs() {
    print_header "АНАЛИЗ ЛОГОВ"
    
    # Ошибки в логах Synapse за последний час
    ERROR_COUNT=$(sudo journalctl -u matrix-synapse --since "1 hour ago" | grep -i error | wc -l)
    if [ $ERROR_COUNT -eq 0 ]; then
        print_success "Ошибки в логах Synapse: не найдены за последний час"
    else
        print_warning "Ошибки в логах Synapse: $ERROR_COUNT за последний час"
    fi
    
    # Ошибки в логах Coturn
    COTURN_ERROR_COUNT=$(sudo journalctl -u coturn --since "1 hour ago" | grep -i error | wc -l)
    if [ $COTURN_ERROR_COUNT -eq 0 ]; then
        print_success "Ошибки в логах Coturn: не найдены за последний час"
    else
        print_warning "Ошибки в логах Coturn: $COTURN_ERROR_COUNT за последний час"
    fi
    
    # Ошибки в логах Nginx
    NGINX_ERROR_COUNT=$(sudo tail -n 100 /var/log/nginx/error.log 2>/dev/null | wc -l)
    if [ $NGINX_ERROR_COUNT -eq 0 ]; then
        print_success "Ошибки в логах Nginx: не найдены"
    else
        print_info "Записей в логе ошибок Nginx: $NGINX_ERROR_COUNT"
    fi
}

generate_report() {
    print_header "ГЕНЕРАЦИЯ ОТЧЕТА"
    
    REPORT_FILE="./data/monitoring_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Отчет мониторинга Matrix Synapse"
        echo "================================"
        echo "Дата: $(date)"
        echo "Сервер: $MATRIX_DOMAIN"
        echo ""
        
        echo "СТАТУС СЕРВИСОВ:"
        for service in "postgresql" "matrix-synapse" "coturn" "nginx"; do
            if sudo systemctl is-active --quiet $service; then
                echo "✓ $service: запущен"
            else
                echo "✗ $service: остановлен"
            fi
        done
        
        echo ""
        echo "ИСПОЛЬЗОВАНИЕ РЕСУРСОВ:"
        echo "Память: $(free -h | grep "Mem:" | awk '{print $3 "/" $2}')"
        echo "Диск /: $(df / | awk 'NR==2 {print $5}')"
        echo ""
        
        echo "БАЗА ДАННЫХ:"
        if sudo -u postgres psql -d synapse -c "SELECT 1;" >/dev/null 2>&1; then
            echo "Подключение: успешно"
            echo "Размер: $(sudo -u postgres psql -d synapse -t -c "SELECT pg_size_pretty(pg_database_size('synapse'));" | xargs)"
        else
            echo "Подключение: ошибка"
        fi
        
        echo ""
        echo "СЕТЬ:"
        if curl -s -o /dev/null -w "%{http_code}" "https://$MATRIX_DOMAIN" | grep -q "200\|403"; then
            echo "HTTPS: доступен"
        else
            echo "HTTPS: недоступен"
        fi
        
    } > "$REPORT_FILE"
    
    print_success "Отчет сохранен в: $REPORT_FILE"
}

show_dashboard() {
    clear
    print_header "ПАНЕЛЬ МОНИТОРИНГА MATRIX SYNAPSE"
    
    check_services
    check_ports
    check_ssl
    check_database
    check_disk_space
    check_memory
    check_network
    check_logs
    
    echo ""
    print_info "Обновление каждые 30 секунд. Нажмите Ctrl+C для выхода."
    sleep 30
}

main() {
    case "${1:-dashboard}" in
        "dashboard")
            while true; do
                show_dashboard
            done
            ;;
        "report")
            check_services
            check_ports
            check_ssl
            check_database
            check_disk_space
            check_memory
            check_network
            check_logs
            generate_report
            ;;
        "services")
            check_services
            ;;
        "network")
            check_network
            ;;
        "database")
            check_database
            ;;
        *)
            echo "Использование: $0 [dashboard|report|services|network|database]"
            echo "  dashboard - интерактивная панель мониторинга"
            echo "  report    - создание отчета"
            echo "  services  - проверка сервисов"
            echo "  network   - проверка сети"
            echo "  database  - проверка базы данных"
            ;;
    esac
}

main "$@"
