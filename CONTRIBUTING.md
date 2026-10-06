# Contributing

- Run `bin/setup` once; it enables the pre-push hook (`.githooks/pre-push`),
  which runs `bin/ci` (lint, security audits, the test suite) before anything
  reaches GitHub. A red run blocks the push.
- Tests: `bin/rails test`. The suite runs in Launchpad mode and sets
  `AUTH_MODE=local` where it exercises the built-in sign-in.
- Style is `rubocop-rails-omakase`; `bin/rubocop -a` for the safe fixes.
- Keep commits to one concern each, with a message that says why.
- Fixtures use made-up names. Keep it that way.
- `CLAUDE.md` is the working notes on the domain model and conventions; read
  it before changing how documents post to the ledger.
