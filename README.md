# Partita Doppia

Double-entry books for a small business, built for people leaving Xero. Rails 8,
SQLite, Hotwire. One organisation, a chart of accounts, invoices and bills with
payments, spend and receive money, transfers, manual journals, bank
reconciliation against a SimpleFIN feed or statement files, Xero-style tracking
categories, and the usual reports (P&L, balance sheet, trial balance, general
ledger, aging, P&L by tracking).

Partita doppia is Italian for double entry. The name is always the two words
together.

## What you need

- Ruby 3.4, SQLite 3. No Postgres, Redis or Node.
- An SMTP account for email: login codes and invoice emails.
- Optional: a [Xero app](https://developer.xero.com/app/manage) to import your
  history over the API, and a [SimpleFIN](https://bridge.simplefin.org) account
  for the nightly bank feed (about $1.50 a month).

## First run

```sh
bundle install
bin/rails db:prepare
cp config/credentials.yml.example /tmp/creds && EDITOR="nano" bin/rails credentials:edit   # fill in secret_key_base, encryption keys, app.host, smtp
bin/rails server
```

Visit the site. With nobody signed in yet it shows **Set up your books**: name
the entity and the first person, prove the email with a six-digit code, and
you're in. There are no passwords: every sign-in emails a code. Add other people
under **Settings → People**.

## Bringing your Xero history

Settings → Xero → Connect, then Run import. It pulls the chart of accounts, tax
rates, contacts, tracking categories, every sales invoice and bill with lines,
tracking and payments, spend and receive money, transfers and manual journals.
Re-running is safe; it updates in place.

Registering the app at developer.xero.com: Web app, redirect URI
`https://<your host>/settings/xero/callback`, then put the client id and secret
in the credentials under `xero:`. Apps registered after March 2026 get only
Xero's granular scopes, which this app requests. Two things those scopes cannot
read: **conversion balances** and journals Xero made on its own (depreciation,
payroll). Enter those once as a manual journal and the balance sheet lines up.

The CSV uploads under Settings → Imports and data are the fallback for the same
exports by file.

## Bank feed and statements

Settings → Bank feed: paste a SimpleFIN setup token, map its accounts onto
yours, and lines arrive every night. **Pull history** on that page backfills in
90-day windows. CSV, OFX and QFX statement files upload from the same Settings
section or from any bank account's page.

## Assumptions, stated

- One organisation per installation, one currency (shown as `$`), a calendar
  fiscal year.
- Sales tax is a single rate on top of a line; purchase tax is folded into the
  cost unless a recoverable asset account is set on the rate.
- Bank feeds are SimpleFIN only. Everything else is a file upload.

## Sign-in

Built-in by default: email, six-digit code, session. If the credentials carry a
`launchpad:` block the app instead trusts a [Launchpad](../launchpad) SSO hub's
cookie and the hub decides who gets in; `AUTH_MODE=local` or `=launchpad` in the
environment overrides for development.

## Development

- `bin/dev` runs the app on 3001 (and a Launchpad checkout on 3000 if you have
  one; set `AUTH_MODE=local` to skip it). Open http://accounting.lvh.me:3001.
- `bin/ci` is what the pre-push hook runs: lint, security audits, tests. Enable
  the hook once with `git config core.hooksPath .githooks`.
- Mail opens in the browser in development via letter_opener; mailer previews
  live at `/rails/mailers`.

`CLAUDE.md` holds the working notes on the domain model and conventions.
`docs/OPEN_SOURCE_PLAN.md` is the plan that got the app here.
