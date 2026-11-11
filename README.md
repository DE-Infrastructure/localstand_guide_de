# Учебное DWH: PostgreSQL → Airflow → Greenplum → dbt

Стенд онлайн-школы для гайда: одна полностью реализованная витрина продаж и задания для самостоятельной практики. В Postgres уже есть данные для всех витрин.

Greenplum работает как MPP-кластер: координатор и два primary-сегмента внутри одного контейнера. В гайде есть примеры распределения строк и обмена данными между сегментами.

**[Архитектура, данные и сценарий YouTube-гайда →](docs/DWH_GUIDE.md)**

**[Подробный сценарий записи: от установки программ до разбора витрины →](docs/VIDEO_SCRIPT.md)**

**[Задания: покупки студентов и эффективность курсов →](docs/EXERCISES.md)**

**[Что проверено и как выполнить полную проверку →](docs/VALIDATION.md)**

## 1. Подготовка компьютера — один раз

Нужны **Git и запущенный Docker с Compose 2.20+**. Python, PostgreSQL, Greenplum, Airflow и dbt устанавливаются внутри контейнеров. Рекомендуется компьютер с 16 ГБ RAM, для Docker — 4 CPU и 8 ГБ RAM; свободное место — от 20 ГБ. Интернет нужен для клонирования и первой сборки.

