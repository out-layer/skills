# Payment Check - Implementation Spec

Спецификация для реализации фичи Payment Check (agent-to-agent payments) на основе NEAR Intents Gifts.

API-контракт описан в [SKILL.md](../SKILL.md) → секция "Payment Checks (Agent-to-Agent Payments)".

---

## Архитектура

```
Agent (buyer)                Coordinator                    OutLayer TEE                  intents.near
     |                           |                              |                              |
     | POST /payment-check/create|                              |                              |
     |-------------------------->|                              |                              |
     |                           | derive ephemeral key         |                              |
     |                           |----------------------------->|                              |
     |                           | ed25519 keypair              |                              |
     |                           |<-----------------------------|                              |
     |                           |                              |                              |
     |                           | transfer intent (wallet → ephemeral implicit account)       |
     |                           |------------------------------------------------------------->|
     |                           |                              |                              |
     |  {check_id, check_key}    |                              |                              |
     |<--------------------------|                              |                              |
```

---

## 1. OutLayer TEE - Key Derivation

### Что реализовать

Новая функция деривации ephemeral ключей из custody keystore агента.

```
derive_payment_check_key(wallet_master_key, check_counter) → Ed25519KeyPair
```

### Требования

- **Детерминистичность**: один и тот же `(wallet_master_key, check_counter)` всегда даёт один и тот же keypair
- **Изоляция**: утечка ephemeral key не компрометирует master key и другие check keys
- **Derivation path**: `m/payment-check/{check_counter}` (или аналог для Ed25519)
  - `check_counter` - монотонный счётчик на уровне кошелька, хранится в state координатора
- **Формат выхода**: Ed25519 keypair, приватный ключ в формате `ed25519:<base58>` (совместимо с NEAR)

### Рекомендуемый подход

```
ephemeral_seed = HKDF-SHA256(
    ikm = wallet_master_key,
    salt = "payment-check",
    info = uint64_be(check_counter),
    length = 32
)
keypair = Ed25519KeyPair::from_seed(ephemeral_seed)
```

### API для координатора

TEE должен экспонировать для координатора (внутренний вызов, не внешний API):

```
POST /internal/derive-check-key
{
    "wallet_id": "36842e2f...",
    "check_counter": 42
}
→ {
    "public_key": "ed25519:...",
    "private_key": "ed25519:...",
    "implicit_account_id": "a1b2c3d4..."  // hex(public_key)
}
```

Плюс: подпись intent от имени ephemeral key (для claim/reclaim):

```
POST /internal/sign-check-intent
{
    "wallet_id": "36842e2f...",
    "check_counter": 42,
    "intent": { ... }  // transfer intent payload
}
→ {
    "signed_intent": "..."
}
```

Это позволяет координатору не хранить приватные ключи - TEE деривирует и подписывает на лету.

---

## 2. Coordinator - Новые эндпоинты

### Storage / State

Новая таблица `payment_checks`:

```sql
CREATE TABLE payment_checks (
    check_id        TEXT PRIMARY KEY,        -- "pc_" + random hex
    wallet_id       TEXT NOT NULL,           -- creator wallet
    check_counter   BIGINT NOT NULL,         -- для TEE derivation
    token           TEXT NOT NULL,           -- NEAR contract ID
    amount          TEXT NOT NULL,           -- smallest denomination
    memo            TEXT,                    -- max 256 chars
    status          TEXT NOT NULL DEFAULT 'unclaimed',  -- unclaimed|claimed|reclaimed
    created_at      TIMESTAMPTZ NOT NULL,
    expires_at      TIMESTAMPTZ,            -- NULL = no expiry
    claimed_at      TIMESTAMPTZ,
    intent_hash     TEXT,                   -- hash транзакции создания
    UNIQUE(wallet_id, check_counter)
);

CREATE INDEX idx_checks_wallet_status ON payment_checks(wallet_id, status);
```

Также нужен счётчик `next_check_counter` в таблице wallets (или отдельно).

### POST /wallet/v1/payment-check/create

**Логика:**

1. Валидация: `token`, `amount` (> 0), `memo` (≤ 256), `expires_in` (> 0 если указан)
2. Инкремент `check_counter` для кошелька
3. Вызов TEE: `derive-check-key(wallet_id, check_counter)` → получаем `public_key`, `private_key`, `implicit_account_id`
4. Проверка intents balance для `token`:
   - Если достаточно → переходим к п.5
   - Если нет - проверяем wallet balance. Если достаточно → auto-deposit в intents (`/intents/deposit` логика). Если нет → `insufficient_balance`
5. Подписываем transfer intent от имени wallet: переводим `amount` токена `token` на `implicit_account_id` внутри `intents.near`
6. Сохраняем запись в `payment_checks`
7. Возвращаем `check_id`, `check_key` (= `private_key`), остальные поля

**Важно:** `check_key` (приватный ключ) координатор НЕ сохраняет. Он возвращается клиенту один раз. При необходимости (reclaim) координатор повторно деривирует ключ через TEE.

### POST /wallet/v1/payment-check/claim

**Логика:**

1. Парсим `check_key` → извлекаем `public_key` → вычисляем `implicit_account_id`
2. Проверяем баланс `implicit_account_id` в `intents.near` (on-chain query или через SDK)
3. Если баланс 0 → `check_empty`
4. Ищем check в БД по `implicit_account_id` (можно вычислить из public_key):
   - Если найден и `status != unclaimed` → `check_already_claimed` / `check_already_reclaimed`
   - Если найден и `expires_at` прошёл → `check_expired`
   - Если не найден в БД - чек мог быть создан другим сервисом, всё равно пробуем claim
