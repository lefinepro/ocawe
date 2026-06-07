# Доставляемость почты в Maddy (SPF/DKIM/DMARC/PTR/rDNS)

Этот гайд реализует `PRD-07`: базовая настройка доставляемости почты для нескольких доменов на одном Maddy-сервере.

## Что добавлено в репозиторий

- `scripts/maddy-deliverability/playbook.toml`
- `scripts/maddy-deliverability/inventory.example.toml`
- `scripts/maddy-deliverability/dns-records.example.env`
- `scripts/maddy-deliverability/maddy-deliverability.conf.example`

## Важные уточнения по Maddy

- Для исходящей DKIM в актуальном Maddy используется `modify.dkim`.
- DKIM-ключи генерируются автоматически в `state_directory/dkim_keys` после загрузки `modify.dkim`.
- Для антиспама используйте `check.dnsbl` в SMTP `check` pipeline.
- Лимиты задаются через `limits { ... }` в SMTP endpoint, а не через отдельный `rate_limit {}` блок.
- Встроенного `greylist {}` блока в Maddy нет (обычно делают через внешние фильтры, например Rspamd).

## Предпосылки

- Maddy установлен и работает.
- Есть доступ к DNS-провайдерам всех доменов.
- Есть доступ к провайдеру/VPS для настройки PTR (reverse DNS).

## Быстрый старт (spot)

1. Подготовьте inventory:

```bash
cp scripts/maddy-deliverability/inventory.example.toml inventory.toml
```

2. Подготовьте переменные DNS/доменов:

```bash
cp scripts/maddy-deliverability/dns-records.example.env /tmp/maddy-deliverability.env
# Отредактируйте /tmp/maddy-deliverability.env
```

3. Скопируйте env на сервер (или создайте `/etc/ocawe/maddy-deliverability.env` вручную).

4. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-deliverability/playbook.toml \
  -i inventory.toml \
  -t default
```

Playbook:
- делает backup `/etc/maddy/maddy.conf`,
- рендерит snippet `check.dnsbl` + `modify.dkim` в `/etc/ocawe/maddy-deliverability.rendered.conf`,
- генерирует DNS-план в `/etc/ocawe/maddy-dns-records.generated.txt`,
- поддерживает общий SPF (`SPF_IPV4`) и точечный per-domain SPF (`DOMAIN_SPF_IPV4_MAP`),
- поддерживает PTR для каждого IP через `PTR_HOSTS`,
- проверяет опубликованные SPF/DKIM/DMARC/PTR через `dig`.

## Как включить snippet в `maddy.conf`

По умолчанию auto-append выключен (`APPLY_MADDY_SNIPPET="no"`).

- Рекомендуемо: вручную объединить `/etc/ocawe/maddy-deliverability.rendered.conf` с вашим `maddy.conf`.
- Опционально: поставить `APPLY_MADDY_SNIPPET="yes"` в env для автоматического append.

После merge убедитесь, что в endpoint `smtp tcp://...:25` есть:

```conf
dmarc yes

check {
    spf
    dkim
    dnsbl &cogni_dnsblocawe_dnsbl
}

limits {
    all rate 20
    ip rate 10
    endpoint concurrency 200
}
```

И в исходящем пути (обычно `submission` / `default_source`) есть:

```conf
modify {
    dkim &cogni_dkimocawe_dkim
}
```

## DNS и rDNS

Для каждого домена должны быть:

- SPF: TXT `v=spf1 mx ip4:... -all`
- DKIM: TXT `<selector>._domainkey.<domain>` (из `dkim_keys/*.dns`)
- DMARC: TXT `_dmarc.<domain>`

В `dns-records.example.env` можно выбрать один из режимов SPF:

- `SPF_IPV4`: один общий набор IP для всех доменов.
- `DOMAIN_SPF_IPV4_MAP`: отдельный набор IP для каждого домена (`domain=ip1,ip2`).

Для каждого исходящего SMTP IP:

- PTR: `IP -> mail.<domain>`
- A/AAAA: `mail.<domain> -> IP`
- Прямой и обратный DNS должны совпадать (FCrDNS).

Для проверки PTR сразу по всем IP используйте `PTR_HOSTS="ip=hostname ip=hostname ..."`.

## Валидация

Проверка с сервера:

```bash
dig +short TXT domain1.tld
dig +short TXT maddy._domainkey.domain1.tld
dig +short TXT _dmarc.domain1.tld
dig +short -x 203.0.113.10
```

Внешняя проверка:

- https://mxtoolbox.com/
- https://www.mail-tester.com/

Почтовые тесты:

- отправка в Gmail (Inbox, не Spam)
- отправка в Outlook (Inbox/Junk signal)
- отправка в Yandex

## Чеклист приёмки

- `AC-1` SPF валиден для всех 5 доменов.
- `AC-2` DKIM подписывает исходящую почту (`Authentication-Results` показывает `dkim=pass`).
- `AC-3` DMARC запись опубликована для всех доменов.
- `AC-4` PTR/rDNS настроен для каждого SMTP IP.
- `AC-5` Mail-Tester score >= 9/10.
- `AC-6` MXToolbox не показывает критичных ошибок.
- `AC-7` Gmail не отправляет тестовые письма в spam.
- `AC-8` Outlook не отправляет тестовые письма в spam.

## Рекомендация rollout по DMARC

1. Недели 1-2: `p=none` (сбор отчётов).
2. Недели 3-4: `p=quarantine`.
3. После стабилизации: `p=reject`.
