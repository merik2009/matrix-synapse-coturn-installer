#!/bin/bash

# Docker версия скрипта установки Matrix Synapse

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

collect_docker_config() {
    print_header "СБОР КОНФИГУРАЦИИ ДЛЯ DOCKER"
    
    # Загрузка существующей конфигурации если есть
    if [ -f "./configs/install_config.env" ]; then
        source ./configs/install_config.env
        print_info "Загружена существующая конфигурация"
    fi
    
    # Домен сервера
    read -p "Введите домен для Matrix сервера [$MATRIX_DOMAIN]: " NEW_DOMAIN
    MATRIX_DOMAIN=${NEW_DOMAIN:-$MATRIX_DOMAIN}
    
    # Имя сервера
    read -p "Введите имя сервера [$SERVER_NAME]: " NEW_SERVER
    SERVER_NAME=${NEW_SERVER:-$SERVER_NAME}
    
    # Пароль для базы данных
    if [ -z "$DB_PASSWORD" ]; then
        read -s -p "Введите пароль для базы данных PostgreSQL: " DB_PASSWORD
        echo
    fi
    
    # Секретный ключ для Coturn
    if [ -z "$COTURN_SECRET" ]; then
        COTURN_SECRET=$(openssl rand -base64 32)
    fi
    
    # Порты
    HTTP_PORT=${HTTP_PORT:-8008}
    HTTPS_PORT=${HTTPS_PORT:-8448}
    COTURN_PORT=${COTURN_PORT:-3478}
    
    # Создание .env файла для Docker Compose
    cat > ./docker/.env << EOF
# Matrix Synapse Docker Configuration
MATRIX_DOMAIN=$MATRIX_DOMAIN
SERVER_NAME=$SERVER_NAME
DB_PASSWORD=$DB_PASSWORD
COTURN_SECRET=$COTURN_SECRET
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT
COTURN_PORT=$COTURN_PORT
COMPOSE_PROJECT_NAME=matrix-synapse
EOF
    
    print_success "Конфигурация Docker сохранена"
}

generate_docker_configs() {
    print_header "ГЕНЕРАЦИЯ КОНФИГУРАЦИОННЫХ ФАЙЛОВ"
    
    # Конфигурация Synapse для Docker
    cat > ./configs/homeserver.yaml << EOF
server_name: "$SERVER_NAME"
pid_file: /data/homeserver.pid
web_client_location: https://app.element.io/

listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['0.0.0.0']
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: synapse
    password: $DB_PASSWORD
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10

log_config: "/data/log.config"

media_store_path: "/data/media"
uploads_path: "/data/uploads"

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

registration_shared_secret: "$(openssl rand -base64 32)"
macaroon_secret_key: "$(openssl rand -base64 32)"
form_secret: "$(openssl rand -base64 32)"

signing_key_path: "/data/homeserver.signing.key"

trusted_key_servers:
  - server_name: "matrix.org"

turn_uris:
  - "turn:$MATRIX_DOMAIN:$COTURN_PORT?transport=udp"
  - "turn:$MATRIX_DOMAIN:$COTURN_PORT?transport=tcp"
  - "turns:$MATRIX_DOMAIN:5349?transport=tcp"

turn_shared_secret: "$COTURN_SECRET"
turn_user_lifetime: 86400000

suppress_key_server_warning: true

# Redis configuration
redis:
  enabled: true
  host: redis
  port: 6379
EOF

    # Конфигурация логирования
    cat > ./configs/log.config << EOF
version: 1

formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'

handlers:
  console:
    class: logging.StreamHandler
    formatter: precise

root:
    level: INFO
    handlers: [console]

disable_existing_loggers: false
EOF

    # Конфигурация Coturn
    cat > ./configs/turnserver.conf << EOF
use-auth-secret
static-auth-secret=$COTURN_SECRET
realm=$MATRIX_DOMAIN
min-port=49152
max-port=65535
verbose
fingerprint
lt-cred-mech
no-tcp-relay
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
user-quota=12
total-quota=1200
EOF

    # Nginx конфигурация
    mkdir -p ./configs/nginx-sites
    cat > ./configs/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF

    cat > ./configs/nginx-sites/matrix.conf << EOF
server {
    listen 80;
    server_name $MATRIX_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $MATRIX_DOMAIN;

    ssl_certificate /etc/ssl/certs/fullchain.pem;
    ssl_certificate_key /etc/ssl/certs/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;

    location /.well-known/matrix/server {
        return 200 '{"m.server": "$MATRIX_DOMAIN:8448"}';
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
    }

    location /.well-known/matrix/client {
        return 200 '{"m.homeserver": {"base_url": "https://$MATRIX_DOMAIN"}}';
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
    }

    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://synapse:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 50M;
    }
    
    location / {
        proxy_pass http://element:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 8448 ssl http2;
    listen [::]:8448 ssl http2;
    server_name $MATRIX_DOMAIN;

    ssl_certificate /etc/ssl/certs/fullchain.pem;
    ssl_certificate_key /etc/ssl/certs/privkey.pem;

    location / {
        proxy_pass http://synapse:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 50M;
    }
}
EOF

    # Element конфигурация
    cat > ./configs/element-config.json << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$MATRIX_DOMAIN",
            "server_name": "$SERVER_NAME"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "disable_custom_urls": false,
    "disable_guests": false,
    "disable_login_language_selector": false,
    "disable_3pid_login": false,
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ],
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "defaultCountryCode": "GB",
    "showLabsSettings": false,
    "features": {},
    "default_federate": true,
    "default_theme": "light",
    "roomDirectory": {
        "servers": [
            "$SERVER_NAME"
        ]
    }
}
EOF

    print_success "Конфигурационные файлы созданы"
}

