# Autodiscover/Autoconfig для почтовых клиентов через Maddy

Этот гайд закрывает `PRD-04`: автоматическая настройка клиентов (Outlook, Thunderbird, iOS/Android Mail) для 5 доменов с почтой в Maddy.

## Что добавлено в репозиторий

- `scripts/maddy-autodiscover/playbook.toml`
- `scripts/maddy-autodiscover/inventory.example.toml`
- `scripts/maddy-autodiscover/autodiscover.example.env`

## Важное уточнение по архитектуре

В текущем Maddy нет отдельного встроенного HTTP-модуля для выдачи `autodiscover.xml`, `config-v1.1.xml` и `mail.mobileconfig`.

Поэтому playbook делает совместимый слой рядом с Maddy:

- генерирует файлы Autodiscover/Autoconfig/MobileConfig по каждому домену,
- генерирует Nginx-конфиг для `autodiscover.<domain>` и `autoconfig.<domain>`,
- оставляет Maddy источником истины для IMAP/SMTP.

## Предпосылки

- Maddy установлен и работает.
- SSL-сертификат покрывает все имена:
  - `autodiscover.domain1.tld ... autodiscover.domain5.tld`
  - `autoconfig.domain1.tld ... autoconfig.domain5.tld`
- Есть IP/CNAME, куда будут указывать DNS записи autodiscover/autoconfig.

## Быстрый старт (spot)

1. Подготовьте inventory:

```bash
cp scripts/maddy-autodiscover/inventory.example.toml inventory.toml
```

2. Подготовьте env:

```bash
cp scripts/maddy-autodiscover/autodiscover.example.env /tmp/maddy-autodiscover.env
# Отредактируйте /tmp/maddy-autodiscover.env
```

3. Скопируйте env на сервер (или создайте `/etc/ocawe/maddy-autodiscover.env` вручную).

4. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-autodiscover/playbook.toml \
  -i inventory.toml \
  -t default
```

Playbook:

- рендерит endpoint-файлы в `/var/www/ocawe-autodiscover/<domain>/...`,
- рендерит Nginx vhost в `/etc/ocawe/maddy-autodiscover.nginx.conf`,
- рендерит DNS-подсказки в `/etc/ocawe/maddy-autodiscover-dns.generated.txt`,
- проверяет локально ответы endpoint’ов через `curl --resolve`.

По умолчанию авто-применение Nginx выключено (`APPLY_NGINX_CONFIG="no"`).

## Как включить Nginx-конфиг

1. Убедитесь, что в env корректно заданы:

- `TLS_CERT_PATH`
- `TLS_KEY_PATH`
- `NGINX_CONF_DEST` (по умолчанию `/etc/nginx/conf.d/ocawe-autodiscover.conf`)

2. Поставьте:

```bash
APPLY_NGINX_CONFIG="yes"
```

3. Повторно запустите playbook.

Он выполнит `nginx -t` и `reload`.

## Root domain `.well-known` (опционально)

Если нужен именно путь `https://domain.tld/.well-known/...`,
playbook генерирует snippet’ы в `/etc/ocawe/maddy-root-domain-snippets/*.conf`.

Их нужно вручную включить в существующие vhost’ы `domain.tld`, чтобы не ломать текущий сайт.

## Валидация

Проверка Outlook endpoint:

```bash
curl -k https://autodiscover.domain1.tld/autodiscover/autodiscover.xml
```

Проверка Thunderbird endpoint:

```bash
curl -k https://autoconfig.domain1.tld/mail/config-v1.1.xml
```

Проверка mobile profile:

```bash
curl -k https://autodiscover.domain1.tld/mail.mobileconfig
```

Проверка NFR по времени ответа (<500ms):

```bash
curl -k -o /dev/null -s -w 'time_total=%{time_total}\n' \
  https://autodiscover.domain1.tld/autodiscover/autodiscover.xml
```

## Логирование

Для каждого домена создаются отдельные логи Nginx:

- `/var/log/nginx/autodiscover-<domain>.access.log`
- `/var/log/nginx/autodiscover-<domain>.error.log`
- `/var/log/nginx/autoconfig-<domain>.access.log`
- `/var/log/nginx/autoconfig-<domain>.error.log`

Это закрывает требование по логированию всех запросов discovery-слоя.

## Acceptance Checklist

- `AC-1` Outlook автоматически находит настройки через `autodiscover.<domain>`.
- `AC-2` iOS Mail настраивается через `mail.mobileconfig`/autodiscover endpoint.
- `AC-3` Android Mail получает корректные IMAP/SMTP параметры.
- `AC-4` Thunderbird забирает `config-v1.1.xml`.
- `AC-5` Gmail (IMAP/SMTP) работает с теми же параметрами.
- `AC-6` SSL-сертификат не вызывает предупреждений.
- `AC-7` Все 5 доменов отдают независимые настройки.

## Риски

- Неполный SAN в сертификате для `autodiscover.*`/`autoconfig.*`.
- Корпоративные firewall/proxy могут блокировать endpoint’ы.
- Для некоторых клиентов потребуется включить root-domain `.well-known` в основном vhost.

## Ссылки

- Maddy docs: https://maddy.email/docs/configuration/
- Maddy setup tutorial: https://maddy.email/docs/tutorials/setting-up/
- Thunderbird autoconfig format: https://wiki.mozilla.org/Thunderbird:Autoconfiguration:ConfigFileFormat
