# Responsive plan: desktop as is, phone layer underneath

Mockups and the Xero research: https://claude.ai/artifact/NNRjozJYSTuXHQ2ZXwsTFH
Written 2026-10-07. Built 2026-10-08, all eleven steps, on master.

## What Xero does on small screens
Native app, designed for a thumb: bottom tab bar (not a hamburger); lists are
cards, never sideways tables; the dashboard is a stack of widgets; reconciliation
is a deck of cards with the suggestion on the card and OK or swipe to confirm;
forms are one column with a sticky save; full reports stay on the desktop.

## Where the app stands
One breakpoint at 900px: the sidebar becomes a horizontal link strip, tables
scroll sideways, reconcile already renders cards. Reachable, not designed.

## Breakpoints
- Above 1000px: unchanged.
- 700 to 1000px: sidebar becomes an icon rail with labels on hover.
- Below 700px: top bar + bottom tabs (Home, Invoices, Reconcile, Reports, More),
  lists as cards, forms one column with line items as cards and a pinned save bar.

## Steps, one commit each
1. Phone test harness: system test at 390×844 asserting no sideways scroll and
   the bottom bar present. Red until the step that fixes each page.
2. Shell: three breakpoints; top bar, bottom tabs, More sheet (one Stimulus
   controller); icon rail; safe-area insets; 16px form text.
3. List rows as cards: `data-cell="primary|secondary|amount|status"` on index
   row cells, one CSS grid turns marked tables into cards below 700px. Invoices,
   bills, expenses, deposits, transfers, contacts, payments, bank account activity.
4. Filters as chips; floating + on list pages.
5. Document pages: sticky bottom action bar (primary action, Edit, ··· sheet);
   lines as cards; history collapsed behind a count.
6. Forms: one column; line items as tappable cards with live amount; pinned save
   bar; combobox as a bottom sheet on phones.
7. Reconcile: thumb-sized OK, full-width segment bar, forms in a bottom sheet,
   bank filter as chips with counts.
8. Dashboard: stacked KPI tiles, quick-action row, activity as cards.
9. Reports: frozen first column with sideways figures; P&L and balance sheet
   sections stack with collapsible groups.
10. Settings and the rest: check every page at phone width, fix what the
    harness flags.
11. PWA polish: standalone display, apple-touch-icon, status bar colour per theme.

Optional 12: swipe-right to OK on reconcile.

## Decisions
1. Tabs: Home, Invoices, Expenses, Reconcile, More.
2. Button only on reconcile; swiping is still optional step 12.
3. Line items on a phone form are cards that expand in place.

## Departures from the plan
- Reconcile panels open under their card at full width rather than in a
  bottom sheet, so the line being acted on stays in view.
- Reports got the frozen column and stacking; collapsible groups were not
  needed, the sections are short.
- Journal lines on a phone keep the sideways sheet; rare enough to leave.
