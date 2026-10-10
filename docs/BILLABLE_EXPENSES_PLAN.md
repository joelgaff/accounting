# Billable expenses

An expense or bill can be flagged as billable to a customer. When an invoice for
that customer is written, its unbilled expenses are offered under the lines; a
tick adds each as an invoice line, optionally marked up. Xero calls this
billable expenses. Nothing about the ledger changes: the cost stays an expense,
the invoice line is revenue.

## Decided

- **Gross method.** The expense posts as it always has (debit its expense
  account, credit the bank or Accounts Payable). The picked-up invoice line
  credits one revenue account. Profit is the same as the net method; the P&L
  shows both what was spent and what was charged.
- **Default account: 4721 Billable Expense Income**, chosen in Settings → Books
  as "Billable expenses income". Blank means the picked-up line defaults to
  the expense line's own account (the net method, for anyone who wants it).
  Joel archives 4030 Reimbursed Expenses, 4749 Travel Fees and 4900 Markup
  himself in Accounts.
- **Markup** is a percentage typed in the pick-up panel, applied to everything
  ticked, and lands in the same account as the rest of the line. The customer
  sees one price; the expense keeps its real cost. Nothing is stored per
  customer.
- **Whole document is flagged**, not single lines. Each of its lines becomes an
  invoice line, so accounts, tax rates and tracking survive a mixed expense.
- **Carried across to the invoice line:** description as the expense line had
  it, quantity and unit amount (unit marked up), tax rate, tracking options.
  Account from Settings (see above).
- **Flag it** on the expense and bill forms and in the reconcile Create panel,
  as a "Bill to" customer picker. Memory learns it with the rest of the coding.
- **Billed is derived**, not stored: an expense is billed while a live
  (non-voided) invoice carries a line that rebills it. Removing the row before
  saving, voiding or deleting the invoice all free the expense again with no
  status to keep in sync.
- The account on a picked-up line is still editable in the form, like any
  other line.

## Schema (one migration)

- `documents.billable_to_contact_id` (FK contacts, nullable, indexed). Set on
  Expense and Bill documents only; a validation refuses it elsewhere.
- `line_items.rebills_document_id` (FK documents, nullable, indexed). Set on an
  invoice line that was picked up from a billable expense. One invoice line per
  expense line, but the link is to the document, which is the unit that is
  flagged and billed; the line's own fields say what it rebills.
- `organization_settings.billable_income_account_id` (FK plutus_accounts,
  nullable). Must be a revenue account when set.

## Model

- `Document`
  - `belongs_to :billable_to, class_name: "Contact", optional: true`.
  - `validate` billable_to only on `expense? || bill?`; the contact must be in
    the organisation (`scoped_to_organization`, as the other FKs).
  - `has_many :rebilling_lines, class_name: "LineItem", foreign_key:
    :rebills_document_id` and `billed_on` = the live approved-or-draft invoice
    among those lines' documents, or nil. `billed?` = `billed_on.present?`.
  - `scope :billable_to(contact)` = posted expenses and bills flagged for that
    contact; `scope :unbilled` = those with no live invoice line rebilling
    them (a `NOT EXISTS` against line_items joined to live invoices).
  - `copy_from` does **not** carry `billable_to`; a copy is a new cost.
- `LineItem`
  - `belongs_to :rebills, class_name: "Document", optional: true`.
  - Validation: `rebills` must be a billable expense or bill of the same
    organisation, and the line's own document must be an invoice.
- `OrganizationSettings`
  - `belongs_to :billable_income_account, class_name: "Plutus::Revenue",
    optional: true`.
- `Contact#unbilled_expenses` = `organization.documents.billable_to(self).unbilled`.
- `Reconciliation::Categorize` takes `billable_to:` (a contact name, found or
  made as a customer, or upgraded to "both") and sets it on the document.
  `Memory::Coding`/`Hit` carry `billable_to_name`; `Memory#coding` includes it;
  the OK re-reads it like the rest.
- `Billing::PickUp` (new service, `app/services/billing/pick_up.rb`): given an
  invoice document, a list of expense documents and a markup percentage,
  builds the invoice lines in memory (not saved):
  `unit_amount = (src.unit_amount * (1 + markup/100)).round(2)`, description,
  quantity, tax_rate, tracking copied, account = settings account or the
  source line's, `rebills: src.document`. Used by the controller to render
  rows into the form and by tests. One place for the arithmetic.

## Controllers and routes

