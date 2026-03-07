# Закрытие внешнего доступа к админке (Maddy + ISPmanager)

Этот гайд ограничивает доступ к административным точкам:

- ISPmanager (`1500/tcp`) только с доверенных IP.
- SSH (`22/tcp`, через который управляется Maddy CLI) только с доверенных IP.

Ограничение делается на уровне firewall (`iptables`) с логированием отклоненных попыток.

## Что добавлено в репозиторий

- `scripts/maddy-admin-lockdown/playbook.toml`
- `scripts/maddy-admin-lockdown/inventory.example.toml`
- `scripts/maddy-admin-lockdown/trusted-ips.example.txt`

## Важно перед применением

Сначала добавьте ваш текущий IP/VPN CIDR в whitelist, только потом применяйте правила.

По умолчанию whitelist хранится в `/etc/cogni/admin-whitelist.txt` и копируется из шаблона `trusted-ips.example.txt` при первом запуске.

Playbook валидирует whitelist как `IPv4`/`IPv4 CIDR` и перед применением проверяет, что текущий `SSH`-клиент входит в whitelist (защита от самоблокировки).

## Запуск через spot

1. Подготовьте inventory:

```bash
cp scripts/maddy-admin-lockdown/inventory.example.toml inventory.toml
```

2. Отредактируйте `inventory.toml` под ваш сервер.

3. Отредактируйте whitelist-шаблон:

```bash
nano scripts/maddy-admin-lockdown/trusted-ips.example.txt
```

Добавьте туда office/VPN/admin диапазоны до первого запуска.

4. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-admin-lockdown/playbook.toml \
  -i inventory.toml \
  -t default
```

## Что делает playbook

- Делает backup текущих правил в `/root/iptables.backup.<timestamp>`.
- Создает/обновляет цепочки `COGNI_ISPMANAGER` и `COGNI_SSH`.
- Разрешает доступ к `1500/tcp` и `22/tcp` только для IP/CIDR из whitelist.
- Если запуск идет по SSH: проверяет, что текущий IP сессии есть в whitelist (если нет, прерывает применение).
- Логирует и блокирует неавторизованные попытки (`LOG` + `DROP`).
- Сохраняет firewall-правила (`netfilter-persistent save` или `/etc/iptables/rules.v4`).
- Усиливает права на файлы Maddy:
  - `/etc/maddy/maddy.conf` -> `640`
  - `/var/lib/maddy/auth.db` -> `660`

## Быстрое добавление IP в whitelist

1. Добавьте IP/CIDR строкой в `/etc/cogni/admin-whitelist.txt`.
2. Повторно выполните playbook (или только шаг `apply whitelist for ISPmanager and SSH`).

Если нужно принудительно применить правила без проверки текущего SSH IP (риск lockout), используйте `ALLOW_LOCKOUT_RISK=yes`.

## Проверка и приемка

- `AC-1`: с доверенного IP открывается ISPmanager (`:1500`) и SSH (`:22`).
- `AC-2`: с недоверенного IP соединение отклоняется.
- `AC-3`: в kernel/journald появляются записи с префиксами:
  - `COGNI ISP deny`
  - `COGNI SSH deny`
- `AC-4`: почта и веб не затронуты, так как правило применяется только к `1500` и `22`.
- `AC-5`: SSH доступен только доверенным IP.
- `AC-6`: права на конфиг/БД Maddy ограничены.

Проверка deny-логов:

```bash
journalctl -k --since "15 min ago" | grep -E 'COGNI (ISP|SSH) deny'
```

## Откат

```bash
iptables-restore < /root/iptables.backup.<timestamp>
```

После отката сохраните правила в persistent-хранилище вашей системы.
