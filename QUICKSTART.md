# Быстрый старт - Matrix Synapse + Coturn

## 🚀 Быстрая установка

### 1. Подготовка сервера
```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Настройка временной зоны (опционально)
sudo timedatectl set-timezone Europe/Moscow
```

### 2. Клонирование и запуск
```bash
# Если у вас есть git
git clone <your-repo-url> matrix-server
cd matrix-server

# Или скачайте и распакуйте архив
# Затем перейдите в папку проекта

# Запуск интерактивной установки
sudo ./install.sh
```

### 3. Что потребуется ввести:
- **Домен Matrix**: matrix.yourdomain.com
- **Имя сервера**: yourdomain.com  
- **Email**: your@email.com (для SSL сертификатов)
- **Пароль БД**: надежный пароль для PostgreSQL
- **Порты**: обычно по умолчанию подходят

### 4. DNS настройки
После установки настройте DNS записи:
```
A    matrix.yourdomain.com    →  YOUR_SERVER_IP
A    yourdomain.com          →  YOUR_SERVER_IP
SRV  _matrix._tcp.yourdomain.com  →  10 0 8448 matrix.yourdomain.com
```

### 5. Проверка работы
```bash
# Статус сервисов
./scripts/monitor.sh services

# Полная панель мониторинга
./scripts/monitor.sh

# Тест доступности
curl https://matrix.yourdomain.com/_matrix/federation/v1/version
```

---

## 🐳 Docker установка (альтернатива)

Если предпочитаете Docker:
```bash
# Установка Docker (если нужно)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Перелогиньтесь или выполните:
newgrp docker

# Запуск Docker установки
./docker/install-docker.sh
```

---

## 📱 Подключение клиентов

1. Скачайте Element или другой Matrix клиент
2. При настройке введите:
   - **Сервер**: https://matrix.yourdomain.com
   - **Имя пользователя**: admin (или созданное при установке)
   - **Пароль**: тот что задали при установке

---

## ⚡ Полезные команды

```bash
# Обновление всей системы
./scripts/update.sh

# Создание резервной копии
./scripts/backup.sh

# Мониторинг в реальном времени
./scripts/monitor.sh dashboard

# Просмотр логов
sudo journalctl -u matrix-synapse -f

# Создание нового пользователя
sudo -u synapse /var/lib/synapse/venv/bin/register_new_matrix_user \
    -c /etc/synapse/homeserver.yaml

# Полное удаление (если понадобится)
./scripts/uninstall.sh
```

---

## 🔧 Решение проблем

### Сервер не доступен
```bash
# Проверка сервисов
sudo systemctl status matrix-synapse coturn nginx

# Перезапуск
sudo systemctl restart matrix-synapse
```

### Ошибки прав доступа или pkg_resources
```bash
# Автоматическое исправление
./scripts/fix-synapse.sh

# Или вручную:
sudo chown -R synapse:synapse /etc/synapse /var/lib/synapse /var/log/synapse
sudo systemctl restart matrix-synapse
```

### Проблемы с SSL
```bash
# Обновление сертификатов
sudo certbot renew
sudo systemctl reload nginx
```

### Ошибки в логах
```bash
# Просмотр ошибок
sudo journalctl -u matrix-synapse --since "1 hour ago" | grep -i error
```

---

## 📞 Поддержка

Если возникли проблемы:
1. Проверьте логи: `./scripts/monitor.sh`
2. Убедитесь что DNS настроен корректно
3. Проверьте открытые порты: `sudo ufw status`
4. Создайте issue в репозитории проекта

**Успешной установки! 🎉**
