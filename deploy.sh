#!/bin/bash
# Скрипт деплоя test-actions. Запускается по SSH с ключа, у которого в
# authorized_keys прописан command= на этот файл: произвольные команды
# по этому ключу выполнить нельзя, только деплой.
#
# Что делает: подтягивает main из GitHub, пересобирает образ и поднимает
# контейнер через compose. Порт остаётся на 127.0.0.1, наружу выходит nginx.

set -euo pipefail

REPO_DIR=${REPO_DIR:-/srv/test-actions}
BRANCH=${BRANCH:-main}
LOG=${LOG:-/var/log/test-actions-deploy.log}

# Весь вывод — в лог и в stdout: stdout видит GitHub Actions.
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date -Is) деплой начат ==="

cd "$REPO_DIR"

# Чужие правки в рабочей копии ломают pull — сообщаем и выходим,
# а не затираем их молча.
if [ -n "$(git status --porcelain)" ]; then
    echo "ОШИБКА: в $REPO_DIR есть незакоммиченные изменения:"
    git status --short
    exit 1
fi

git fetch --quiet origin "$BRANCH"
BEFORE=$(git rev-parse HEAD)
git checkout --quiet "$BRANCH"
git reset --hard --quiet "origin/$BRANCH"
AFTER=$(git rev-parse HEAD)
echo "коммит: $BEFORE -> $AFTER"

if [ "$BEFORE" = "$AFTER" ] && docker compose ps --quiet api | grep -q .; then
    echo "изменений нет, контейнер работает — пересборка не нужна"
else
    docker compose up -d --build --remove-orphans
fi

# Ждём healthcheck, а не просто «контейнер запущен».
echo "ожидание healthcheck..."
for i in $(seq 1 30); do
    STATUS=$(docker inspect -f '{{.State.Health.Status}}' fastapi-app 2>/dev/null || echo "нет контейнера")
    [ "$STATUS" = "healthy" ] && break
    [ "$STATUS" = "unhealthy" ] && break
    sleep 2
done

echo "health: $STATUS"
docker compose ps

if [ "$STATUS" != "healthy" ]; then
    echo "ОШИБКА: контейнер не стал healthy, последние логи:"
    docker compose logs --tail=30
    exit 1
fi

# Проверка через nginx: контейнер может быть жив, а проксирование сломано.
for path in /api/time/ /api/time/time /api/time/docs; do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1$path" || echo 000)
    echo "  $CODE  $path"
    [ "$CODE" = "200" ] || { echo "ОШИБКА: $path вернул $CODE"; exit 1; }
done

echo "=== $(date -Is) деплой завершён успешно ==="
