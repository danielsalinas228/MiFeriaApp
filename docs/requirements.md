# MiFeria App — High-Level Requirements

**Version:** 0.2 (Draft)
**Date:** 2026-07-06
**Status:** In Review

---

## 1. Product Vision

A personal-first budget and expense tracker built for manual-entry workflows with automation support. Designed to be simple enough for daily use on mobile web, extensible enough to grow into multi-user, multi-currency, and investment tracking over time.

The primary reference app is [Wallet by BudgetBakers](https://support.budgetbakers.com/hc/en-us), which this project aims to replicate and improve upon.

---

## 2. Guiding Principles

- **Mobile-first web** — all core flows must be comfortable on a phone screen
- **Manual entry is a first-class citizen** — no reliance on bank integrations at launch
- **Solo-first, collaboration-ready** — built for one user, architected to support sharing
- **Extensible data model** — entities designed with extra fields/metadata so future features don't require schema rewrites
- **Open source stack with pragmatic cloud** — prefer open source tooling; use AWS where it adds value but choose cost-effective managed services (e.g. Neon over RDS)

---

## 3. Modules in Scope (MVP)

### 3.1 User Management

| Requirement | Notes |
|---|---|
| User registration (email + password) | |
| Email verification | Required before first login |
| User login / logout | |
| Password reset via email | |
| Edit profile | Name, preferred currency, timezone, gender, etc |
| Delete account | Soft delete — preserves data integrity |
| Session management | JWT-based |

**Future-ready considerations:**
- OAuth login (Google, Apple)
- Biometric / PIN unlock
- MFA
- User roles (owner, collaborator) for budget sharing
- Multi-user household grouping

---

### 3.2 Account Management

A financial **account** represents a source or destination of money (e.g. checking account, cash wallet, credit card).

Accounts are their own module — each account type has distinct behavior and future complexity (e.g. credit cards have limits and statement cycles, investment accounts have positions).

**Account types (MVP):**
- Cash
- Checking
- Savings
- Credit Card 

**Core fields per account:**

| Field | Type | Notes |
|---|---|---|
| Name | String | User-defined |
| Type | Enum | cash / checking / savings / credit_card |
| Currency | String | ISO 4217 code — the account's base currency; defaults to user base currency |
| Initial balance | Decimal | Starting balance in account base currency |
| Current balance | Decimal | Stored incrementally in account base currency; records in other currencies contribute via their `base_amount` |
| Include in stats | Boolean | Exclude account from totals/statistics |
| Archived | Boolean | Hide without deleting |
| Metadata | JSONB | Extensible — future fields (e.g. credit limit, institution name, account number last 4) stored here without schema changes |
| Created at / Updated at | Timestamp | System-managed |

**Future-ready considerations:**
- Overdraft accounts
- Loan / mortgage accounts
- Investment accounts (stocks, ETF, crypto)
- Bank connectivity (open banking / CSV import)
- Hide balance toggle

---

### 3.3 Category Management

Categories classify records. Unlike other apps, users can create their own categories in addition to the system-provided defaults.

**Design decisions:**
- Two-level hierarchy: **Category → Subcategory**
- System-provided default categories (income and expense sets) are editable display names but not deletable
- Users can create custom categories and subcategories freely
- Categories are typed: **income** or **expense** 
- Each category has a default **nature** that can be overridden per record at entry time

**Nature by record type:**

| Record type | Nature options | Description |
|---|---|---|
| Expense | `must` | Non-negotiable essential spending — rent, utilities, loan repayments, healthcare |
| Expense | `need` | Important but with some flexibility — groceries, transport, subscriptions |
| Expense | `want` | Discretionary spending — dining out, hobbies, entertainment, travel, gifts |
| Income | `active` | Income earned through work — salary, freelance, consulting |
| Income | `passive` | Income without direct effort — rental, dividends, interest |
| Income | `windfall` | One-time or unexpected — bonus, gift, tax refund, sale |

**Core fields per category:**

| Field | Type | Notes |
|---|---|---|
| Name | String | |
| Type | Enum | income / expense |
| Default nature | Enum | must / need / want for expense; active / passive / windfall for income |
| Icon | String | Icon identifier (emoji or icon set key) |
| Color | String | Hex color for UI |
| Parent category | Reference | Null if top-level |
| Is system default | Boolean | System defaults visible to all users |
| Owner | Reference | Null for system defaults; user ID for custom |
| Archived | Boolean | |

---

### 3.4 Tag Management

Tags are user-defined freeform labels applied to records. Unlike categories (structured, typed), tags are flexible and personal.

| Requirement | Notes |
|---|---|
| Create, rename, delete tags | |
| Apply multiple tags to a single record | |
| Filter records by tag | |
| Tags are per-user | Not shared by default |

---

### 3.5 Record Management

A **record** is any financial transaction entered by the user.

**Record types:**
- **Income** — money received (salary, freelance, gift, loan received)
- **Expense** — money spent, including any payment to another person (split settlement, rent share, loan repayment, gift); the category describes the nature of the expense
- **Transfer** — money moved exclusively between the user's own accounts, or to an external untracked destination (e.g. cash withdrawal); never used for payments to other people

**Core fields per record:**

| Field | Type | Notes |
|---|---|---|
| Type | Enum | income / expense / transfer |
| Amount | Decimal | Always positive; in the record's own currency |
| Currency | String | ISO 4217; defaults to account currency but can be any currency |
| Exchange rate | Decimal | Rate from record currency to account base currency at time of entry; 1.0 if same currency |
| Base amount | Decimal | Amount converted to account base currency (amount × exchange_rate); used for balance and reporting |
| Date | DateTime | Full datetime, defaults to now |
| Account | Reference | Source account |
| Destination account | Reference | Transfers only — must be the user's own account; null if transferring out of app (e.g. external cash withdrawal) |
| Category | Reference | Required for income/expense; optional for transfer |
| Subcategory | Reference | Optional |
| Tags | Array | User-defined, optional |
| Note | String | Free text, optional |
| Nature | Enum | Expense: must / need / want — Income: active / passive / windfall — defaults from category, overridable per record; null for transfers |
| Status | Enum | uncleared / cleared / reconciled (default: uncleared) |
| Payment type | Enum | cash / card / bank_transfer / other (optional) |
| Split | Object | See Section 3.6; null if not a split record |
| Metadata | JSONB | Extensible — future fields (receipt photo URL, merchant, GPS, template ref, recurring rule ref) without schema changes |
| Created at / Updated at | Timestamp | System-managed |

**Capabilities:**
- Create, read, update, delete any record
- Filter and search by: date range, type, account, category, tag, status
- Paginated list view optimized for mobile
- Clone a record (duplicate with editable fields)

**Transfer design — two linked records:**
A transfer creates two records atomically: a money-out record on the source account and a money-in record on the destination account. They share a `transfer_ref` identifier so they can always be found and displayed together as a single transfer. Editing or deleting one side also affects the other. If the destination is external (outside the app), only the money-out record is created.

**Cross-user payments are always expenses, not transfers:**
Any money sent to another person is an expense on the sender's side, regardless of intent (split settlement, rent share, loan repayment, gift). The sender picks the appropriate category. The receiver records it as income or as split settlement on their side. A payment request mechanism (Phase 2) coordinates the flow without exposing either party's account details.

**Future-ready considerations:**
- Recurring / scheduled records
- Automatic categorization rules
- Automatic transfer rules (e.g. auto-contribute to savings goal on payday)
- Bulk edit
- Receipt photo attachment (via metadata field)
- CSV import / export
- Templates

---

### 3.6 Debt / Split Tracking *(Lightweight — MVP-adjacent)*

Split tracking is built into the record model from day one but surfaced as a lightweight feature in MVP. No separate module is required.

A record marked as "split" tracks how its cost is shared with other people.

**Split modes:**

| Mode | Description |
|---|---|
| Equal split | Total divided equally among all participants (including the record owner) |
| Percentage split | Each participant assigned a percentage of the total |
| Specific amount | Each participant assigned a fixed amount; owner's share is total minus all other shares, or also specified explicitly |

**Participant fields:**

| Field | Type | Notes |
|---|---|---|
| Name | String | Display name |
| Email | String | Optional — used to link to an app user later |
| Share mode | Enum | equal / percentage / amount |
| Share value | Decimal | Percentage (0–100) or fixed amount depending on mode |
| Total paid | Decimal | What this participant actually paid up front |
| Paid by user | Decimal | What the record owner paid on behalf of this participant |
| Settled | Boolean | Has this participant paid back their share |
| Settled at | DateTime | Optional timestamp when marked settled |
| Linked user | Reference | Optional — if participant later creates an account, link here |

**Design rules:**
- No requirement for other participants to have an app account
- If a participant has an email and later registers, the system can optionally offer to link their participation records
- The owner's share is always tracked — the split must account for 100% of the total

**Future-ready considerations:**
- Participant-facing view (shared link to see what they owe)
- Sync when both parties use the app
- Group expenses (multi-record debt tracking)

---

## 3.7 Budgets *(Phase 2 Module)*

A **budget** is a rule that tracks spending or saving progress against a target, over a defined period or toward a future goal.

**Budget types:**

| Type | Description |
|---|---|
| Spending limit | Cap spending in a category or set of categories per period (e.g. "max $300/month on dining") |
| Savings goal | Accumulate a target amount by a future date (e.g. "save $2,000 for a trip by December") |
| Income target | Track progress toward an expected income amount per period |

**Core fields per budget:**

| Field | Type | Notes |
|---|---|---|
| Name | String | User-defined (e.g. "Europe Trip 2027") |
| Type | Enum | spending_limit / savings_goal / income_target |
| Target amount | Decimal | The limit or goal amount |
| Currency | String | ISO 4217 |
| Period | Enum | monthly / weekly / custom / one-time |
| Period start | Date | For recurring budgets, the day the period resets |
| Start date | Date | When tracking begins |
| End date | Date | Optional — for goal-based budgets |
| Linked categories | Array | Records in these categories count toward this budget |
| Linked accounts | Array | Only records in these accounts count (optional filter) |
| Linked tags | Array | Optional additional filter by tag |
| Current progress | Decimal | Computed from linked records |
| Shared with | Array | Future — user references for collaborative budgets |
| Metadata | JSONB | Extensible |
| Created at / Updated at | Timestamp | System-managed |

**Capabilities:**
- Create, read, update, delete budgets
- Visual progress indicator (amount used vs. target)
- Early warning alerts when approaching limit (configurable threshold, e.g. 80%)
- Budget period auto-reset for recurring budgets
- Dashboard summary of active budgets

**Design rules:**
- A record can count toward multiple budgets simultaneously
- Budgets are non-destructive — they observe records, never block entry
- Savings goal budgets are funded by transfers: the user manually transfers income into the goal's linked account; the budget tracks the accumulated balance toward the target
- Automatic contribution rules (e.g. "transfer $200 on the 1st of every month to this goal") are a Phase 2 addition built on top of the recurring records feature
- Future spending outlook/forecasting can classify goal contributions as a distinct record subtype for clearer reporting

**Future-ready considerations:**
- Collaborative budgets (multiple users contribute to / are limited by the same budget)
- Budget templates (e.g. "50/30/20 rule")
- Rollover unspent amounts to next period
- Push / email notifications for threshold alerts
- Budget vs. actual reporting and history

---

## 4. Out of Scope for MVP

| Feature | Notes |
|---|---|
| Budget planning and limits | Designed above — Phase 2 |
| Recurring / scheduled transactions | Phase 2 |
| Stock / investment account types | Phase 2 |
| Crypto support | Phase 3 |
| AI-driven recommendations and alerts | Future |
| Bank integrations / auto-sync | Future |
| CSV import / export | Phase 2 |
| Receipt OCR | Future |
| Native mobile app | Future |
| Multi-user shared budgets | Phase 2 |
| Multi-currency conversion reporting | Phase 2 — data model supports it from day one; cross-account totals in a single currency come later |
| Live exchange rate lookup | Phase 2 — MVP requires manual rate entry; Phase 2 auto-populates via exchange rate API (e.g. Open Exchange Rates, ExchangeRate-API, or ECB) at record entry time; stored rate is always editable so user can override with the actual rate they received |
| Goals / savings goals | Phase 2 |
| Shopping list | Future |
| Warranty tracker | Future |
| Dashboard widgets / customization | Phase 2 |
| Statistics and reports | Phase 2 |
| PWA / offline support | Phase 2 |

---

## 5. Non-Functional Requirements

| Requirement | Decision |
|---|---|
| Platform | Web, mobile-optimized |
| Authentication | JWT-based, secure |
| Data ownership | User owns their data; export planned (not MVP) |
| Scalability | Single-user at launch; multi-user data model from day one |
| Stack | Open source preferred; AWS where practical and cost-effective |
| Database | Managed Postgres — Neon preferred over RDS for cost |
| Backend languages | Node.js (primary), Java, Python |
| Frontend | TBD — technical design phase |
| Balance storage | Stored and updated incrementally on each record mutation |
| Availability | Best-effort for personal use; SLA not required at MVP |

---

## 6. Decisions Log

Previously open questions, now resolved:

| # | Question | Decision |
|---|---|---|
| 1 | Default categories | Ship with a curated default set (categories + subcategories). Users can rename, archive, and add their own. System defaults are not deletable. |
| 2 | Transfer records | Two linked records (debit + credit) sharing a `transfer_ref`. External transfers (out of app) create only the debit record. |
| 3 | Balance computation | Stored and updated incrementally on each record create/update/delete. Faster at scale; requires care to keep consistent on mutations. |
| 4 | Backend stack | Node.js and Java as primary backend languages; Python available for tooling/scripts. Frontend TBD in technical design. |
| 5 | Cross-user payments | Any payment to another person (split settlement, rent share, loan repayment) is an expense on the sender's side — Transfer is strictly own-account-to-own-account. Category describes the nature of the payment. |

---

## 7. Decisions Log (continued)

| # | Question | Decision |
|---|---|---|
| 6 | Frontend framework | React (required); Next.js as the framework — SSR support, mobile-optimized, strong ecosystem |
| 7 | Service architecture | Microservices from day one |
| 8 | Default category set | Deferred to implementation time |
| 9 | Authentication | Amazon Cognito — free up to 50k MAU, handles JWT/email verification/password reset/MFA/OAuth, fits AWS preference |
