#!/bin/bash

# Скрипт для создания git репозитория и загрузки на GitHub

echo "🚀 Инициализация Git репозитория..."

# Инициализация git репозитория
git init

# Добавление всех файлов
git add .

# Первый коммит
git commit -m "🎉 Initial commit: Matrix Synapse + Coturn автоматический инсталлятор

- Интерактивный скрипт установки Matrix Synapse
- Автоматическая настройка Coturn для голосовых вызовов
- Полная настройка PostgreSQL, Nginx, SSL
- Скрипты мониторинга, резервного копирования и обновления
- Docker альтернатива для развертывания
- Подробная документация и быстрый старт"

echo "✅ Git репозиторий инициализирован!"
echo ""
echo "📋 Следующие шаги:"
echo "1. Создайте новый репозиторий на GitHub.com"
echo "2. Скопируйте URL репозитория (например: https://github.com/username/repo.git)"
echo "3. Выполните команды:"
echo ""
echo "   git remote add origin https://github.com/USERNAME/REPOSITORY.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "🎯 Рекомендуемое название репозитория: matrix-synapse-coturn-installer"
