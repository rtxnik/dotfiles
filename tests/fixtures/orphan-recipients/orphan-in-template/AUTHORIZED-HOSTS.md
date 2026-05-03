# AUTHORIZED-HOSTS (fixture: orphan-in-template)

3 active hosts; the template carries an extra pubkey absent from this list.
Expected `verify-recipients.sh` exit code: 1 (orphan in template).

| hostname | role         | pubkey                                                         | fingerprint | provisioned | host_type | tag    |
|----------|--------------|----------------------------------------------------------------|-------------|-------------|-----------|--------|
| devpod   | primary      | age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq6n5t2q | qq6n5t2q    | 2026-05-03  | DevPod    | active |
| macbook  | primary      | age1pzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpz6n5t2q | pz6n5t2q    | 2026-05-03  | macOS     | active |
| iphone   | device-bound | age1zrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzr6n5t2q | zr6n5t2q    | 2026-05-03  | iOS       | active |