setup_ssl_docker() {
    print_header "НАСТРОЙКА SSL ДЛЯ DOCKER"
    
    print_info "Для работы с Docker вам нужно разместить SSL сертификаты в папке ./ssl/"
    print_info "Файлы должны называться: fullchain.pem и privkey.pem"
    
    if [ ! -f "./ssl/fullchain.pem" ] || [ ! -f "./ssl/privkey.pem" ]; then
        print_warning "SSL сертификаты не найдены"
        read -p "Хотите создать самоподписанные сертификаты для тестирования? (y/N): " CREATE_SELF_SIGNED
        
        if [[ "$CREATE_SELF_SIGNED" =~ ^[Yy]$ ]]; then
            mkdir -p ./ssl
            openssl req -x509 -newkey rsa:4096 -keyout ./ssl/privkey.pem -out ./ssl/fullchain.pem -days 365 -nodes \
                -subj "/C=US/ST=State/L=City/O=Organization/CN=$MATRIX_DOMAIN"
            print_success "Самоподписанные сертификаты созданы"
            print_warning "Для продакшн использования получите настоящие SSL сертификаты!"
        else
            print_error "Разместите SSL сертификаты в ./ssl/ перед запуском Docker"
            exit 1
        fi
    else
        print_success "SSL сертификаты найдены"
    fi
}

start_docker_services() {
    print_header "ЗАПУСК DOCKER СЕРВИСОВ"
    
    cd ./docker
    
    print_info "Создание и запуск контейнеров..."
    docker-compose up -d
    
    print_info "Ожидание запуска сервисов..."
    sleep 30
    
    # Проверка статуса контейнеров
    print_info "Статус контейнеров:"
    docker-compose ps
    
    print_success "Docker сервисы запущены"
}

create_admin_user_docker() {
    print_header "СОЗДАНИЕ АДМИНИСТРАТОРА"
    
    read -p "Введите имя пользователя администратора: " ADMIN_USER
    read -s -p "Введите пароль для администратора: " ADMIN_PASSWORD
    echo
    
    cd ./docker
    
    # Создание администратора в контейнере
    docker-compose exec synapse register_new_matrix_user \
        -c /data/homeserver.yaml \
        -u "$ADMIN_USER" \
        -p "$ADMIN_PASSWORD" \
        -a
    
    print_success "Администратор создан: @$ADMIN_USER:$SERVER_NAME"
}

show_docker_info() {
    print_header "ИНФОРМАЦИЯ О DOCKER РАЗВЕРТЫВАНИИ"
    
    echo -e "${GREEN}Matrix Synapse развернут в Docker!${NC}"
    echo
    echo "Сервисы:"
    echo "- Matrix Synapse: http://localhost:$HTTP_PORT"
    echo "- Element Web: http://localhost:8080"
    echo "- PostgreSQL: localhost:5432"
    echo "- Redis: localhost:6379"
    echo "- Coturn: $MATRIX_DOMAIN:$COTURN_PORT"
    echo
    echo "Управление:"
    echo "- Запуск: cd docker && docker-compose up -d"
    echo "- Остановка: cd docker && docker-compose down"
    echo "- Логи: cd docker && docker-compose logs -f [service]"
    echo "- Обновление: cd docker && docker-compose pull && docker-compose up -d"
    echo
    echo "Резервное копирование:"
    echo "- База данных: docker-compose exec postgres pg_dump -U synapse synapse > backup.sql"
    echo "- Конфигурация: уже сохранена в ./configs/"
    echo "- Медиафайлы: docker-compose exec synapse tar -czf - /data/media > media_backup.tar.gz"
}

main() {
    print_header "MATRIX SYNAPSE DOCKER УСТАНОВКА"
    
    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker не установлен! Установите Docker и Docker Compose."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose не установлен!"
        exit 1
    fi
    
    collect_docker_config
    generate_docker_configs
    setup_ssl_docker
    start_docker_services
    create_admin_user_docker
    show_docker_info
    
    print_success "Docker установка завершена!"
}

main "$@"
