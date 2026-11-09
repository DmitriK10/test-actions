# CI/CD: FastAPI → Docker → GHCR → деплой по SSH

Учебный проект по автоматизации доставки кода: приложение на FastAPI упаковывается в Docker-образ, публикуется в GitHub Container Registry и автоматически разворачивается на сервере по SSH. Всё происходит по push в `main`, без ручных шагов.

Репозиторий небольшой (5 файлов), но это не заготовка: пайплайн рабочий и собирается из двух последовательных джобов.

## Что здесь главное

Ценность проекта — не приложение, а `.github/workflows/deploy.yaml`: полный путь от коммита до запущенного контейнера на удалённом сервере.

```
push в main
    │
    ├─ JOB build (ubuntu-latest)
    │   ├─ checkout
    │   ├─ setup-buildx
    │   ├─ login в ghcr.io по GITHUB_TOKEN
    │   ├─ metadata: теги sha (короткий) + latest
    │   └─ build-push: сборка и публикация образа
    │       cache-from/to: type=gha
    │
    └─ JOB deploy (needs: build, только для main)
        └─ SSH на сервер:
            ├─ docker stop/rm старого контейнера (|| true)
            ├─ login в ghcr.io
            ├─ docker pull ...:latest
            ├─ docker run -d --restart unless-stopped
            └─ docker image prune -f
```

## Что показывает проект

| Практика | Где видно |
|---|---|
| Docker-образ приложения | `Dockerfile`: `python:3.11-slim`, установка зависимостей отдельным слоем, запуск через uvicorn |
| Публикация в реестр | GHCR (`ghcr.io/<owner>/<repo>`), права `packages: write` |
| Тегирование образов | `docker/metadata-action`: тег по короткому SHA + `latest` только для дефолтной ветки |
| Кэш сборки | `cache-from: type=gha`, `cache-to: type=gha,mode=max` — повторные сборки быстрее |
| Порядок джобов | `needs: build` — деплой не стартует, если сборка упала |
| Защита от деплоя с ветки | `if: github.ref == 'refs/heads/main'` |
| Секреты вне репозитория | `HOST`, `USERNAME`, `SSH_KEY`, `PORT` — в GitHub Secrets |
| Чистка сервера | `docker image prune -f` после деплоя |

## Приложение

`app/main.py` — FastAPI-сервис «Time Server API»: четыре эндпоинта, выбран нарочно простым, чтобы внимание было на пайплайне, а не на бизнес-логике.

| Метод | Назначение |
|---|---|
| `GET /` | приветствие |
| `GET /time` | текущее время UTC |
| `GET /date` | текущая дата UTC |
| `GET /datetime` | дата и время UTC одной строкой |
| `GET /convert?time_str=&from_tz=&to_tz=` | конвертация времени между часовыми поясами (`Europe/Moscow` → `America/New_York`) |

Swagger доступен на `/docs`.

## Запуск локально

```bash
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Или в Docker:

```bash
docker build -t time-server .
docker run -d --name fastapi-app -p 8000:8000 time-server
```

Проверка:

```bash
curl http://localhost:8000/time
curl "http://localhost:8000/convert?time_str=2025-03-30T12:00:00&from_tz=Europe/Moscow&to_tz=America/New_York"
```

## Что нужно, чтобы пайплайн заработал у себя

1. Форкнуть репозиторий или скопировать `.github/workflows/deploy.yaml`.
2. В **Settings → Secrets and variables → Actions** добавить:

   | Секрет | Значение |
   |---|---|
   | `HOST` | IP или домен сервера |
   | `USERNAME` | пользователь SSH |
   | `SSH_KEY` | приватный ключ (содержимое, не путь) |
   | `PORT` | порт SSH, обычно `22` |

3. На сервере должен быть установлен Docker и открыт порт приложения (8000).
4. `GITHUB_TOKEN` выдаётся автоматически — создавать его не нужно.

## Замечание по безопасности

В джобе `deploy` токен передаётся в удалённый скрипт через `echo ${{ secrets.GITHUB_TOKEN }} | docker login ...`. GitHub подставляет значение до отправки команды, поэтому токен попадает в командную строку на сервере и виден в `ps` другим пользователям машины.

Безопаснее — не логиниться на сервере повторно, а один раз выполнить `docker login ghcr.io` вручную под отдельного пользователя, либо использовать `docker pull` с заранее настроенным `~/.docker/config.json`. Для учебного проекта это допустимо, для продакшена — нет.

## Ограничения

- Приложение не хранит состояние: только чтение системного времени.
- Нет тестов и линтеров в пайплайне — стадия проверки кода отсутствует.
- Отката нет: если новый образ не запустится, старый контейнер уже удалён. Для продакшена нужен healthcheck и возврат к предыдущему тегу.
