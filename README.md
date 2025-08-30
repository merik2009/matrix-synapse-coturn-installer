# Matrix Synapse + Coturn - Автоматическая установка

Этот проект предоставляет интерактивные скрипты для автоматической установки и настройки сервера Matrix Synapse с Coturn для полноценного поднятия системы обмена сообщениями с поддержкой голосовых и видеозвонков.

## 🚀 Возможности

- **Полная автоматизация**: Интерактивная установка всех компонентов
- **Matrix Synapse**: Основной сервер Matrix с поддержкой федерации
- **Coturn**: TURN/STUN сервер для голосовых и видеозвонков
- **PostgreSQL**: Оптимизированная база данных
- **Nginx**: Обратный прокси с SSL
- **Let's Encrypt**: Автоматическое получение SSL сертификатов
- **Мониторинг**: Встроенные инструменты мониторинга
- **Резервное копирование**: Автоматические бэкапы
- **Docker**: Альтернативное развертывание через Docker

## 📋 Требования

### Минимальные требования
- **ОС**: Ubuntu 20.04+ / Debian 11+
- **CPU**: 2 ядра
- **RAM**: 4 GB
- **Диск**: 20 GB свободного места
- **Сеть**: Публичный IP адрес
- **Домен**: Настроенный DNS домен
- **Права**: Обычный пользователь с sudo или root доступ

### Рекомендуемые требования
- **CPU**: 4+ ядра
- **RAM**: 8+ GB
- **Диск**: 50+ GB (SSD)

## 🛠 Установка

### Метод 1: Прямая установка на сервер

1. **Клонирование проекта**:
```bash
git clone https://github.com/merik2009/matrix-synapse-coturn-installer.git
cd matrix-synapse-coturn-installer
```

2. **Сделать скрипт исполняемым**:
```bash
chmod +x install.sh
chmod +x scripts/*.sh
```

3. **Запуск интерактивной установки**:

**От обычного пользователя** (рекомендуется):
```bash
./install.sh
```

**От root** (для серверов):
```bash
# Войти как root
sudo su -
# или
sudo -i

# Перейти в директорию проекта
cd /path/to/matrix-synapse-coturn-installer

# Запустить установку
./install.sh
```

4. **Следуйте инструкциям** в интерактивном режиме:
   - Введите домен для Matrix сервера (например, matrix.example.com)
   - Введите имя сервера (например, example.com)  
   - Введите email для Let's Encrypt
   - Задайте пароль для базы данных
   - Настройте порты (по умолчанию подходят для большинства случаев)

### Метод 2: Docker развертывание

1. **Установка Docker и Docker Compose** (если не установлены):
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

2. **Запуск Docker установки**:
```bash
chmod +x docker/install-docker.sh
./docker/install-docker.sh
```

## 🏗 Структура проекта

```
MATRIX-SYNAPSE-COTURN/
├── install.sh              # Основной скрипт установки
├── scripts/
│   ├── update.sh           # Скрипт обновления
│   ├── backup.sh           # Скрипт резервного копирования
│   └── monitor.sh          # Скрипт мониторинга
├── docker/
│   ├── docker-compose.yml  # Docker Compose конфигурация
│   └── install-docker.sh   # Docker установка
├── configs/
│   └── install_config.env  # Конфигурация (создается при установке)
├── ssl/                    # SSL сертификаты
├── data/                   # Данные и бэкапы
└── README.md              # Этот файл
```

## ⚙️ Конфигурация

### Основные параметры, которые будут запрошены:

- **MATRIX_DOMAIN**: Домен для Matrix сервера (matrix.example.com)
- **SERVER_NAME**: Имя сервера для Matrix (example.com)
- **LETSENCRYPT_EMAIL**: Email для получения SSL сертификатов
- **DB_PASSWORD**: Пароль для базы данных PostgreSQL
- **COTURN_SECRET**: Секретный ключ для Coturn (генерируется автоматически)
- **HTTP_PORT**: HTTP порт для Matrix (по умолчанию 8008)
- **HTTPS_PORT**: HTTPS порт для Matrix (по умолчанию 8448)
- **COTURN_PORT**: Порт для Coturn (по умолчанию 3478)

### DNS настройки

После установки необходимо настроить DNS записи:

```
A     matrix.example.com    -> IP_ADDRESS
A     example.com           -> IP_ADDRESS (если используется как основной домен)
SRV   _matrix._tcp.example.com -> 10 0 8448 matrix.example.com
```

## 🔧 Управление сервисами

### Системные команды
```bash
# Статус сервисов
sudo systemctl status matrix-synapse coturn nginx postgresql

# Перезапуск сервисов
sudo systemctl restart matrix-synapse
sudo systemctl restart coturn
sudo systemctl restart nginx

# Просмотр логов
sudo journalctl -u matrix-synapse -f
sudo journalctl -u coturn -f
```

### Скрипты управления

#### Мониторинг
```bash
# Интерактивная панель мониторинга
./scripts/monitor.sh

# Создание отчета
./scripts/monitor.sh report

# Проверка конкретных компонентов
./scripts/monitor.sh services
./scripts/monitor.sh network
./scripts/monitor.sh database
```

#### Обновление
```bash
# Обновление всех компонентов
./scripts/update.sh

# Выборочное обновление
./scripts/update.sh  # Выберите опцию в меню
```

#### Резервное копирование
```bash
# Создание полной резервной копии
./scripts/backup.sh

# Резервные копии сохраняются в ./data/backups/
```

