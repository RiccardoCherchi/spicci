# Spicci spec

Spicci is a personal expense tracker for iOS (sideloaded) and Android. It is a from-scratch rewrite of
[Sossoldi](https://github.com/RIP-Comm/sossoldi) that keeps its core model and fixes its known bugs.

## Principles

- Local SQLite only. No accounts, no cloud.
- Money is stored as integer cents. Amounts are always positive; `type` gives the sign.
- Every number is computed in Dart. AI only writes commentary on top of aggregated numbers.
- Single currency (EUR, formatted with the device region).
- UI in English and Italian via easy_localization; follows the device language, overridable in Settings.
- Dark-first look: near-black background, lime accent, cents drawn smaller. Light theme uses the same tokens.
- Icons: Solar (CC BY 4.0). Categories use Bold Duotone SVGs drawn with flutter_svg; UI uses Linear.

## Data model

| Table | Columns |
| --- | --- |
| `accounts` | id, name, icon, color, starting_cents, is_main, active, count_net_worth, position, deleted_at |
| `categories` | id, name, type (`IN`/`OUT`/`BOTH`), icon, color, note, parent_id (one level), position, deleted_at |
| `transactions` | id, date (local ISO), amount_cents, type (`IN`/`OUT`/`TRSF`), note, category_id, account_id, to_account_id, recurring_id |
| `recurring` | id, from_date, to_date, amount_cents, note, frequency, category_id, account_id, type, last_date |
| `budgets` | id, category_id, amount_cents, active (monthly) |
| `tags`, `transaction_tags` | id, name / transaction_id, tag_id |
| `presets` | id, label, amount_cents, type, category_id, account_id, note, position |

- A transfer is one row from `account_id` to `to_account_id`, with no category.
- Soft-deleted accounts and categories stay in the table, because transactions still reference them.
- `is_main` marks the default account. It is preselected in the add flow.
- App settings (theme mode) live in shared_preferences. The AI API key lives in secure storage.
- Colors are indexes into the 44-colour category palette and the 5-colour account palette, copied from
  Sossoldi so imported indexes keep their colours. Out-of-range indexes wrap around and never throw.
- Icons are Solar icon names, stored as strings. The Sossoldi importer maps Material names to Solar names.

## Screens and navigation

Floating pill bar: **Home**, a central **+** button, **Settings**. Analysis and Planning join it in their milestones.

- **Home**: month picker, amount spent this month with the difference from last month at the same day,
  a cumulative spending chart against last month, income and net-worth cards, quick-expense cards and
  the month's transactions in one card per day. Long text is ellipsised and the amount never clips.
- **Add / edit transaction** (full-screen sheet):
  1. Type switch (Expense / Income / Transfer).
  2. Large amount with a built-in keypad, focused first, and a note field under it.
  3. Horizontal strip of categories, most used first; subcategories of the selected one appear as chips.
     For transfers, From and To account cards replace the strip.
  4. Account button (default account preselected) and date button.
  5. Save button showing the signed amount.
- **Quick presets**: one tap on a chip saves the transaction at once, with an undo snackbar. A long
  press opens the preset for editing.
- **Analysis** (month or year): income, expenses, net, share of income kept and, for the running month,
  the month-end projection at the current pace; a donut of expenses per category with a change against
  the previous period (cut at the same day while the period is running) and subcategories on tap;
  12-month income/expense bars; a 12-month net-worth line (straight segments, bounds follow the data so
  negatives never break it); largest expenses; an optional AI commentary card.
- **Planning**: budgets with progress, subscriptions (recurring items with yearly cost) and pending
  recurring items.
- **Settings**: theme (system / light / dark), accounts, categories (separate Expense / Income tabs,
  reorder via drag handles), presets, Face ID lock, JSON backup / restore, Sossoldi CSV import, AI provider.

## Plan: subscriptions, planned expenses, piggy banks, budgets

- One model for scheduled items (`recurring` table): `SUB` (subscriptions, shown with yearly cost) and
  `PLAN` (big, rare expenses: insurance, tuition, car tax, shown on a 12-month timeline).
- Nothing is inserted automatically. When an item is due it shows under "To confirm" and a local
  notification offers Paid / Tomorrow / Skip. Paid opens a sheet with the real amount, date and account,
  then records the transaction and moves to the next due date (one-off items are archived).
  Due dates keep the anchor day, so Jan 31 goes to Feb 28 and then back to Mar 31. The first occurrence
  is never lost. Notification permission is asked when the first item is saved.
- **Piggy banks** (`pots`, `pot_moves`) set money aside *inside* an account. They never change the account
  balance, so it keeps matching the bank. The account shows free money and money in piggy banks; Home shows
  "Available" (free money) when piggy banks exist.
  - A piggy bank linked to a planned expense fills automatically: on the saving day (Settings, default 1)
    it gets the missing amount divided by the deposits left before the due date. Paying the expense takes
    what it can from the piggy bank; any change stays there.
  - A project piggy bank (e.g. a trip) is filled by hand and can have a goal and a date; expenses can be
    paid from it in the add page.
- **Budgets**: a monthly limit per top-level expense category, subcategories included.

## Storage and sideloading

- The database lives in `Library/Application Support`: iOS backs it up, but the Files app never shows it.
- A SideStore refresh (every 7 days on a free Apple ID) reinstalls over the app and keeps its data.
- Data is lost when the app is deleted, or when it is signed with a different Apple ID, because the
  bundle ID (and so the container) changes. Restoring a sideloaded app from an iCloud backup is not reliable.
- So Spicci's own backup is the real safety net. The user picks a backup folder once (normally in iCloud
  Drive); a security-scoped bookmark (native code in `ios/Runner/AppDelegate.swift`, no paid iCloud
  entitlement needed) lets the app write a daily JSON backup there, keeping 30. Those files survive
  deleting the app. A local copy also goes to `Documents/Backups`. Home warns when no folder is set or
  the last copy is older than two days. After a reinstall, the empty Home offers "Restore from file".

