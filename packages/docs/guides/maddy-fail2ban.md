# Fail2Ban против брутфорса для Maddy, ISPmanager и Roundcube

Этот гайд настраивает Fail2Ban для:

- SMTP (Maddy)
- IMAP (Maddy)
- ISPmanager
- Roundcube

Цель: блокировать IP при серии неуспешных авторизаций и автоматически снимать бан через заданное время.

## Что добавлено в репозиторий

- `scripts/maddy-fail2ban/playbook.toml`
- `scripts/maddy-fail2ban/inventory.example.toml`
- `scripts/maddy-fail2ban/maddy.conf`
- `scripts/maddy-fail2ban/maddy-smtp.conf`
- `scripts/maddy-fail2ban/maddy-imap.conf`
- `scripts/maddy-fail2ban/ispmanager.conf`
- `scripts/maddy-fail2ban/ispmanager-auth.conf`
- `scripts/maddy-fail2ban/webmail.conf`
- `scripts/maddy-fail2ban/roundcube-auth.conf`
- `scripts/maddy-fail2ban/jail.local`

## Предпосылки

- Maddy Mail Server установлен.
- Логи Maddy пишутся в `/var/log/maddy/maddy.log`.
- ISPmanager установлен (лог обычно `/usr/local/mgr5/var/ispmgr.log`).
- Roundcube установлен (лог обычно `/var/log/roundcube/errors.log` или `/var/log/roundcubemail/errors.log`).

## Запуск через spot

1. Подготовьте inventory:

```bash
cp scripts/maddy-fail2ban/inventory.example.toml inventory.toml
```

2. Отредактируйте `inventory.toml` под ваш хост.

3. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-fail2ban/playbook.toml \
  -i inventory.toml \
  -t default
```

## Ручная проверка

```bash
fail2ban-client status
fail2ban-client status maddy-smtp
fail2ban-client status maddy-imap
fail2ban-client status ispmanager
fail2ban-client status roundcube
tail -f /var/log/fail2ban.log
```

## Валидация regex до запуска в прод

Проверьте фильтры на реальных логах:

```bash
fail2ban-regex /var/log/maddy/maddy.log /etc/fail2ban/filter.d/maddy-smtp.conf
fail2ban-regex /var/log/maddy/maddy.log /etc/fail2ban/filter.d/maddy-imap.conf
fail2ban-regex /usr/local/mgr5/var/ispmgr.log /etc/fail2ban/filter.d/ispmanager-auth.conf
fail2ban-regex /var/log/roundcube/errors.log /etc/fail2ban/filter.d/roundcube-auth.conf
```

Если по ISPmanager совпадений нет, адаптируйте `failregex` в `ispmanager-auth.conf` под ваш формат строк.

## Параметры безопасности и тюнинг

- Порог Maddy: `maxretry = 3`, `findtime = 600`.
- Базовый `bantime = 3600` (1 час).
- Для ISPmanager установлен `bantime = 7200`.
- Доверенные IP задаются в `jail.local` через `ignoreip`.
- Диапазон блокировки 1-24 часа задается через `bantime` (например `3600`..`86400`).

Все блокировки пишутся в `/var/log/fail2ban.log`.

## Критерии приемки

- `AC-1`: сервис Fail2Ban активен (`systemctl status fail2ban`).
- `AC-2`: jail `maddy-smtp` активен.
- `AC-3`: jail `maddy-imap` активен.
- `AC-4`: jail `ispmanager` активен.
- `AC-5`: после 3 неуспешных логинов IP попадает в бан.
- `AC-6`: адреса из `ignoreip` не блокируются.
- `AC-7`: события банов пишутся в `/var/log/fail2ban.log`.