## 🐳 Docker управление

### Основные команды
```bash
cd docker

# Запуск всех сервисов
docker-compose up -d

# Остановка сервисов
docker-compose down

# Просмотр логов
docker-compose logs -f synapse
docker-compose logs -f coturn

# Обновление образов
docker-compose pull
docker-compose up -d
```

### Создание пользователя в Docker
```bash
cd docker
docker-compose exec synapse register_new_matrix_user \
    -c /data/homeserver.yaml \
    -u username \
    -p password \
    -a  # для администратора
```

## 🔐 Безопасность

### Настройки брандмауэра
Скрипт автоматически настраивает UFW брандмауэр со следующими правилами:
- SSH (22/tcp)
- HTTP (80/tcp)
- HTTPS (443/tcp)
- Matrix federation (8448/tcp)
- Coturn (3478/tcp,udp и 5349/tcp)
- RTC порты (49152-65535/udp)

### SSL сертификаты
- Автоматическое получение Let's Encrypt сертификатов
- Автоматическое обновление через certbot
- Использование современных протоколов TLS 1.2/1.3

### Дополнительные меры безопасности
- Настройка fail2ban для защиты от брутфорса
- Регулярные обновления системы
- Ограничение доступа к базе данных
- Защищенные настройки Nginx

## 📱 Клиенты

### Рекомендуемые клиенты Matrix:
- **Element Web**: https://app.element.io
- **Element Desktop**: https://element.io/get-started
- **Element Mobile**: App Store / Google Play
- **FluffyChat**: Альтернативный мобильный клиент
- **Nheko**: Десктопный клиент для Linux/Windows/macOS

### Настройки клиента:
- **Homeserver**: https://matrix.example.com
- **Пользователь**: @username:example.com

## 🔍 Диагностика

### Проверка работоспособности
```bash
# Тест доступности Matrix API
curl https://matrix.example.com/_matrix/federation/v1/version

# Тест well-known записей
curl https://matrix.example.com/.well-known/matrix/server
curl https://matrix.example.com/.well-known/matrix/client

# Проверка SSL сертификата
openssl s_client -connect matrix.example.com:443 -servername matrix.example.com
```

### Частые проблемы

1. **Сервер недоступен**:
   - Проверьте DNS записи
   - Убедитесь, что порты открыты
   - Проверьте статус сервисов

2. **Ошибки SSL**:
   - Проверьте действительность сертификатов
   - Убедитесь, что домен корректно настроен

3. **Проблемы с правами доступа или pkg_resources**:
   ```bash
   # Автоматическое исправление всех проблем
   ./scripts/fix-synapse.sh
   
   # Или отдельные команды:
   ./scripts/fix-synapse.sh permissions  # Исправить права
   ./scripts/fix-synapse.sh key         # Создать ключ подписи
   ./scripts/fix-synapse.sh check       # Проверить конфигурацию
   ```

4. **Проблемы с голосовыми вызовами**:
   - Проверьте настройки Coturn
   - Убедитесь, что RTC порты открыты
   - Проверьте конфигурацию TURN в Synapse

5. **Ошибка "Permission denied" при генерации конфигурации**:
   ```bash
   # Исправление прав доступа
   sudo chown -R synapse:synapse /etc/synapse
   sudo chown -R synapse:synapse /var/lib/synapse
   sudo chown -R synapse:synapse /var/log/synapse
   
   # Перезапуск сервиса
   sudo systemctl restart matrix-synapse
   ```

## 📊 Мониторинг и метрики

### Встроенный мониторинг
Скрипт `monitor.sh` предоставляет:
- Статус всех сервисов
- Использование ресурсов (CPU, RAM, диск)
- Проверку сетевой доступности
- Анализ логов на ошибки
- Статистику базы данных

### Внешний мониторинг
Рекомендуется настроить:
- **Prometheus + Grafana** для детального мониторинга
- **Uptime monitoring** для проверки доступности
- **Log aggregation** для централизованного анализа логов

## 🔄 Обновления и обслуживание

### Регулярные задачи:
1. **Еженедельно**: Запуск скрипта обновления
2. **Ежедневно**: Проверка мониторинга
3. **Ежемесячно**: Создание полной резервной копии
4. **По необходимости**: Обновление SSL сертификатов (автоматически)

### Автоматизация через cron:
```bash
# Добавить в crontab (crontab -e)
0 2 * * 0 /path/to/scripts/update.sh  # Еженедельное обновление
0 3 * * * /path/to/scripts/backup.sh  # Ежедневный бэкап
```

## 🆘 Поддержка и помощь

### Логи и отладка:
- Логи установки: `./install.log`
- Логи Synapse: `/var/log/synapse/homeserver.log`
- Системные логи: `journalctl -u matrix-synapse`

### Полезные ресурсы:
- [Matrix.org Documentation](https://matrix.org/docs/)
- [Synapse Admin API](https://matrix-org.github.io/synapse/latest/admin_api/)
- [Element Help](https://element.io/help)

## 📝 Лицензия

Этот проект распространяется под лицензией MIT. См. файл LICENSE для подробностей.

## 🤝 Вклад в проект

Приветствуются любые улучшения и предложения! Пожалуйста, создавайте issues или pull requests.

---

**Примечание**: Этот скрипт предназначен для упрощения установки Matrix Synapse. Для продакшн развертывания рекомендуется дополнительная настройка безопасности и мониторинга в соответствии с требованиями вашей организации.