5. Подписываем transfer intent ephemeral ключом: переводим все токены с `implicit_account_id` на intents-аккаунт получателя (auth wallet)
   - Для подписи: используем `check_key` напрямую (клиент его прислал) - НЕ нужен вызов TEE
6. Обновляем `status = 'claimed'`, `claimed_at = now()` в БД
7. Возвращаем `token`, `amount`, `memo`, `claimed_at`

### GET /wallet/v1/payment-check/status

**Логика:**

1. Найти check по `check_id` + `wallet_id` (из auth) → `check_not_found` если нет
2. Если `status = 'unclaimed'` и `expires_at` прошёл → вернуть `status: "expired"`
3. Для дополнительной надёжности: можно проверить on-chain баланс ephemeral account:
   - Если баланс 0 и status = unclaimed → кто-то заклеймил on-chain напрямую → обновить `status = 'claimed'`
4. Вернуть все поля

### GET /wallet/v1/payment-check/list

**Логика:**

1. Query `payment_checks WHERE wallet_id = auth_wallet`
2. Фильтр по `status` если указан (для `expired` - фильтр `status = 'unclaimed' AND expires_at < now()`)
3. Limit (default 50, max 100)
4. Вернуть `{"checks": [...]}`

### POST /wallet/v1/payment-check/reclaim

**Логика:**

1. Найти check по `check_id` + `wallet_id` → `check_not_found`
2. Если `status = 'claimed'` → `check_already_claimed`
3. Если `status = 'reclaimed'` → `check_already_reclaimed`
4. Вызов TEE: `derive-check-key(wallet_id, check_counter)` → получаем ephemeral keypair
5. Вызов TEE: `sign-check-intent` - transfer intent от ephemeral account обратно на wallet intents balance
6. Если транзакция failed (баланс 0 - кто-то уже заклеймил on-chain) → обновить status = 'claimed', вернуть `check_already_claimed`
7. Обновить `status = 'reclaimed'`
8. Вернуть `token`, `amount`, `reclaimed_at`

---

## 3. Интеграция с NEAR Intents

### Transfer intent (создание чека)

Координатор подписывает intent от имени wallet:

```javascript
await sdk.signAndSendIntent({
    intents: [{
        intent: 'transfer',
        receiver_id: ephemeralImplicitAccountId,  // hex(ephemeral_public_key)
        tokens: {
            [`nep141:${token}`]: amount,
        },
    }],
});
```

### Transfer intent (claim)

Координатор подписывает intent от имени ephemeral account (используя check_key от клиента):

```javascript
const sdkAsCheck = new IntentsSDK({
    intentSigner: createIntentSignerNearKeyPair({
        signer: KeyPair.fromString(checkKey),
        accountId: ephemeralImplicitAccountId,
    }),
});

await sdkAsCheck.signAndSendIntent({
    intents: [{
        intent: 'transfer',
        receiver_id: claimerIntentsAccountId,
        tokens: {
            [`nep141:${token}`]: amount,
        },
    }],
});
```

### Transfer intent (reclaim)

То же что claim, но `receiver_id` = creator wallet's intents account. Ephemeral key деривируется через TEE (не из запроса).

---

## 4. Race Conditions и Edge Cases

| Ситуация | Поведение |
|----------|-----------|
| Claim + Reclaim одновременно | Blockchain first-to-claim. Второй получит failed transaction → координатор обрабатывает gracefully |
| Внешний кошелёк заклеймил on-chain | Status endpoint проверяет on-chain баланс, обновляет status если 0 |
| Claim после expiry через API | Координатор отклоняет с `check_expired` |
| Claim после expiry on-chain напрямую | Успешно (on-chain нет expiry). Координатор обнаружит при status check |
| Сервер перезагрузился | Все ephemeral ключи восстанавливаемы через TEE derivation (wallet_id + check_counter) |
| Двойной create с тем же counter | UNIQUE constraint в БД предотвращает. Counter инкрементируется атомарно |

---

## 5. Порядок реализации

### Фаза 1: OutLayer TEE
- [ ] Реализовать `derive_payment_check_key` (HKDF от master key)
- [ ] Экспонировать внутренний API `POST /internal/derive-check-key`
- [ ] Экспонировать `POST /internal/sign-check-intent`
- [ ] Тесты: детерминистичность, изоляция ключей

### Фаза 2: Coordinator - Storage
- [ ] Миграция: таблица `payment_checks`
- [ ] Миграция: `next_check_counter` в wallets
- [ ] Индексы

### Фаза 3: Coordinator - Create + Status
- [ ] `POST /wallet/v1/payment-check/create` (с auto-deposit)
- [ ] `GET /wallet/v1/payment-check/status`
- [ ] `GET /wallet/v1/payment-check/list`
- [ ] Тесты: создание, статус, expiry

### Фаза 4: Coordinator - Claim + Reclaim
- [ ] `POST /wallet/v1/payment-check/claim`
- [ ] `POST /wallet/v1/payment-check/reclaim`
- [ ] Обработка race conditions
- [ ] Тесты: claim, reclaim, double-claim, expired claim

### Фаза 5: Интеграция
- [ ] E2E тест: create → claim → verify balance
- [ ] E2E тест: create → expire → reclaim
- [ ] E2E тест: create → external claim on-chain → status shows claimed
- [ ] Audit log интеграция (записывать create/claim/reclaim в audit)
- [ ] Policy интеграция (проверять policy при create)
