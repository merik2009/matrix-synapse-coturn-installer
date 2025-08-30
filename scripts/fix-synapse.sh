#!/bin/bash

# Скрипт для исправления проблем с Matrix Synapse

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

# Исправление проблемы с pkg_resources
fix_pkg_resources() {
    print_header "ИСПРАВЛЕНИЕ ПРОБЛЕМЫ PKG_RESOURCES"
    
    print_info "Обновление setuptools в виртуальном окружении Synapse..."
    
    # Остановка Synapse
    if sudo systemctl is-active --quiet matrix-synapse; then
        print_info "Остановка Matrix Synapse..."
        sudo systemctl stop matrix-synapse
    fi
    
    # Обновление setuptools
    sudo -u synapse /var/lib/synapse/venv/bin/pip install --upgrade "setuptools<81"
    
    # Также обновим pip и wheel
    sudo -u synapse /var/lib/synapse/venv/bin/pip install --upgrade pip wheel
    
    print_success "Setuptools обновлен"
}

# Исправление прав доступа
fix_permissions() {
    print_header "ИСПРАВЛЕНИЕ ПРАВ ДОСТУПА"
    
    # Проверка и исправление прав на конфигурационные файлы
    if [[ -d "/etc/synapse" ]]; then
        print_info "Исправление прав на /etc/synapse..."
        sudo chown -R synapse:synapse /etc/synapse
        sudo chmod 755 /etc/synapse
        
        if [[ -f "/etc/synapse/homeserver.yaml" ]]; then
            sudo chmod 644 /etc/synapse/homeserver.yaml
        fi
        
        if [[ -f "/etc/synapse/homeserver.signing.key" ]]; then
            sudo chmod 600 /etc/synapse/homeserver.signing.key
            sudo chown synapse:synapse /etc/synapse/homeserver.signing.key
        fi
    fi
    
    # Исправление прав на директории данных
    if [[ -d "/var/lib/synapse" ]]; then
        print_info "Исправление прав на /var/lib/synapse..."
        sudo chown -R synapse:synapse /var/lib/synapse
    fi
    
    # Исправление прав на логи
    if [[ -d "/var/log/synapse" ]]; then
        print_info "Исправление прав на /var/log/synapse..."
        sudo chown -R synapse:synapse /var/log/synapse
    fi
    
    print_success "Права доступа исправлены"
}

# Генерация отсутствующего ключа подписи
generate_signing_key() {
    print_header "ПРОВЕРКА КЛЮЧА ПОДПИСИ"
    
    if [[ ! -f "/etc/synapse/homeserver.signing.key" ]]; then
        print_info "Генерация отсутствующего ключа подписи..."
        
        # Создание ключа с помощью Synapse
        sudo -u synapse /var/lib/synapse/venv/bin/python -c "
from synapse.config.key import KeyConfig
import tempfile
import os
import shutil

# Создаем временную директорию
temp_dir = tempfile.mkdtemp()
key_path = os.path.join(temp_dir, 'signing.key')

try:
    # Генерируем ключ
    key_config = KeyConfig()
    key_config.generate_files({'signing_key_path': key_path}, {})
    
    # Копируем ключ в нужное место
    shutil.copy2(key_path, '/etc/synapse/homeserver.signing.key')
    print('Ключ подписи успешно сгенерирован')
    
except Exception as e:
    print(f'Ошибка генерации ключа: {e}')
    exit(1)
finally:
    # Очищаем временную директорию
    shutil.rmtree(temp_dir, ignore_errors=True)
"
        
        # Установка правильных прав
        sudo chown synapse:synapse /etc/synapse/homeserver.signing.key
        sudo chmod 600 /etc/synapse/homeserver.signing.key
        
        print_success "Ключ подписи создан"
    else
        print_success "Ключ подписи существует"
    fi
}

# Проверка конфигурации
check_config() {
    print_header "ПРОВЕРКА КОНФИГУРАЦИИ"
    
    if [[ -f "/etc/synapse/homeserver.yaml" ]]; then
        print_info "Проверка синтаксиса конфигурации..."
        
        if sudo -u synapse /var/lib/synapse/venv/bin/python -m synapse.config.homeserver -c /etc/synapse/homeserver.yaml --generate-keys; then
            print_success "Конфигурация корректна"
        else
            print_error "Ошибка в конфигурации Synapse"
            return 1
        fi
    else
        print_error "Файл конфигурации не найден: /etc/synapse/homeserver.yaml"
        return 1
    fi
}

# Запуск сервисов
start_services() {
    print_header "ЗАПУСК СЕРВИСОВ"
    
    # Запуск PostgreSQL
    if ! sudo systemctl is-active --quiet postgresql; then
        print_info "Запуск PostgreSQL..."
        sudo systemctl start postgresql
    fi
    
    # Запуск Matrix Synapse
    print_info "Запуск Matrix Synapse..."
    sudo systemctl start matrix-synapse
    
    # Проверка статуса
    sleep 5
    if sudo systemctl is-active --quiet matrix-synapse; then
        print_success "Matrix Synapse успешно запущен"
    else
        print_error "Ошибка запуска Matrix Synapse"
        print_info "Проверьте логи: sudo journalctl -u matrix-synapse -f"
        return 1
    fi
}

# Показать статус
show_status() {
    print_header "СТАТУС СЕРВИСОВ"
    
    services=("postgresql" "matrix-synapse" "coturn" "nginx")
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet $service 2>/dev/null; then
            print_success "$service: запущен"
        else
            print_error "$service: остановлен"
        fi
    done
}

# Главная функция
main() {
    case "${1:-fix}" in
        "fix")
            fix_pkg_resources
            fix_permissions
            generate_signing_key
            check_config
            start_services
            show_status
            ;;
        "permissions")
            fix_permissions
            ;;
        "key")
            generate_signing_key
            ;;
        "check")
            check_config
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Использование: $0 [fix|permissions|key|check|status]"
            echo "  fix         - исправить все проблемы (по умолчанию)"
            echo "  permissions - исправить права доступа"
            echo "  key         - создать ключ подписи"
            echo "  check       - проверить конфигурацию"
            echo "  status      - показать статус сервисов"
            ;;
    esac
}

main "$@"
