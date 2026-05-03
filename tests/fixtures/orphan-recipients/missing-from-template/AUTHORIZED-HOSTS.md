# AUTHORIZED-HOSTS (fixture: missing-from-template)

4 active hosts; template only carries 3 of them.
Expected `verify-recipients.sh` exit code: 1 (active host missing from template).

| hostname      | role         | pubkey                                                         | fingerprint | provisioned | host_type | tag    |
|---------------|--------------|----------------------------------------------------------------|-------------|-------------|-----------|--------|
| devpod        | primary      | age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq6n5t2q | qq6n5t2q    | 2026-05-03  | DevPod    | active |
| macbook       | primary      | age1pzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpz6n5t2q | pz6n5t2q    | 2026-05-03  | macOS     | active |
| iphone        | device-bound | age1zrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzr6n5t2q | zr6n5t2q    | 2026-05-03  | iOS       | active |
| backup-laptop | primary      | age18g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g8g6n5t2q | 8g6n5t2q    | 2026-05-03  | macOS     | active |
