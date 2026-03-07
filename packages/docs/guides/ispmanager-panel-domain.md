# Привязка домена к панели ISPmanager (опционально)

Этот гайд закрывает `PRD-02`: доступ к панели ISPmanager через доменное имя вместо IP.

## Что добавлено в репозиторий

- `scripts/ispmanager-panel-domain/playbook.toml`
- `scripts/ispmanager-panel-domain/inventory.example.toml`
- `scripts/ispmanager-panel-domain/panel-domain.example.env`

## Важные уточнения

- DNS A-запись для `panel.domain1.tld` обычно создается у внешнего DNS-провайдера, а не через локальный `bind9` на mail-сервере.
- Для HTTPS в панели нужен сертификат, выпущенный для домена панели.
- Согласно документации ISPmanager, адрес панели и сертификат настраиваются в UI:
  - `Settings -> Control panel addresses`
  - выпуск Let's Encrypt сертификата для адреса панели

## Предпосылки

- ISPmanager установлен и доступен на сервере (обычно `:1500`).
- Вы выбрали поддомен панели (`panel.domain1.tld` или `admin.domain1.tld`).
- Домен уже делегирован и DNS-зона управляется у провайдера.

## Быстрый старт (spot)

1. Подготовьте inventory:

```bash
cp scripts/ispmanager-panel-domain/inventory.example.toml inventory.toml
```

2. Подготовьте env:

```bash
cp scripts/ispmanager-panel-domain/panel-domain.example.env /tmp/ispmanager-panel-domain.env
# Отредактируйте /tmp/ispmanager-panel-domain.env
```

3. Скопируйте env на сервер:

```bash
scp /tmp/ispmanager-panel-domain.env root@<server-ip>:/etc/cogni/ispmanager-panel-domain.env
```

Или создайте `/etc/cogni/ispmanager-panel-domain.env` вручную.

4. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/ispmanager-panel-domain/playbook.toml \
  -i inventory.toml \
  -t default
```

## Что делает playbook

- Проверяет корректность входных параметров (`PANEL_DOMAIN`, `PANEL_IP`, `PANEL_PORT`).
- Проверяет DNS A-запись для домена панели.
- Проверяет, что панель отвечает по домену (через `curl --resolve`).
- Считывает и анализирует TLS-сертификат (subject/issuer/SAN/notAfter).
- Проверяет trust-валидность сертификата (если `STRICT_TLS_VALID=yes`).
- Проверяет, что резервный доступ по IP сохранен (`AC-3`).
- Печатает финальные шаги в UI ISPmanager.

## Ручные шаги в ISPmanager

1. Откройте `Settings -> Control panel addresses`.
2. Добавьте адрес панели: `panel.domain1.tld`.
3. Выпустите сертификат Let's Encrypt для этого адреса.
4. Проверьте доступ: `https://panel.domain1.tld:1500`.
5. Опционально включите запрет HTTP (после успешной проверки HTTPS).

## Acceptance Checklist

- `AC-1` Панель открывается по доменному имени.
- `AC-2` Сертификат валиден и выдан для домена панели.
- `AC-3` Доступ по IP остается рабочим как fallback.

## Риски и митигация

- Задержка DNS propagation:
  - используйте проверку `curl --resolve` и/или локальный hosts для precheck.
- Ошибочный сертификат (не тот SAN):
  - playbook валидирует SAN и доверенность сертификата.
- Недоступность fallback по IP:
  - playbook проверяет IP-доступ и может фейлить по `STRICT_IP_FALLBACK=yes`.

## Полезные проверки

```bash
dig +short A panel.domain1.tld
curl -I https://panel.domain1.tld:1500
openssl s_client -connect panel.domain1.tld:1500 -servername panel.domain1.tld </dev/null | openssl x509 -noout -subject -issuer -dates
```
