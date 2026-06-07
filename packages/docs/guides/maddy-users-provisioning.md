# Массовое создание пользователей в Maddy (PRD-05)

Этот гайд закрывает `PRD-05`: создание почтовых пользователей в Maddy из CSV с автогенерацией/заданием паролей, проверками и применением квот.

## Что добавлено в репозиторий

- `scripts/maddy-users/playbook.toml`
- `scripts/maddy-users/import-users.sh`
- `scripts/maddy-users/maddy-users.env.example`
- `scripts/maddy-users/users.example.csv`
- `scripts/maddy-users/inventory.example.toml`

## Важное уточнение по квоте

В Maddy штатная per-user настройка через CLI - это `imap-acct appendlimit` (максимальный размер сообщения для IMAP APPEND), а не общий размер почтового ящика.

В этом сценарии поле `Quota` из CSV маппится на `APPENDLIMIT` в байтах.

## Предпосылки

- Maddy установлен и работает.
- Есть доступ root по SSH к mail-серверу.
- Подготовлен CSV с колонками: `Email,Domain,Password,Quota`.
- Значения `Password`:
  - пусто или `auto` -> пароль генерируется автоматически;
  - явное значение -> используется как есть (минимум 12 символов).

## Формат CSV

Пример:

```csv
Email,Domain,Password,Quota
user1@domain1.tld,domain1.tld,auto,1GB
user2@domain1.tld,domain1.tld,,512MB
user3@domain2.tld,domain2.tld,StrongPassw0rd!,2GB
```

Поддерживаемые форматы `Quota`: `1GB`, `512MB`, `1048576`, `-1`/`none`.

## Быстрый старт (spot)

1. Подготовьте inventory:

```bash
cp scripts/maddy-users/inventory.example.toml inventory.toml
```

2. Подготовьте env:

```bash
cp scripts/maddy-users/maddy-users.env.example /tmp/maddy-users.env
# Отредактируйте /tmp/maddy-users.env
```

3. Подготовьте CSV:

```bash
cp scripts/maddy-users/users.example.csv /tmp/maddy-users.csv
# Отредактируйте /tmp/maddy-users.csv
```

4. Скопируйте файлы на сервер:

```bash
scp /tmp/maddy-users.env root@<mail-server>:/etc/ocawe/maddy-users.env
scp /tmp/maddy-users.csv root@<mail-server>:/etc/ocawe/maddy-users.csv
```

5. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-users/playbook.toml \
  -i inventory.toml \
  -t default
```

## Что делает импорт

- Валидирует CSV (дубликаты, формат email, совпадение `Email`/`Domain`).
- Создаёт credentials: `maddy creds create`.
- Создаёт IMAP storage account: `maddy imap-acct create`.
- Применяет quota как `maddy imap-acct appendlimit --value <bytes>`.
- Экспортирует созданные/обновлённые пароли в зашифрованный файл (`AES-256-CBC`, `PBKDF2`).

## Настройка поведения

Через `maddy-users.env`:

- `ON_EXISTING=skip|update|fail` - как обрабатывать уже существующие credentials.
- `BCRYPT_COST` - cost bcrypt для новых учёток.
- `DEFAULT_QUOTA` - квота по умолчанию при пустом поле в CSV.
- `ALLOW_SKIP_QUOTA=yes|no` - продолжать ли импорт, если appendlimit не применился.
- `ENCRYPT_PASSWORD_EXPORT=yes|no` и `MADDY_USERS_MASTER_KEY` - политика хранения паролей.

## Ручной режим (до 20 пользователей)

Используйте актуальные команды Maddy CLI:

```bash
maddy creds create user1@domain1.tld
maddy imap-acct create user1@domain1.tld
maddy imap-acct appendlimit --value 1073741824 user1@domain1.tld
```

## Acceptance Checklist

- `AC-1` Все пользователи из CSV присутствуют в `maddy creds list` и `maddy imap-acct list`.
- `AC-2` Пароли сохранены в encrypted export-файле и переданы пользователям по защищённому каналу.
- `AC-3` Для пользователей с `Quota` применён `APPENDLIMIT`.
- `AC-4` Проверен тестовый вход 2-3 пользователей по IMAP/SMTP AUTH.

## Риски

- Ошибки в CSV (формат, дубликаты, неверный домен) блокируют импорт.
- `APPENDLIMIT` не равен total mailbox quota.
- Если `ON_EXISTING=skip`, переданный в CSV пароль для существующего аккаунта будет проигнорирован.
