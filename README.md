# Airflow + Postgres + Dbt

## Архитектура

Postgres:

    client-postgres — «клиентская» БД с таблицами users и т.д.

    warehouse-postgres — «витрина/хранилище» при необходимости.

Airflow:

    webserver, scheduler, worker, Flower.

    DAG-и для загрузки данных и запуска dbt.

dbt:

    отдельный контейнер с проектом в каталоге ./dbt_project.

    запускается из Airflow через BashOperator.

## Запуск

    git@github.com:DE-Infrastructure/localstand_guide_de.git
    cd localstand_guide_de

1. Настроить .env с AIRFLOW_UID

Для запуска Airflow нужен UID текущего пользователя, его надо записать в файл .env в корне репозитория.
На Linux UID можно получить так: 

```sh
id -u
```

Пример .env:

```text
AIRFLOW_UID=1000
```
(подставь свой UID.)


2. Поднять все сервисы

```sh
docker-compose up
```

### Веб интерфейсы

*   [Airflow](http://localhost:8080)

### Доступные с хоста сервисы:

*   client-postgres: [localhost:5051](\[localhost:5051])

## Параметры подключения к БД в Airflow:

```text
host: client-postgres
port: 5432
database: postgres
user: postgres
password: postgres
```
## Параметры подключения к БД в Dbeaver:

```text
host: localhost
port: 5051
database: postgres
user: postgres
password: postgres
```