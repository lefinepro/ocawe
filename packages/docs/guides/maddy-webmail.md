# Веб-почта для Maddy через Roundcube (5 доменов)

Этот гайд закрывает `PRD-03`: веб-доступ к почте через Roundcube для доменов на Maddy.

## Что добавлено в репозиторий

- `scripts/maddy-webmail/playbook.toml`
- `scripts/maddy-webmail/inventory.example.toml`
- `scripts/maddy-webmail/webmail.example.env`
- `scripts/maddy-webmail/roundcube-maddy.inc.php.example`

## Что делает playbook

- Устанавливает Roundcube, nginx, php-fpm и certbot.
- Настраивает Roundcube на Maddy:
  - IMAP: `ssl://127.0.0.1:993`
  - SMTP submission: `tls://127.0.0.1:587`
- Создает nginx vhost для `webmail.<domain>` на каждый домен из `DOMAINS`.
- Выпускает TLS-сертификаты Let's Encrypt и включает HTTP -> HTTPS редирект.
- Проверяет доступность `https://webmail.<domain>`.
- Опционально настраивает `domain.tld/webmail -> webmail.domain.tld` через ISPmanager API.

## Предпосылки

- 5 доменов уже добавлены в ISPmanager.
- Maddy установлен и слушает порты `993` и `587`.
- DNS `A/AAAA` для `webmail.<domain>` указывает на ваш сервер.
- Порт `80/tcp` и `443/tcp` открыт извне (для Let's Encrypt и доступа).

## Быстрый старт (spot)

1. Подготовьте inventory:

```bash
cp scripts/maddy-webmail/inventory.example.toml inventory.toml
```

2. Подготовьте env:

```bash
cp scripts/maddy-webmail/webmail.example.env /tmp/maddy-webmail.env
# Отредактируйте /tmp/maddy-webmail.env
```

3. Скопируйте env на сервер (или создайте файл вручную):

```bash
scp /tmp/maddy-webmail.env root@<server>:/etc/ocawe/maddy-webmail.env
```

4. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-webmail/playbook.toml \
  -i inventory.toml \
  -t default
```

## Важные переменные env

- `DOMAINS="domain1.tld domain2.tld ..."`
- `LETSENCRYPT_EMAIL="admin@domain1.tld"`
- `ISSUE_CERTS="yes"` (по умолчанию)
- `IMAP_HOST`, `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS`
- `PHP_FPM_SOCK` (опционально, если авто-детект сокета не сработал)

Для FR-3 (редирект `/webmail`):

- `ENABLE_ISPMANAGER_REDIRECT="yes"`
- `ISPMGR_API_URL`, `ISPMGR_USER`, `ISPMGR_PASS`

## Проверка и приемка

- `AC-1..AC-5`: `https://webmail.domainN.tld` открывается для всех 5 доменов.
- `AC-6`: `http://webmail.domainN.tld` редиректит на HTTPS.
- `AC-7`: логин в Roundcube проходит учеткой Maddy.
- `AC-8`: отправка и получение писем из веб-интерфейса работают.

Проверка HTTP-кодов:

```bash
for d in domain1.tld domain2.tld domain3.tld domain4.tld domain5.tld; do
  echo "=== $d"
  curl -I "http://webmail.$d" | head -n1
  curl -k -I "https://webmail.$d" | head -n1
done
```

## FR/NFR покрытие

- `FR-1`: webmail на `webmail.domain.tld`.
- `FR-2`: IMAP 993 и SMTP 587 в конфиге Roundcube.
- `FR-3`: автоматизируется через ISPmanager API (опционально).
- `FR-4`: certbot для всех `webmail.<domain>`.
- `NFR-3`: принудительный HTTPS через certbot `--redirect`.

`NFR-1` (загрузка < 3 сек) и `NFR-2` (браузеры) проверяются уже эксплуатационными тестами после деплоя.

## Откат

1. Отключить vhost webmail в nginx (`/etc/nginx/sites-enabled/webmail.*.conf`).
2. Восстановить backup Roundcube-конфига `config.inc.php.bak.<timestamp>`.
3. Перезагрузить nginx/php-fpm.
4. При необходимости удалить certbot-конфиги и сертификаты для `webmail.<domain>`.
