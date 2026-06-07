# Добавление 5 доменов в ISPmanager (spot)

Этот гайд автоматизирует массовое добавление доменов в ISPmanager через API.

Сценарий закрывает задачи:

- вход в ISPmanager API по адресу панели;
- создание WWW-доменов;
- проверка, что домены созданы и SSL не выключен.

## Что добавлено в репозиторий

- `scripts/ispmanager-add-domains/playbook.toml`
- `scripts/ispmanager-add-domains/inventory.example.toml`
- `scripts/ispmanager-add-domains/ispmanager-domains.example.env`

## Подготовка

1. Скопируйте inventory:

```bash
cp scripts/ispmanager-add-domains/inventory.example.toml inventory.toml
```

2. Отредактируйте `inventory.toml` под сервер ISPmanager.

3. Подготовьте env-файл с доменами и доступами:

```bash
cp scripts/ispmanager-add-domains/ispmanager-domains.example.env ispmanager-domains.env
```

Заполните минимум эти поля:

- `ISPM_API_URL`
- `ISPM_USER`
- `ISPM_PASSWORD`
- `DOMAINS` (5 доменов через пробел)

Пример:

```bash
DOMAINS="domain1.tld domain2.tld domain3.tld domain4.tld domain5.tld"
```

4. Загрузите заполненный env-файл на сервер:

```bash
scp ispmanager-domains.env root@<server-ip>:/etc/ocawe/ispmanager-domains.env
```

## Запуск через spot

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/ispmanager-add-domains/playbook.toml \
  -i inventory.toml \
  -t default
```

По умолчанию playbook использует env-файл `/etc/ocawe/ispmanager-domains.env` на удаленном хосте.

## Что делает playbook

- Создает `/etc/ocawe` при необходимости.
- Кладет шаблон env-файла в `/etc/ocawe/ispmanager-domains.env` (без перезаписи).
- Проверяет доступ к API ISPmanager.
- Добавляет каждый домен через API (с fallback между `site.edit`, `webdomain.edit`, `wwwdomain.edit` для совместимости версий).
- Проверяет, что домены доступны через API и SSL не отключен.
- Опционально проверяет HTTPS (`VERIFY_HTTPS=yes`).

## Критерии приемки

- `AC-1`: все 5 доменов присутствуют в списке WWW-доменов.
- `AC-2`: для всех доменов SSL не отключен (и при `ENABLE_LETSENCRYPT=yes` инициирован выпуск LE-сертификатов).
- `AC-3`: при `VERIFY_HTTPS=yes` домены отвечают по HTTPS.

## Частые проблемы

- Неверный API путь: попробуйте `https://<ip>:1500/ispmgr.cgi` вместо `/ispmgr`.
- Невалидный TLS панели: оставьте `ISPM_INSECURE_TLS="yes"`.
- Домены не открываются по HTTPS сразу: дождитесь выпуска сертификатов и DNS propagation, затем повторите шаг проверки.