- `GET /contacts/:id/billable_expenses?for=<invoice id or blank>&markup=10`
  (`Contacts::BillableExpensesController#index`), rendered inside a Turbo
  frame on the invoice form. Lists the contact's unbilled expenses and bills:
  date, vendor, description, amount, and a checkbox per document. A markup
  field at the top re-fetches the frame on change (so the amounts shown are
  the marked-up ones). Each checkbox carries the rows to add as a `<template>`
  rendered through `Billing::PickUp`, using `shared/line_item_row` with
  `child_index: "NEW_RECORD"` so the existing line-items Stimulus controller
  can add them.
- Invoice form: `document[line_items_attributes][n][rebills_document_id]` is a
  hidden field on each row (blank for ordinary lines), permitted in
  `DocumentsController#document_params`. Save stores it; nothing else to do.
- `InvoicesController#new`/`copy`/`edit` render the frame lazily (`src:`) when
  a customer is picked; a small Stimulus controller (`billable_controller.js`)
  sets the frame's `src` from the customer select and inserts a ticked
  template's rows via the line-items controller's `add` path. Unticking
  removes rows it added and not yet saved (persisted rows go through the
  normal × remove with `_destroy`).
- Expense and bill forms: "Bill to" `collection_select :billable_to_id`,
  customers, include_blank "Not billable". Permitted in universal params but
  validated to purchase types.
- Reconcile Create panel: "Bill to" text field with the contact datalist, next
  to Vendor, optional; posted as `billable_to`. Prefilled from memory.

## Views

- Expense and bill show pages: a line under the status header. "Billable to
  Northwind · not yet invoiced" with a "New invoice for Northwind" link
  (`new_invoice_path(contact_id:)`), or "Billed on INV-2380" linking to it.
- Invoice show page: a picked-up line shows a small muted "rebills Expense ·
  Delta, Mar 14" under its description, linking to the expense. Print and PDF
  show nothing about it.
- Contact page: an "Unbilled expenses" section with the same list and total
  when there are any, and the same "New invoice" link.
- Expenses and bills index: a `billable` chip (flagged, not yet billed) so the
  outstanding list is one tap away without going through a contact.
- Settings → Books: "Billable expenses income" select among revenue accounts,
  saved through the same `save_settings` helper as the others, with the help
  text "Picked-up expenses go to this account on an invoice. Blank: the
  expense's own account."
- Reconcile memory hint: "Last time: Zoom · 6820 Web Hosting · billed to
  Northwind".

## Edge cases

- A flagged expense that is voided or deleted drops off the unbilled list
  (`posted` scope).
- The same expense ticked on two invoices: the second save is refused with
  "already billed on INV-2380" unless that invoice is voided. Validation on
  the line, re-checked at approve.
- Changing the customer on an invoice that already carries picked-up lines:
  the lines stay (they are lines), but the form warns that they rebill
  expenses flagged to another customer. Approval does not refuse it; the
  bookkeeper may know better.
- Markup applies to unit amount; quantity is copied as is, so a 3 × $40 line
  at 10% becomes 3 × $44.
- Tax: the expense line's tax rate comes across as the invoice line's rate. The
  invoice form shows tax as it does for any line.
- A draft invoice counts as billing (it holds the lines); the expense page says
  "on draft INV-2381" so it is not picked up twice while the draft waits.
- Copying an invoice (`copy_from`) does not copy `rebills_document_id`; the
  copy's lines are ordinary.
- Xero import: nothing to map, Xero's export does not carry billable flags.

## Steps (red, green, refactor, one commit each)

1. Migration + settings account: `billable_income_account` on settings, the
   Books row, validation it is revenue. Test: save, blank, non-revenue refused.
2. Flag on the document: `billable_to`, validation by type, show-page line,
   the form field on expenses and bills, `billable_to`/`unbilled` scopes,
   `billed_on`. Tests on the model and the two forms.
3. `LineItem#rebills` + `Billing::PickUp`: the arithmetic, account choice,
   tax and tracking carry-over, validations (type, organisation, already
   billed). Model and service tests.
4. Pick-up panel: the frame controller, the view, the Stimulus glue, the
   hidden field through the form, the show-page "rebills" note. Request tests
   on the frame and on saving an invoice with picked-up lines; a browser test
   that ticks one and sees the row appear and the total move, desktop and
   phone.
5. Billed status everywhere it shows: expense page, contact page, index chip,
   refusal of a second pick-up. Request tests.
6. Reconcile: "Bill to" in the Create panel, `Categorize`, memory carries it,
   hint text. Service and request tests, phone browser test for the panel.
7. CLAUDE.md paragraph, README line.

Out of scope for now: a report of billable expenses outstanding by customer
(the contact page and the chip cover it), markup per customer, line-level
flags, the Xero API pulling Xero's own billable flags.
