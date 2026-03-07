# Массовое создание пользователей в Maddy

Этот гайд закрывает задачу массового создания почтовых аккаунтов из CSV.

## Что добавлено в репозиторий

- `scripts/maddy-users/playbook.toml`
- `scripts/maddy-users/import-users.sh`
- `scripts/maddy-users/inventory.example.toml`
- `scripts/maddy-users/users.example.csv`

## Поддерживаемые требования

- Создание credentials для каждого email (`maddy creds create`).
- Создание IMAP account (`maddy imap-acct create`).
- Пароль из CSV или автогенерация.
- Политика минимальной длины пароля (`>= 12`, настраивается).
- Проверка дубликатов и соответствия `email <-> domain`.
- Сохранение отчета с паролями в plaintext и/или AES-256 encrypted файл.

## Важно про квоты

В playbook поле `Quota` применяется как `APPENDLIMIT` через:

```bash
maddy imap-acct appendlimit --value <bytes> <email>
```

Это лимит размера сообщений для IMAP APPEND, а не полноценная дисковая квота mailbox storage.

## Формат CSV

```csv
Email,Domain,Password,Quota
user1@domain1.tld,domain1.tld,auto,1GB
user2@domain1.tld,domain1.tld,VeryStrongPassw0rd!,2GB
user3@domain2.tld,domain2.tld,,500MB
```

- `Password`:
  - `auto` или пусто -> автогенерация.
  - иначе используется значение из CSV.
- `Quota`:
  - поддерживаются `KB`, `MB`, `GB`, `TB` (и `KiB/MiB/GiB/TiB`).

## Подготовка

1. Скопируйте inventory:

```bash
cp scripts/maddy-users/inventory.example.toml inventory.toml
```

2. Отредактируйте `inventory.toml` под сервер.

3. Загрузите ваш CSV на сервер, например в `/tmp/users.csv`.

4. Создайте ключ для шифрования отчета:

```bash
openssl rand -base64 48 > /root/.maddy-password-master.key
chmod 600 /root/.maddy-password-master.key
```

## Запуск через spot

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  -e PASSWORDS_MASTER_KEY_FILE=/root/.maddy-password-master.key \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-users/playbook.toml \
  -i inventory.toml \
  -t default
```

По умолчанию playbook ждёт CSV на удалённом хосте в `/tmp/users.csv`.

## Переменные окружения

- `USERS_CSV` (default: `/tmp/users.csv`)
- `MIN_PASSWORD_LEN` (default: `12`)
- `PASSWORD_LENGTH` (default: `20`)
- `STRICT_DOMAIN_MATCH` (`yes|no`, default: `yes`)
- `APPLY_APPENDLIMIT` (`yes|no`, default: `yes`)
- `SKIP_EXISTING` (`yes|no`, default: `yes`)
- `UPDATE_PASSWORD_FOR_EXISTING` (`yes|no`, default: `no`)
- `PASSWORDS_PLAINTEXT_PATH` (default: `/root/mail_passwords.txt`, empty to disable)
- `PASSWORDS_ENCRYPTED_PATH` (default: `/root/mail_passwords.enc`, empty to disable)
- `PASSWORDS_MASTER_KEY_FILE` или `PASSWORDS_MASTER_KEY`

## Проверка

Плейбук включает автоматическую проверку:

- каждый email из CSV существует в `creds list`;
- каждый email из CSV существует в `imap-acct list`.

Дополнительно вручную:

```bash
maddy creds list
maddy imap-acct list
maddy imap-acct appendlimit user1@domain1.tld
```

## Безопасность

После выдачи паролей удалите plaintext-файл:

```bash
shred -u /root/mail_passwords.txt
```

Расшифровка encrypted-отчёта:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in /root/mail_passwords.enc \
  -out /root/mail_passwords.csv \
  -pass file:/root/.maddy-password-master.key
```
