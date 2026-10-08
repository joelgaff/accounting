# Payee memory for reconciliation

Built 2026-10-08. Decisions: a confident suggestion creates the expense or
deposit on one tap (undo stays available); memory learns contact, account,
tax rate and tracking; three agreeing codings make it confident.

Order of trust on a line: bank rule, then match to an open document or
transfer, then memory.

- `Reconciliation::PayeeKey` turns the bank's text into a key: lowercase, no
  dates, store or card numbers, invoice ids or punctuation. Under four
  characters is no key.
- `Reconciliation::Memory` loads once per page: reconciled lines through
  their document, plus expenses and deposits entered by hand or imported
  whose counterparty's words all appear in the line. Direction is respected,
  voided documents ignored. Three recent codings agreeing on account and
  tracking make a Hit confident; tax comes along only when it agrees too.
- The suggester ranks memory below rules and exact matches. Confident shows
  OK; a hint prefills the Create panel and says how many times it was seen.
- OK on a memory suggestion re-reads the books and refuses if no longer
  confident. A new rule made from a line starts from the same memory.

Not done, by choice: no stored key column (derived each page; add one if the
lookup ever shows in the logs), no swipe.