Для повторения видео также установи **[VS Code](https://code.visualstudio.com/Download)** для просмотра кода и **[DBeaver Community](https://dbeaver.io/download/)** для SQL-запросов. **[Пошаговая установка с нуля](docs/VIDEO_SCRIPT.md#setup-from-zero)** включает macOS, Linux и Windows 10/11: куда нажимать, где вводить команды, как открыть проект, создать оба подключения и проверить результат.

| Система | Как запускать |
|---|---|
| macOS, Apple Silicon или Intel | Docker Desktop для своего процессора; команды ниже — в Terminal |
| Linux, x86-64 или arm64 | Docker Engine с плагинами Compose и Buildx; команды — в Bash |
| Windows 10 / 11 | Docker Desktop, Linux containers, WSL2 + Ubuntu; все команды проекта — в терминале Ubuntu |

<details>
<summary>macOS: если Docker ещё не установлен</summary>

1. Установи [Docker Desktop для Mac](https://docs.docker.com/desktop/setup/install/mac-install/), выбрав Apple Silicon или Intel.
2. Запусти Docker Desktop и дождись готовности движка. В настройках ресурсов выдели 4 CPU и 8 ГБ RAM.
3. Открой Terminal. Проверь `git --version`; если macOS предложит установить Command Line Tools, согласись.

Если уже пользуешься Colima, оставь её: достаточно работающего Docker Engine и Compose. Два движка одновременно не нужны.

</details>

<details>
<summary>Linux: если Docker ещё не установлен</summary>

Установи Git и [Docker Engine для своего дистрибутива](https://docs.docker.com/engine/install/), включая `docker-compose-plugin` и `docker-buildx-plugin`. Для гайда удобны Ubuntu 22.04/24.04 или Debian.

Команда `docker info` должна работать из твоего терминала. Настрой доступ пользователя по [инструкции Docker](https://docs.docker.com/engine/install/linux-postinstall/) или используй `sudo docker ...` во всех командах. После добавления пользователя в группу Docker нужно заново войти в систему.

Базы и логи хранятся в Docker volumes, поэтому создавать каталоги данных, менять UID и выполнять `chmod 777` не требуется. Для общих каталогов кода в Compose задана метка `z`, необходимая на хостах с SELinux.

</details>

<details>
<summary>Windows 10 / 11: WSL2 и Docker Desktop</summary>

1. В PowerShell от администратора установи Ubuntu в WSL и перезагрузи компьютер, если Windows попросит:

   ```powershell
   wsl --install -d Ubuntu
   wsl --update
   wsl --set-default-version 2
   ```

   Если Ubuntu уже установлена, достаточно обновить WSL. Проверь `wsl -l -v`: у Ubuntu должна быть версия `2`; для старой установки выполни `wsl --set-version Ubuntu 2`. [Инструкция Microsoft](https://learn.microsoft.com/en-us/windows/wsl/install).

2. Установи и запусти [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/). Используй **Linux containers**, включи **Use WSL 2 based engine** и **Settings → Resources → WSL Integration → Ubuntu**. [Настройка интеграции](https://docs.docker.com/desktop/features/wsl/).
3. Открой **Ubuntu** из меню Windows, создай Linux-пользователя при первом запуске. В этом терминале:

   ```bash
   sudo apt-get update
   sudo apt-get install -y git
   cd ~
   ```

4. Выполняй дальнейшие команды в Ubuntu и клонируй проект в её домашний каталог (`~/localstand_guide_de`). Это позволяет использовать все команды гайда, включая `< scripts/demo_changes.sql`. Хранение проекта в файловой системе WSL также рекомендовано в [документации Docker](https://docs.docker.com/desktop/features/wsl/best-practices/).

Docker Engine внутри Ubuntu отдельно устанавливать не нужно: его предоставляет Docker Desktop. Интерфейс Airflow открывается в обычном браузере Windows по `http://localhost:8080`.

**Версии Windows:** технические требования Docker включают Windows 10 22H2, сборку 19045, либо Windows 11 23H2+, а также WSL 2.1.5+. Официальная поддержка Docker Desktop дополнительно зависит от срока обслуживания Windows; проверь [требования Docker](https://docs.docker.com/desktop/setup/install/windows-install/) для своей редакции. Старые сборки Windows и WSL1 для этого сценария не подходят.

</details>

Перед первым запуском эти команды должны завершаться без ошибки:

```bash
git --version
docker info
docker compose version
```

## 2. Клонирование и выбор сервисов

```bash
git clone https://github.com/DE-Infrastructure/localstand_guide_de.git
cd localstand_guide_de
```

Стенд можно разворачивать по частям. **Без профиля запускаются только Airflow и его служебный Postgres; dbt уже установлен в образе Airflow.** Бизнес-источник и Greenplum включаются дополнительной командой.

| Что нужно сейчас | Команда | Что работает после запуска |
|---|---|---|
| Airflow + dbt | `docker compose up --build --detach --wait --wait-timeout 600` | Интерфейс, scheduler и служебная база Airflow |
| Добавить Postgres с учебными данными | `docker compose --profile source up --build --detach --wait --wait-timeout 600` | Airflow + dbt + источник `client-postgres` |
| Весь DWH с Greenplum | `docker compose --profile dwh up --build --detach --wait --wait-timeout 600` | Все сервисы и готовая цепочка до витрины |

Команды запуска выполняй из корня репозитория. Они подходят и для первого запуска, и для добавления сервисов к уже работающему стенду. `.env` создавать не требуется. Первый запуск собирает образ, поэтому может занять несколько минут.

### Сначала только Airflow и dbt

```bash
docker compose up --build --detach --wait --wait-timeout 600
docker compose ps -a
docker compose exec -T airflow-scheduler /opt/dbt-venv/bin/dbt --version
```

Открой [Airflow](http://localhost:8080), вход `airflow` / `airflow`. На новой установке DAG `academy_dwh` виден и стоит на паузе: баз для его загрузки пока нет. Команда `dbt --version` показывает установленный dbt; выполнение моделей этого DWH станет доступно после запуска Greenplum.

### Подключить весь DWH и построить витрину

```bash
docker compose --profile dwh up --build --detach --wait --wait-timeout 600
docker compose exec -T airflow-scheduler python /opt/airflow/scripts/smoke_test.py --initial-only
```

Профиль `dwh` добавляет источник и Greenplum. Postgres сам заполнится при первом создании тома. Одноразовый сервис `dwh-init` дождётся готовности баз и Airflow, снимет DAG `academy_dwh` с паузы. На новой установке расписание `@once` создаст первый запуск: загрузка raw → dbt → тесты → проверка витрины. Вторая команда дождётся его завершения и напечатает `PASS` с контрольными показателями.

Connections уже настроены. Импортировать CSV, добавлять DAG через интерфейс и вручную запускать dbt не требуется. Если первый запуск уже был выполнен на сохранённых томах, новый `@once` не создаётся; для повторного расчёта используй `docker compose exec -T airflow-scheduler airflow dags trigger academy_dwh`.

Репозиторий содержит код и небольшой SQL-генератор данных: текущие исходники и документы занимают около 350 КБ без Git-истории. Основной объём скачивания — Docker-образы; данные для всех заданий создаются локально. Архитектура образов выбирается автоматически: amd64 для Intel/AMD, arm64 для Apple Silicon и Linux arm64.

Если команда завершилась с ошибкой, посмотри состояние сервисов и логи:

```bash
docker compose --profile dwh ps -a
docker compose --profile dwh logs --tail 100 airflow-init dwh-init greenplum airflow-scheduler
```

| Сервис | Когда доступен | Адрес с компьютера | База | Пользователь / пароль |
|---|---|---|---|---|
| Airflow | Во всех вариантах | [localhost:8080](http://localhost:8080) | — | `airflow` / `airflow` |
| Postgres, источник | Профиль `source` или `dwh` | `localhost:5051` | `postgres` | `postgres` / `postgres` |
| Greenplum, DWH | Профиль `dwh` | `localhost:5433` | `dwh` | `gpadmin` / `gpadmin` |

Это локальные демонстрационные учётные записи; порты привязаны к `127.0.0.1`. В DBeaver подключай Greenplum через Greenplum или PostgreSQL-драйвер. Между контейнерами используются `client-postgres:5432` и `greenplum:5432`.

Настройки портов и UID необязательны: шаблон находится в `.env.example`. PostgreSQL для метаданных Airflow — отдельный служебный контейнер.

## 3. Результат

После запуска профиля `dwh` проверить уже готовую витрину можно без повторного DAG:

```bash
docker compose exec -T airflow-scheduler python /opt/airflow/scripts/verify_warehouse.py --expected baseline
```

Ожидается 200 студентов, 400 заказов, 320 оплаченных заказов, 640 зачислений. Продажи после возвратов: **7 158 110 ₽**.

Готовый пример — **`marts.mart_sales_daily`**: продажи по дню заказа и курсу, скидки и возвраты. Реализована вся цепочка от Postgres до витрины и проверок.

В [заданиях](docs/EXERCISES.md) предлагается самостоятельно построить:

- `marts.mart_student_ltv` — накопленные покупки каждого студента;
- `marts.mart_course_performance` — продажи и прогресс обучения по курсу.

Для заданий даны требования, критерии приёмки и раскрывающиеся подсказки. Все восемь таблиц Postgres, включая зачисления и события уроков, уже загружаются в `raw`. Учебные модели студент добавляет сам; стартовый DAG успешно работает до их реализации.

```bash
bash scripts/gp_sql.sh < docs/demo_queries.sql
```

## Изменение данных для видео

```bash
docker compose exec -T client-postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 < scripts/demo_changes.sql
docker compose exec -T airflow-scheduler airflow dags trigger academy_dwh
```

Дождись успешного завершения нового запуска, затем:

```bash
docker compose exec -T airflow-scheduler python /opt/airflow/scripts/verify_warehouse.py --expected changed
```

Появится заказ на **27 800 ₽**, обновится город студента. В `raw` добавятся две доставки одного события урока — их обработка входит в задание по обучению. Повторное применение SQL и повторная загрузка не увеличивают продажи.

## Остановка и переключение набора

Профиль выбирает сервисы для запуска. **Запуск без профиля не останавливает Greenplum, который уже работает.**

Чтобы временно вернуться от полного DWH к Airflow + dbt, дождись завершения активного DAG в Airflow, поставь его на паузу и останови дополнительные сервисы:

```bash
docker compose exec -T airflow-scheduler airflow dags pause academy_dwh
docker compose --profile dwh stop dwh-init greenplum client-postgres
```

Базы и таблицы сохранятся. Вернуть их можно командой полного запуска с `--profile dwh`; `dwh-init` снова включит DAG. Для нового расчёта после изменений запусти DAG вручную.

Остановить весь стенд и продолжить позднее:

```bash
docker compose --profile dwh stop
# Продолжить с Airflow + dbt:
docker compose up --detach --wait --wait-timeout 600
# Или продолжить со всем DWH:
docker compose --profile dwh up --detach --wait --wait-timeout 600
```

Удалить контейнеры всех профилей, сохранив данные: `docker compose --profile dwh down`. Именованные тома удаляются только при добавлении `--volumes`; это сбрасывает учебные базы и историю Airflow. Сценарий полного сброса, dbt lineage и проверки сбоя загрузки — в [гайде](docs/DWH_GUIDE.md).

## Если запуск не удался

| Сообщение или симптом | Действие |
|---|---|
| `Cannot connect to the Docker daemon` | Запусти Docker Desktop / Docker Engine и повтори `docker info` |
| В Ubuntu WSL нет команды `docker` | Включи интеграцию Ubuntu в настройках Docker Desktop; проверь WSL2 и режим Linux containers |
| `permission denied` для Docker socket на Linux | Настрой доступ к Docker или выполняй команды с `sudo` |
| `port is already allocated` | Освободи порты 8080, 5051, 5433 или скопируй `.env.example` в `.env` и задай свободные порты |
| Контейнер завершился с кодом 137 / `OOMKilled` | Выдели Docker/WSL больше памяти, закрой тяжёлые программы и повтори запуск |
| `Resource deadlock avoided` при чтении кода из контейнера на Mac | Такая ошибка наблюдалась у файлов, ещё не скачанных из облака. Полностью скачай папку проекта через Finder либо клонируй в локальный `~/projects` вне облачной синхронизации; перезапусти Docker/Colima. Если до этого упал seed источника, см. пояснение ниже |
| Долго скачиваются образы / ошибка сети | Проверь доступ к Docker Hub и PyPI; после восстановления сети повтори ту же команду запуска |
| `airflow-init` или `dwh-init` показывает `Exited (0)` | Это штатно: соответствующая одноразовая инициализация завершилась успешно |
| В базовом запуске нет Greenplum или источника | Добавь `--profile dwh` для всего DWH либо `--profile source` для одного источника |
| DAG на паузе | В базовом режиме это ожидаемо; профиль `dwh` включает его после готовности баз |

Если инициализация источника упала до загрузки данных, повторный `up` не гарантирует повтор seed: init SQL выполняется только на пустом томе. После исправления доступа к файлам для чистого учебного набора используй [осознанный сброс стенда](docs/DWH_GUIDE.md#10-перезапуск-и-диагностика); он удаляет его базы и историю Airflow.

Для предметной диагностики используй `docker compose logs --tail 100` и [раздел гайда](docs/DWH_GUIDE.md#10-перезапуск-и-диагностика).

**Проверено локально:** сборка и запуск контейнеров, автоматический DAG, 11 моделей и 72 dbt-теста в Greenplum, повторные загрузки, обновление данных и откат при сбое COPY. Подробности — в [отчёте проверки](docs/VALIDATION.md).
