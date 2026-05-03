# AUTHORIZED-HOSTS (fixture: ignores-retired)

3 active hosts (matched by template) + 1 retired host (must be ignored).
Expected `verify-recipients.sh` exit code: 0 (retired rows are out-of-scope per D-10).

| hostname   | role         | pubkey                                                         | fingerprint | provisioned | host_type | tag     |
|------------|--------------|----------------------------------------------------------------|-------------|-------------|-----------|---------|
| devpod     | primary      | age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq6n5t2q | qq6n5t2q    | 2026-05-03  | DevPod    | active  |
| macbook    | primary      | age1pzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpzpz6n5t2q | pz6n5t2q    | 2026-05-03  | macOS     | active  |
| iphone     | device-bound | age1zrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzrzr6n5t2q | zr6n5t2q    | 2026-05-03  | iOS       | active  |
| old-laptop | escrow       | age1ryryryryryryryryryryryryryryryryryryryryryryryryryry6n5t2q | ry6n5t2q    | 2024-01-01  | macOS     | retired |
