# 🔧 Решение проблем с Matrix Synapse

## 🚨 Проблема: ModuleNotFoundError - модуль synapse.crypto.signing_key не найден

### Описание ошибки:
```
ModuleNotFoundError: No module named 'synapse.crypto.signing_key'
```

### Причина:
Matrix Synapse не установлен или установлен неправильно в виртуальном окружении.

### ✅ Решение на сервере:

#### 1. **Проверка установки Synapse**
```bash
# Проверить виртуальное окружение
ls -la /var/lib/synapse/venv/

# Проверить установленные пакеты
sudo -u synapse /var/lib/synapse/venv/bin/pip list | grep matrix-synapse
```

#### 2. **Переустановка Synapse (если не установлен)**
```bash
# Остановить сервис
sudo systemctl stop matrix-synapse

# Создать/обновить виртуальное окружение
sudo mkdir -p /var/lib/synapse
sudo python3 -m venv /var/lib/synapse/venv

# Установить Synapse
sudo /var/lib/synapse/venv/bin/pip install --upgrade pip setuptools wheel
sudo /var/lib/synapse/venv/bin/pip install "matrix-synapse[all]"

# Установить дополнительные зависимости
sudo /var/lib/synapse/venv/bin/pip install psycopg2-binary

# Исправить права доступа
sudo chown -R synapse:synapse /var/lib/synapse
```

#### 3. **Проверка работоспособности**
```bash
# Тест импорта модуля
sudo -u synapse /var/lib/synapse/venv/bin/python -c "
try:
    from synapse.crypto.signing_key import generate_signing_key
    print('✅ Модуль synapse.crypto.signing_key найден!')
except ImportError as e:
    print(f'❌ Ошибка импорта: {e}')
"

# Генерация тестового ключа
sudo -u synapse /var/lib/synapse/venv/bin/python -c "
from synapse.crypto.signing_key import generate_signing_key
import tempfile
import os

with tempfile.NamedTemporaryFile(delete=False) as f:
    generate_signing_key(f.name)
    print(f'✅ Ключ успешно сгенерирован в {f.name}')
    os.unlink(f.name)
"
```

#### 4. **Автоматическое решение**
```bash
# Запустить скрипт исправления
./scripts/fix-synapse.sh reinstall
```

## 🚨 Проблема: Permission denied при генерации конфигурации

### Описание ошибки:
```
PermissionError: [Errno 13] Permission denied: '/etc/synapse/homeserver.yaml'
UserWarning: pkg_resources is deprecated
```

### ✅ Исправления в коде:

#### 1. **Исправлены права доступа при установке**
```bash
# В функции install_synapse() добавлено:
sudo chown -R synapse:synapse /etc/synapse
```

#### 2. **Улучшена генерация конфигурации**
- Временная генерация в `/tmp/`
- Создание финального файла с sudo
- Правильная генерация ключа подписи

#### 3. **Добавлен python3-nacl**
```bash
# В список пакетов добавлено:
python3-nacl
```

#### 4. **Создан скрипт исправления**
```bash
./scripts/fix-synapse.sh
```

## 🛠 Автоматическое решение

### Запуск скрипта исправления:
```bash
# Исправить все проблемы автоматически
./scripts/fix-synapse.sh

# Или отдельные команды:
./scripts/fix-synapse.sh permissions  # Права доступа
./scripts/fix-synapse.sh key         # Ключ подписи  
./scripts/fix-synapse.sh check       # Проверка конфигурации
./scripts/fix-synapse.sh status      # Статус сервисов
```

## 🔨 Ручное решение

### 1. Остановка Synapse
```bash
sudo systemctl stop matrix-synapse
```

### 2. Исправление прав доступа
```bash
sudo chown -R synapse:synapse /etc/synapse
sudo chown -R synapse:synapse /var/lib/synapse  
sudo chown -R synapse:synapse /var/log/synapse
sudo chmod 600 /etc/synapse/homeserver.signing.key
```

### 3. Обновление setuptools (если есть warning)
```bash
sudo -u synapse /var/lib/synapse/venv/bin/pip install --upgrade "setuptools<81"
```

### 4. Генерация ключа подписи (если отсутствует)
```bash
sudo -u synapse /var/lib/synapse/venv/bin/python -c "
from synapse.config.key import KeyConfig
import tempfile
import os
import shutil

temp_dir = tempfile.mkdtemp()
key_path = os.path.join(temp_dir, 'signing.key')

try:
    key_config = KeyConfig()
    key_config.generate_files({'signing_key_path': key_path}, {})
    shutil.copy2(key_path, '/etc/synapse/homeserver.signing.key')
finally:
    shutil.rmtree(temp_dir, ignore_errors=True)
"

sudo chown synapse:synapse /etc/synapse/homeserver.signing.key
sudo chmod 600 /etc/synapse/homeserver.signing.key
```

### 5. Проверка конфигурации
```bash
sudo -u synapse /var/lib/synapse/venv/bin/python -m synapse.config.homeserver -c /etc/synapse/homeserver.yaml --generate-keys
```

### 6. Запуск сервиса
```bash
sudo systemctl start matrix-synapse
sudo systemctl status matrix-synapse
```

## 📋 Проверка работоспособности

### Статус сервисов
```bash
sudo systemctl status matrix-synapse coturn nginx postgresql
```

### Логи
```bash
# Логи Synapse
sudo journalctl -u matrix-synapse -f

# Логи файла
sudo tail -f /var/log/synapse/homeserver.log
```

### Тест API
```bash
curl https://matrix.yourdomain.com/_matrix/federation/v1/version
```

## 🔄 Предотвращение проблем

### В новых установках:
1. ✅ **Обновленный скрипт** уже содержит исправления
2. ✅ **Автоматическая проверка прав** доступа
3. ✅ **Правильная генерация ключей** подписи
4. ✅ **Обработка ошибок** pkg_resources

### Для существующих установок:
```bash
# Регулярно запускайте проверку
./scripts/monitor.sh

# При проблемах используйте
./scripts/fix-synapse.sh
```

## 🎯 Результат

После применения исправлений:
- ✅ Matrix Synapse запускается без ошибок
- ✅ Конфигурация генерируется корректно  
- ✅ Права доступа настроены правильно
- ✅ Предупреждения pkg_resources устранены
- ✅ Ключ подписи создается автоматически

**Проблема полностью решена! 🎉**
