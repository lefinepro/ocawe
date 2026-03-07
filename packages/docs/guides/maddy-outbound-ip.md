# Исходящая почта Maddy с привязкой домен -> IP (multi-IP)

Этот гайд закрывает `PRD-06`: настройка исходящей почты в Maddy так, чтобы каждый домен отправлял через свой IP.

## Что добавлено в репозиторий

- `scripts/maddy-outbound-ip/playbook.toml`
- `scripts/maddy-outbound-ip/inventory.example.toml`
- `scripts/maddy-outbound-ip/outbound-ip-map.example.env`
- `scripts/maddy-outbound-ip/maddy-outbound-multiip.conf.example`

## Важные уточнения по Maddy

- В актуальном Maddy для исходящего bind используется `target.remote { local_ip ... }`.
- Директивы вида `source_ip` в `submission`/`local` для исходящего маршрута не используются.
- Привязка домена к IP делается через `source <domain> ... default_destination { deliver_to &remote_queue_* }`.

## Предпосылки

- Maddy установлен и работает.
- Для каждого домена опубликованы DNS-записи.
- Известно соответствие `domain -> outbound IP`.
- PTR (rDNS) настраивается у провайдера IP.

## Быстрый старт (spot)

1. Подготовьте inventory:

```bash
cp scripts/maddy-outbound-ip/inventory.example.toml inventory.toml
```

2. Подготовьте env с mapping:

```bash
cp scripts/maddy-outbound-ip/outbound-ip-map.example.env /tmp/maddy-outbound-ip.env
# Отредактируйте /tmp/maddy-outbound-ip.env
```

Минимально проверьте значения:
- `DOMAINS` - список доменов.
- `SERVER_IPS` - все публичные SMTP IP на сервере.
- `DOMAIN_IP_MAP` - соответствие `domain=ip` для каждого домена.
- `FALLBACK_IP` - основной IP для fallback.
- `PTR_HOSTS` - соответствие `ip=ptr-hostname`.
- `TEST_FROM` и `TEST_RECIPIENT` - для smoke-теста отправки (опционально).

3. Скопируйте env на сервер (или создайте `/etc/cogni/maddy-outbound-ip.env` вручную).

4. Запустите playbook:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  ghcr.io/umputun/spot:latest \
  -p scripts/maddy-outbound-ip/playbook.toml \
  -i inventory.toml \
  -t default
```

Playbook:
- проверяет соответствие `domain -> IP` по DNS (`STRICT_DNS_MATCH`),
- проверяет PTR для исходящих IP (`STRICT_PTR_MATCH`),
- валидирует, что `DOMAIN_IP_MAP` использует только адреса из `SERVER_IPS`,
- рендерит multi-IP snippet в `/etc/cogni/maddy-outbound-multiip.rendered.conf`,
- рендерит route hints в `/etc/cogni/maddy-outbound-routes.generated.txt`,
- опционально запускает smoke-тест отправки и замер enqueue latency (`STRICT_ENQUEUE_LATENCY`),
- оставляет fallback-маршрут через основной IP.

## Как включить в `maddy.conf`

По умолчанию auto-append выключен (`APPLY_MADDY_SNIPPET="no"`).

Рекомендовано:
1. Вручную объединить `/etc/cogni/maddy-outbound-multiip.rendered.conf` с вашим `/etc/maddy/maddy.conf`.
2. Встроить блоки из `/etc/cogni/maddy-outbound-routes.generated.txt` в `submission` endpoint.
3. Перезапустить Maddy и проверить логи.

Минимальная схема:

```conf
target.remote remote_mx_domain1_tld {
    debug yes
    dns mx
    local_ip 203.0.113.10
}

target.queue remote_queue_domain1_tld {
    target &remote_mx_domain1_tld
}

submission tcp://0.0.0.0:587 {
    hostname mail.domain1.tld
    auth &local_authdb

    source domain1.tld {
        check { authorize_sender { prepared true } }
        destination $(local_domains) { deliver_to &local_routing }
        default_destination { deliver_to &remote_queue_domain1_tld }
    }

    default_source {
        check { authorize_sender { prepared true } }
        destination $(local_domains) { deliver_to &local_routing }
        default_destination { deliver_to &remote_queue_fallback }
    }
}
```

## Логирование используемого IP

- Включайте `debug yes` в `target.remote`.
- Проверяйте `journalctl -u maddy` и фильтруйте по именам `remote_queue_*`/`remote_mx_*`.
- Для финальной валидации смотрите внешний `Received`/trace на принимающем сервере.

## Валидация

Проверка DNS/PTR:

```bash
dig +short A domain1.tld
dig +short -x 203.0.113.10
```

Проверка отправки:

1. Отправьте письмо с каждого домена на внешний ящик.
2. Проверьте, что домен отправителя использовал ожидаемый IP.
3. Проверьте `Authentication-Results`: `spf=pass`.

Проверка enqueue latency (NFR `< 5 сек`):

```bash
time sh -c 'printf "Subject: test\n\nbody\n" | sendmail -f sender@domain1.tld receiver@example.net'
```

## Acceptance Checklist

- `AC-1` Письмо с `domain1.tld` уходит с `IP1`.
- `AC-2` По логам/заголовкам видно корректный исходящий IP.
- `AC-3` SPF проходит для каждого домена.
- `AC-4` PTR существует и совпадает с ожидаемым hostname для всех исходящих IP.
- `NFR-1` Письмо принимается в очередь Maddy быстрее 5 секунд.
- `NFR-2` По логам `journalctl -u maddy` видно, какой `remote_mx_*`/IP использован.
- `NFR-3` При проблеме со специфичным маршрутом остаётся `default_source -> remote_queue_fallback`.

## Риски

- PTR не настроен или не совпадает с HELO hostname.
- У части IP плохая репутация (blacklist).
- В `submission` не добавлены `source`-роуты для всех доменов.
