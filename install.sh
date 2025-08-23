#!/bin/bash

# Matrix Synapse и Coturn - Интерактивный скрипт установки
# Автор: Скрипт для автоматической установки и настройки
# Дата: $(date)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логирование
LOG_FILE="./install.log"
exec > >(tee -a ${LOG_FILE})
exec 2>&1

# Функция для красивого вывода
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

# Проверка прав суперпользователя
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Не запускайте скрипт от имени root! Используйте sudo при необходимости."
        exit 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ"
    
    local missing_deps=()
    
    # Проверка основных команд
    local required_commands=("curl" "wget" "openssl" "bc")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Проверка доступности интернета
    if ! curl -s --connect-timeout 5 --max-time 10 google.com > /dev/null; then
        print_error "Нет подключения к интернету!"
        exit 1
    fi
    
    # Установка отсутствующих зависимостей
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_info "Установка отсутствующих зависимостей: ${missing_deps[*]}"
        sudo apt update
        sudo apt install -y "${missing_deps[@]}"
    fi
    
    print_success "Все зависимости проверены"
}

# Получение внешнего IP адреса
get_external_ip() {
    local ip=""
    local services=("ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "ident.me")
    
    for service in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '\n\r' | head -c 15)
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    # Если не удалось получить внешний IP, используем локальный
    ip=$(hostname -I | awk '{print $1}')
    if [[ -n "$ip" ]]; then
        print_warning "Не удалось получить внешний IP, используется локальный: $ip"
        echo "$ip"
        return 0
    fi
    
    print_error "Не удалось определить IP адрес сервера"
    return 1
}

# Проверка операционной системы
check_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$NAME
            VER=$VERSION_ID
            
            # Проверка поддерживаемых дистрибутивов
            case "$ID" in
                ubuntu)
                    if [[ $(echo "$VERSION_ID >= 20.04" | bc -l) -eq 1 ]]; then
                        print_info "Обнаружена ОС: $OS $VER (поддерживается)"
                    else
                        print_error "Требуется Ubuntu 20.04 или новее. Обнаружена: $OS $VER"
                        exit 1
                    fi
                    ;;
                debian)
                    if [[ $(echo "$VERSION_ID >= 11" | bc -l) -eq 1 ]]; then
                        print_info "Обнаружена ОС: $OS $VER (поддерживается)"
                    else
                        print_error "Требуется Debian 11 или новее. Обнаружена: $OS $VER"
                        exit 1
                    fi
                    ;;
                *)
                    print_warning "Дистрибутив $OS может не поддерживаться. Продолжение на ваш риск."
                    read -p "Продолжить? (y/N): " CONTINUE
                    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
                        exit 1
                    fi
                    ;;
            esac
        else
            print_error "Невозможно определить операционную систему"
            exit 1
        fi
    else
        print_error "Скрипт поддерживает только Linux системы"
        exit 1
    fi
}

