# SMTP для принтеров и МФУ через Maddy

Этот гайд закрывает `PRD-10`: настройка `Scan to Email` через локальный Maddy SMTP.

## Входные данные

- Список принтеров/МФУ с SMTP.
- IP-адреса или hostname устройств.
- Доступ к внутренней сети организации.
- Установленный и работающий Maddy Mail Server.

## Требования

Функциональные:
- `FR-1` Принтеры могут отправлять почту через локальный SMTP.
- `FR-2` Поддерживается auth-сценарий или IP-based доступ для legacy.
- `FR-3` Поддерживается `STARTTLS` и plaintext для старых устройств.
- `FR-4` Опционально ограничивается отправка только внутренним адресатам.

Нефункциональные:
- `NFR-1` Совместимость со старыми устройствами без TLS/auth.
- `NFR-2` Минимальная задержка отправки (целевой SLA: до 10 секунд в LAN).
- `NFR-3` Логирование отправок и ошибок через `journalctl -u maddy`.

## Важные ограничения Maddy

- Endpoint `submission` в Maddy всегда требует аутентификацию.
- Для устройств без auth/TLS используйте отдельный endpoint `smtp`.
- Listener `127.0.0.1:2525` не подходит для принтеров в сети, нужен bind на LAN IP.

## Вариант A (рекомендуется): AUTH + STARTTLS

Создайте отдельную учётку для принтеров:

```bash
sudo -u maddy maddy creds create printer@domain1.tld
```

Параметры на принтере:

- SMTP Server: `mail.domain1.tld`
- Port: `587`
- Authentication: `Enabled`
- Username: `printer@domain1.tld`
- Password: `<password>`
- STARTTLS/TLS: `Enabled`
- From Address: `printer@domain1.tld`

## Вариант B: legacy-устройства без AUTH/TLS

Добавьте отдельный endpoint `smtp` на `2525` и ограничьте доступ по сети/фаерволу.

```conf
# Если submission :587 уже есть в базовом maddy.conf, не дублируйте его.
# Добавьте только legacy endpoint ниже.
smtp tcp://192.168.1.10:2525 {
    hostname mail.domain1.tld

    destination $(local_domains) {
        deliver_to &local_routing
    }
    default_destination {
        reject
    }
}
```

Примечание: snippet предполагает, что в основном `maddy.conf` уже есть `&local_routing` и `$(local_domains)` из базовой конфигурации.

## Вариант C: только внутренние адресаты (опционально)

Оставьте `default_destination { reject }` на legacy endpoint. Тогда принтер сможет отправлять только в локальные домены из `$(local_domains)`, а внешние получатели будут отклоняться.

## Firewall

- Разрешайте `587/tcp` и `2525/tcp` только из подсети принтеров (например `192.168.1.0/24`).
- Не открывайте `2525/tcp` во внешнюю сеть.

## Проверка

Проверка STARTTLS на `587`:

```bash
openssl s_client -starttls smtp -connect mail.domain1.tld:587 -crlf
```

Проверка legacy-порта `2525`:

```bash
nc -vz mail.domain1.tld 2525
```

Логи Maddy:

```bash
journalctl -u maddy -f
```

## Критерии приёмки

| № | Критерий | Статус |
|---|----------|--------|
| AC-1 | Принтер устанавливает SMTP-соединение с Maddy | ☐ |
| AC-2 | Тестовое письмо отправляется успешно | ☐ |
| AC-3 | Письмо получено адресатом | ☐ |
| AC-4 | В логах Maddy нет ошибок auth/TLS для выбранного режима | ☐ |
| AC-5 | Scan-to-Email стабильно работает | ☐ |

## Автоматизация через spot

Готовые шаблоны в репозитории:

- `scripts/maddy-printers/playbook.toml`
- `scripts/maddy-printers/inventory.example.toml`
- `scripts/maddy-printers/maddy-printers.conf.example`

Поддерживаемые переменные для playbook:

- `MAIL_HOSTNAME` (по умолчанию `mail.domain1.tld`)
- `LAN_BIND_ADDR` (по умолчанию `192.168.1.10`)
- `PRINTERS_CIDR` (по умолчанию `192.168.1.0/24`)

Запуск:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-printers/playbook.toml \
  -i scripts/maddy-printers/inventory.example.toml \
  -t default
```

После выполнения playbook добавьте учётку принтера вручную:

```bash
sudo -u maddy maddy creds create printer@domain1.tld
```

## Риски и митигация

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| Старое устройство без TLS/auth | Высокая | Отдельный `smtp` listener на `2525` + ACL/firewall |
| Блокировка фаерволом | Средняя | Явно разрешить `587/2525` для `PRINTERS_CIDR` |
| Отправка наружу с legacy устройств | Средняя | `default_destination { reject }` на legacy endpoint |
| Ошибки на принтере из-за неправильного From | Средняя | Использовать выделенный `printer@domain1.tld` |