## JSON backup

One file: `{"app": "spicci", "version": 1, "exportedAt": ..., "tables": {"accounts": [...], ...}}`, one
array per table with the database column names. Restore replaces all data in one transaction; unknown
columns are ignored and newer versions are refused. Before any restore or import, today's data is saved
as an automatic backup. Backups run at launch and when the app goes to the background: one file per day in the
backup folder (newest 30 kept) and in `Documents/Backups` (newest 10). A manual export via the share
sheet is also available.

## AI commentary (optional)

One OpenAI-compatible client (`lib/logic/ai.dart`): base URL, model and API key (iOS Keychain).
Presets: Groq (recommended), OpenRouter, Gemini, Mistral, Cerebras, Custom. Models are loaded from the
provider's `/models` endpoint instead of being typed. Only aggregates are sent: period totals, the
previous period, totals per category and the last 6 months; never notes, tags, account names or single
transactions (covered by a test). Gemini and Mistral show a warning that their free tier may train on data.

## Milestones

1. **Foundation**: theme tokens (light / dark / system), schema and repositories, seeded categories and
   a default account, add flow (keypad, category grid, default account, presets), day-grouped list,
   Sossoldi CSV importer with tests.
2. **Management** (done): edit and delete transactions, accounts and categories screens, presets
   list, tags, category suggestion from the note, search and filters, custom date picker.
3. **Plan** (done): subscriptions and planned expenses with confirmation and notifications, piggy banks,
   budgets.
4. **Analysis** (done): charts page and AI commentary.
5. **Safety** (done): Face ID lock with passcode fallback and an always-visible Unlock button, app
   hidden in the app switcher, switching scheduled items between subscription and planned expense,
   app icon and dark launch screen, `tool/build_ipa.sh` building `dist/Spicci.ipa` for SideStore.
   JSON backup and restore were moved ahead.