# Интерактивный сбор данных
collect_user_data() {
    print_header "СБОР КОНФИГУРАЦИОННЫХ ДАННЫХ"
    
    # Домен сервера
    read -p "Введите домен для Matrix сервера (например, matrix.example.com): " MATRIX_DOMAIN
    while [[ -z "$MATRIX_DOMAIN" ]]; do
        print_warning "Домен не может быть пустым!"
        read -p "Введите домен для Matrix сервера: " MATRIX_DOMAIN
    done
    
    # Имя сервера
    read -p "Введите имя сервера (например, example.com): " SERVER_NAME
    while [[ -z "$SERVER_NAME" ]]; do
        print_warning "Имя сервера не может быть пустым!"
        read -p "Введите имя сервера: " SERVER_NAME
    done
    
    # Email для SSL сертификатов
    read -p "Введите email для Let's Encrypt сертификатов: " LETSENCRYPT_EMAIL
    while [[ -z "$LETSENCRYPT_EMAIL" ]] || [[ ! "$LETSENCRYPT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; do
        if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
            print_warning "Email не может быть пустым!"
        else
            print_warning "Введите корректный email адрес!"
        fi
        read -p "Введите email для Let's Encrypt: " LETSENCRYPT_EMAIL
    done
    
    # Пароль для базы данных
    read -s -p "Введите пароль для базы данных PostgreSQL (минимум 8 символов): " DB_PASSWORD
    echo
    while [[ -z "$DB_PASSWORD" ]] || [[ ${#DB_PASSWORD} -lt 8 ]]; do
        if [[ -z "$DB_PASSWORD" ]]; then
            print_warning "Пароль не может быть пустым!"
        else
            print_warning "Пароль должен содержать минимум 8 символов!"
        fi
        read -s -p "Введите пароль для базы данных (минимум 8 символов): " DB_PASSWORD
        echo
    done
    
    # Секретный ключ для Coturn
    read -s -p "Введите секретный ключ для Coturn (можно оставить пустым для автогенерации): " COTURN_SECRET
    echo
    if [[ -z "$COTURN_SECRET" ]]; then
        COTURN_SECRET=$(openssl rand -base64 32)
        print_info "Сгенерирован секретный ключ для Coturn"
    fi
    
    # Порты
    read -p "Введите HTTP порт для Matrix (по умолчанию 8008): " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-8008}
    
    read -p "Введите HTTPS порт для Matrix (по умолчанию 8448): " HTTPS_PORT
    HTTPS_PORT=${HTTPS_PORT:-8448}
    
    read -p "Введите порт для Coturn STUN/TURN (по умолчанию 3478): " COTURN_PORT
    COTURN_PORT=${COTURN_PORT:-3478}
    
    # Подтверждение данных
    print_header "ПОДТВЕРЖДЕНИЕ КОНФИГУРАЦИИ"
    echo "Домен Matrix: $MATRIX_DOMAIN"
    echo "Имя сервера: $SERVER_NAME"
    echo "Email: $LETSENCRYPT_EMAIL"
    echo "HTTP порт: $HTTP_PORT"
    echo "HTTPS порт: $HTTPS_PORT"
    echo "Coturn порт: $COTURN_PORT"
    echo
    
    read -p "Продолжить установку с этими параметрами? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Установка отменена пользователем"
        exit 0
    fi
}

# Сохранение конфигурации
save_config() {
    cat > ./configs/install_config.env << EOF
# Конфигурация Matrix Synapse и Coturn
MATRIX_DOMAIN=$MATRIX_DOMAIN
SERVER_NAME=$SERVER_NAME
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
DB_PASSWORD=$DB_PASSWORD
COTURN_SECRET=$COTURN_SECRET
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT
COTURN_PORT=$COTURN_PORT
INSTALL_DATE=$(date)
EOF
    print_success "Конфигурация сохранена в ./configs/install_config.env"
}

# Установка зависимостей
install_dependencies() {
    print_header "УСТАНОВКА ЗАВИСИМОСТЕЙ"
    
    # Обновление системы
    print_info "Обновление списка пакетов..."
    sudo apt update
    
    # Установка базовых пакетов
    print_info "Установка базовых пакетов..."
    
    # Проверка доступности пакетов
    if ! apt-cache search curl | grep -q "^curl "; then
        print_error "Пакет curl недоступен в репозиториях"
        exit 1
    fi
    
    sudo apt install -y \
        curl \
        wget \
        gnupg2 \
        lsb-release \
        ca-certificates \
        software-properties-common \
        apt-transport-https \
        ufw \
        fail2ban \
        nginx \
        certbot \
        python3-certbot-nginx \
        postgresql \
        postgresql-contrib \
        python3 \
        python3-pip \
        python3-venv \
        build-essential \
        libffi-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg-dev \
        libpq-dev \
        zlib1g-dev \
        bc
    
    print_success "Базовые зависимости установлены"
}

# Установка Docker
install_docker() {
    print_header "УСТАНОВКА DOCKER"
    
    if command -v docker &> /dev/null; then
        print_info "Docker уже установлен"
        return
    fi
    
    # Добавление репозитория Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Установка Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Добавление пользователя в группу docker
    sudo usermod -aG docker $USER
    
    print_success "Docker установлен"
}

# Настройка PostgreSQL
setup_postgresql() {
    print_header "НАСТРОЙКА POSTGRESQL"
    
    # Запуск и включение PostgreSQL
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    # Создание базы данных и пользователя
    sudo -u postgres psql << EOF
CREATE USER synapse WITH PASSWORD '$DB_PASSWORD';
CREATE DATABASE synapse
  ENCODING 'UTF8'
  LC_COLLATE 'C'
  LC_CTYPE 'C'
  TEMPLATE template0
  OWNER synapse;
\q
EOF
    
    print_success "PostgreSQL настроен"
}

# Установка Matrix Synapse
install_synapse() {
    print_header "УСТАНОВКА MATRIX SYNAPSE"
    
    # Создание пользователя synapse
    sudo adduser --system --group --home /var/lib/synapse synapse
    
    # Создание виртуального окружения
    sudo -u synapse python3 -m venv /var/lib/synapse/venv
    
    # Установка Synapse
    sudo -u synapse /var/lib/synapse/venv/bin/pip install --upgrade pip
    sudo -u synapse /var/lib/synapse/venv/bin/pip install matrix-synapse[postgres]
    
    # Создание директорий
    sudo mkdir -p /etc/synapse
    sudo mkdir -p /var/log/synapse
    sudo mkdir -p /var/lib/synapse/media
    sudo chown -R synapse:synapse /var/lib/synapse
    sudo chown -R synapse:synapse /var/log/synapse
    
    print_success "Matrix Synapse установлен"
}

# Генерация конфигурации Synapse
generate_synapse_config() {
    print_header "ГЕНЕРАЦИЯ КОНФИГУРАЦИИ SYNAPSE"
    
    # Генерация конфигурации
    sudo -u synapse /var/lib/synapse/venv/bin/python -m synapse.app.homeserver \
        --server-name $SERVER_NAME \
        --config-path /etc/synapse/homeserver.yaml \
        --generate-config \
        --report-stats=no
    
    # Создание конфигурационного файла
    sudo tee /etc/synapse/homeserver.yaml > /dev/null << EOF
server_name: "$SERVER_NAME"
pid_file: /var/lib/synapse/homeserver.pid
web_client_location: https://app.element.io/

listeners:
  - port: $HTTP_PORT
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1']
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: synapse
    password: $DB_PASSWORD
    database: synapse
    host: localhost
    port: 5432
    cp_min: 5
    cp_max: 10

log_config: "/etc/synapse/log.config"

media_store_path: "/var/lib/synapse/media"
uploads_path: "/var/lib/synapse/uploads"

max_upload_size: 50M
max_image_pixels: 32M

url_preview_enabled: true
url_preview_ip_range_blacklist:
  - '127.0.0.0/8'
  - '10.0.0.0/8'
  - '172.16.0.0/12'
  - '192.168.0.0/16'
  - '100.64.0.0/10'
  - '169.254.0.0/16'
  - '::1/128'
  - 'fe80::/64'
  - 'fc00::/7'

enable_registration: true
enable_registration_without_verification: false

registrations_require_3pid:
  - email

allowed_local_3pids:
  - medium: email
    pattern: '.*'

registration_shared_secret: "$(openssl rand -base64 32)"

macaroon_secret_key: "$(openssl rand -base64 32)"
form_secret: "$(openssl rand -base64 32)"

signing_key_path: "/etc/synapse/homeserver.signing.key"

trusted_key_servers:
  - server_name: "matrix.org"

turn_uris:
  - "turn:$MATRIX_DOMAIN:$COTURN_PORT?transport=udp"
  - "turn:$MATRIX_DOMAIN:$COTURN_PORT?transport=tcp"
  - "turns:$MATRIX_DOMAIN:5349?transport=tcp"

turn_shared_secret: "$COTURN_SECRET"
turn_user_lifetime: 86400000

suppress_key_server_warning: true
EOF

    # Создание конфигурации логирования
    sudo tee /etc/synapse/log.config > /dev/null << EOF
version: 1

formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'

handlers:
  file:
    class: logging.handlers.TimedRotatingFileHandler
    formatter: precise
    filename: /var/log/synapse/homeserver.log
    when: midnight
    backupCount: 3  # Does not include the current log file.
    encoding: utf8

  console:
    class: logging.StreamHandler
    formatter: precise

loggers:
  synapse.storage.SQL:
    level: INFO

root:
    level: INFO
    handlers: [file, console]

disable_existing_loggers: false
EOF

    sudo chown -R synapse:synapse /etc/synapse
    print_success "Конфигурация Synapse сгенерирована"
}

# Установка и настройка Coturn
install_coturn() {
    print_header "УСТАНОВКА И НАСТРОЙКА COTURN"
    
    # Установка Coturn
    sudo apt install -y coturn
    
    # Получение внешнего IP
    EXTERNAL_IP=$(get_external_ip)
    if [[ $? -ne 0 ]]; then
        print_error "Не удалось получить IP адрес для Coturn"
        exit 1
    fi
    
    print_info "Используется IP адрес: $EXTERNAL_IP"
    
    # Настройка Coturn
    sudo tee /etc/turnserver.conf > /dev/null << EOF
use-auth-secret
static-auth-secret=$COTURN_SECRET
realm=$MATRIX_DOMAIN
min-port=49152
max-port=65535
verbose
fingerprint
lt-cred-mech
external-ip=$EXTERNAL_IP
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
allowed-peer-ip=$EXTERNAL_IP
user-quota=12
total-quota=1200
cert=/etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem
pkey=/etc/letsencrypt/live/$MATRIX_DOMAIN/privkey.pem
EOF
    
    # Включение и запуск Coturn
    sudo systemctl enable coturn
    
    print_success "Coturn установлен и настроен"
}

# Настройка Nginx
setup_nginx() {
    print_header "НАСТРОЙКА NGINX"
    
    # Создание конфигурации для Matrix
    sudo tee /etc/nginx/sites-available/$MATRIX_DOMAIN > /dev/null << EOF
server {
    listen 80;
    server_name $MATRIX_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $MATRIX_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MATRIX_DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$MATRIX_DOMAIN/chain.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;

    location /.well-known/matrix/server {
        return 200 '{"m.server": "$MATRIX_DOMAIN:$HTTPS_PORT"}';
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
    }

    location /.well-known/matrix/client {
        return 200 '{"m.homeserver": {"base_url": "https://$MATRIX_DOMAIN"}}';
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
    }

    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://127.0.0.1:$HTTP_PORT;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 50M;
    }
}

server {
    listen $HTTPS_PORT ssl http2;
    listen [::]:$HTTPS_PORT ssl http2;
    server_name $MATRIX_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MATRIX_DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$HTTP_PORT;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 50M;
    }
}
EOF

    # Активация сайта
    sudo ln -sf /etc/nginx/sites-available/$MATRIX_DOMAIN /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Проверка конфигурации
    sudo nginx -t
    
    print_success "Nginx настроен"
}

# Получение SSL сертификатов
setup_ssl() {
    print_header "ПОЛУЧЕНИЕ SSL СЕРТИФИКАТОВ"
    
    # Временный Nginx конфиг для получения сертификата
    sudo tee /etc/nginx/sites-available/temp-$MATRIX_DOMAIN > /dev/null << EOF
server {
    listen 80;
    server_name $MATRIX_DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
    
    sudo ln -sf /etc/nginx/sites-available/temp-$MATRIX_DOMAIN /etc/nginx/sites-enabled/
    sudo systemctl reload nginx
    
    # Получение сертификата
    sudo certbot certonly --webroot -w /var/www/html -d $MATRIX_DOMAIN --email $LETSENCRYPT_EMAIL --agree-tos --non-interactive
    
    # Возврат к основной конфигурации
    sudo rm /etc/nginx/sites-enabled/temp-$MATRIX_DOMAIN
    sudo ln -sf /etc/nginx/sites-available/$MATRIX_DOMAIN /etc/nginx/sites-enabled/
    sudo systemctl reload nginx
    
    print_success "SSL сертификаты получены"
}

# Создание systemd сервисов
create_systemd_services() {
    print_header "СОЗДАНИЕ SYSTEMD СЕРВИСОВ"
    
    # Сервис для Matrix Synapse
    sudo tee /etc/systemd/system/matrix-synapse.service > /dev/null << EOF
[Unit]
Description=Matrix Synapse
After=network.target postgresql.service

[Service]
Type=exec
User=synapse
Group=synapse
WorkingDirectory=/var/lib/synapse
ExecStart=/var/lib/synapse/venv/bin/python -m synapse.app.homeserver --config-path=/etc/synapse/homeserver.yaml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
SyslogIdentifier=matrix-synapse

[Install]
WantedBy=multi-user.target
EOF
    
    # Перезагрузка systemd и включение сервисов
    sudo systemctl daemon-reload
    sudo systemctl enable matrix-synapse
    sudo systemctl enable nginx
    sudo systemctl enable postgresql
    
    print_success "Systemd сервисы созданы"
}

# Настройка брандмауэра
setup_firewall() {
    print_header "НАСТРОЙКА БРАНДМАУЭРА"
    
    # Основные правила UFW
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Разрешение необходимых портов
    sudo ufw allow ssh
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow $HTTPS_PORT/tcp
    sudo ufw allow $COTURN_PORT/tcp
    sudo ufw allow $COTURN_PORT/udp
    sudo ufw allow 5349/tcp  # TURNS
    sudo ufw allow 49152:65535/udp  # RTC порты
    
    # Включение UFW
    sudo ufw --force enable
    
    print_success "Брандмауэр настроен"
}

# Запуск сервисов
start_services() {
    print_header "ЗАПУСК СЕРВИСОВ"
    
    # Запуск PostgreSQL
    sudo systemctl start postgresql
    print_success "PostgreSQL запущен"
    
    # Запуск Matrix Synapse
    sudo systemctl start matrix-synapse
    print_success "Matrix Synapse запущен"
    
    # Запуск Coturn
    sudo systemctl start coturn
    print_success "Coturn запущен"
    
    # Перезапуск Nginx
    sudo systemctl restart nginx
    print_success "Nginx перезапущен"
}

# Создание администратора
create_admin_user() {
    print_header "СОЗДАНИЕ АДМИНИСТРАТОРА"
    
    read -p "Введите имя пользователя администратора: " ADMIN_USER
    while [[ -z "$ADMIN_USER" ]]; do
        print_warning "Имя пользователя не может быть пустым!"
        read -p "Введите имя пользователя администратора: " ADMIN_USER
    done
    
    read -s -p "Введите пароль для администратора: " ADMIN_PASSWORD
    echo
    while [[ -z "$ADMIN_PASSWORD" ]]; do
        print_warning "Пароль не может быть пустым!"
        read -s -p "Введите пароль для администратора: " ADMIN_PASSWORD
        echo
    done
    
    # Создание администратора
    sudo -u synapse /var/lib/synapse/venv/bin/register_new_matrix_user \
        -c /etc/synapse/homeserver.yaml \
        -u $ADMIN_USER \
        -p $ADMIN_PASSWORD \
        -a
    
    print_success "Администратор создан: @$ADMIN_USER:$SERVER_NAME"
}

# Проверка статуса сервисов
check_services() {
    print_header "ПРОВЕРКА СТАТУСА СЕРВИСОВ"
    
    services=("postgresql" "matrix-synapse" "coturn" "nginx")
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet $service; then
            print_success "$service: активен"
        else
            print_error "$service: неактивен"
        fi
    done
}

# Вывод итоговой информации
show_final_info() {
    print_header "УСТАНОВКА ЗАВЕРШЕНА"
    
    echo -e "${GREEN}Matrix Synapse сервер успешно установлен и настроен!${NC}"
    echo
    echo "Информация о сервере:"
    echo "- Домен сервера: https://$MATRIX_DOMAIN"
    echo "- Имя сервера: $SERVER_NAME"
    echo "- Федерация: https://$MATRIX_DOMAIN:$HTTPS_PORT"
    echo "- Coturn сервер: $MATRIX_DOMAIN:$COTURN_PORT"
    echo
    echo "Рекомендуемые клиенты:"
    echo "- Element Web: https://app.element.io"
    echo "- Element Desktop: https://element.io/get-started"
    echo "- Element Mobile: доступен в App Store/Google Play"
    echo
    echo "Настройки клиента:"
    echo "- Homeserver: https://$MATRIX_DOMAIN"
    echo "- Пользователь: @$ADMIN_USER:$SERVER_NAME"
    echo
    echo "Полезные команды:"
    echo "- Просмотр логов Synapse: sudo journalctl -u matrix-synapse -f"
    echo "- Просмотр логов Coturn: sudo journalctl -u coturn -f"
    echo "- Просмотр логов Nginx: sudo tail -f /var/log/nginx/error.log"
    echo "- Статус сервисов: sudo systemctl status matrix-synapse coturn nginx"
    echo
    echo "Конфигурационные файлы сохранены в: ./configs/"
    echo "Логи установки сохранены в: $LOG_FILE"
    
    print_warning "Не забудьте настроить DNS записи для домена $MATRIX_DOMAIN!"
    print_warning "A запись должна указывать на IP адрес этого сервера"
}

# Главная функция
main() {
    print_header "MATRIX SYNAPSE И COTURN - АВТОМАТИЧЕСКАЯ УСТАНОВКА"
    
    # Проверки
    check_root
    check_dependencies
    check_os
    
    # Сбор данных
    collect_user_data
    save_config
    
    # Установка и настройка
    install_dependencies
    install_docker
    setup_postgresql
    install_synapse
    generate_synapse_config
    install_coturn
    setup_nginx
    setup_ssl
    create_systemd_services
    setup_firewall
    start_services
    create_admin_user
    
    # Финальные проверки
    check_services
    show_final_info
    
    print_success "Установка завершена успешно!"
}

# Обработка ошибок
trap 'print_error "Произошла ошибка на строке $LINENO. Проверьте логи для подробностей."; exit 1' ERR

# Запуск основной функции
main "$@"
