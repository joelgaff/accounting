# Backlog

Open items, roughly in priority order. Nothing here blocks daily use.

## Books
- [ ] **Full history from Xero (2019 →).** Re-export invoices, bills and contacts with the date range opened, export the Journal report for the whole period, bundle them and run `bin/xero-prod import`. The importers are ready; the current prod bundle is the 2025 slice.
- [ ] **Credit notes, prepayments, overpayments.** No model yet; they import from the Journal report as plain journal entries. Add them as document types when one is needed (`Documentable` interface in CLAUDE.md).
- [ ] **Fee-net payments on the reconcile page.** A bank line that is an invoice payment net of a processor fee (Stripe, RunSignUp) can't be split into "payment + fee" because the fee is not a bank movement. Xero handles it with an adjustment on the match screen. Workaround today: match the invoice for the net amount and record the fee as an expense, or edit the invoice.
- [ ] **Bills have no due date.** AP aging assumes 30 days from the bill date. Add `due_date` to bills when payment terms matter.
- [ ] **Tax rates are hand-entered.** The importer exists (`tax_rates.csv` in a bundle) but nothing seeds them from Xero automatically.

## Reconcile and banking
- [ ] Bank rule ordering UI (rules apply in `position` order; there is no drag-to-reorder yet).
- [ ] SimpleFIN pending transactions are skipped; consider showing them greyed out.
- [ ] Reconciliation report per period (statement balance vs ledger with the outstanding lines listed), on top of the summary strip.

## Documents
- [ ] Invoice numbering separate from the document id (Xero numbers survive on imported invoices; new ones show "Invoice #<id>").
- [ ] Recurring bills (recurring invoices exist).
- [ ] Attachments on deposits and transfers in the UI (the model already supports them).

## Platform
- [ ] Multi-tenant membership and switching (structure is ready; single-tenant today).
- [ ] Cloudflare caching rules, uptime monitoring on `/up`, off-site SQLite backup (see DEPLOY.md).
