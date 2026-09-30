# MiFeria App — Agent Handoff

## Project summary

MiFeria is a personal budget and expense tracker web app. It is a **solo learning project** — the developer (Dani) wants to learn web development from end to end while building a real product. The app is inspired by Wallet by BudgetBakers but addresses specific pain points with that app.

The codebase is at `/home/danielsalinas228/workplace/miferiaapp`. It is currently empty — no code has been written yet. All work so far has been requirements and design documentation under `docs/`.

---

## Documentation written so far

| File | Contents |
|---|---|
| `docs/requirements.md` | Full high-level requirements for all MVP modules and Phase 2 features, plus all decisions made so far |
| `docs/design/user-management.md` | Detailed backend design for the User Management module — the first module to be built |

Read both files before doing anything. They are the source of truth.

---

## Key product decisions (do not re-open these)

1. **Transfer = own accounts only.** Any payment to another person (split, rent share, loan repayment, gift) is an **expense** on the sender's side. Category describes the nature. This was explicitly decided and locked.
2. **Record has two currency fields.** `amount` + `currency` (what the user entered) and `base_amount` + `exchange_rate` (converted to account base currency). This supports foreign currency records on any account.
3. **Transfers create two linked records** sharing a `transfer_ref` (money-out on source, money-in on destination). External transfers (cash withdrawal) create only the money-out record.
4. **Account balance stored incrementally** — updated on every record mutation, not recomputed.
5. **Categories have a `nature` default** (expense: `must/need/want`; income: `active/passive/windfall`) that can be overridden per record.
6. **No Cognito** — auth is rolled in-house using `bcrypt` + `jsonwebtoken`. This is intentional for learning purposes.
7. **Same domain** — frontend and API share one domain (`/api/v1/...` prefix). No separate subdomain.

---

## Stack decisions (locked)

| Layer | Choice | Notes |
|---|---|---|
| Frontend | React + Next.js | Mobile-optimized web |
| Backend | Node.js (primary), Java, Python | User Service in Node.js |
| Database | Neon (managed Postgres) | Cost-effective RDS alternative |
| Auth | Roll-your-own with `bcrypt` + `jsonwebtoken` | RS256 JWT signing |
| Token storage | Hybrid | Access token in memory; refresh token in httpOnly cookie |
| Deployment | AWS Lambda | Scales to zero; fits personal use |
| Email | AWS SES | Transactional email for verification and reset |
| Rate limiting | In-process (`express-rate-limit`) | Migrate to Redis later if needed |
| Architecture | Microservices | Each module is its own service |
| Infrastructure | AWS + open source | No Amazon-internal tooling |

---

## What to build next

The next step is implementing the **User Management microservice** (Node.js / Express on AWS Lambda). The full design is in `docs/design/user-management.md`. Read it carefully — it includes the data model, all API endpoints with request/response shapes, security considerations, and the decisions log.

**Implementation order within User Management:**
1. Project scaffold — Node.js / Express, folder structure, environment config
2. Database setup — Neon Postgres connection, migrations for `users`, `refresh_tokens`, `verification_tokens` tables
3. Auth endpoints — register, verify email, login, refresh, logout
4. Password reset endpoints — forgot password, reset password
5. Profile endpoints — get, update, delete
6. Middleware — JWT validation, rate limiting
7. Integration with AWS SES for email sending

---

## Developer profile

- Dan is learning web development — he is not a frontend expert. Explain concepts when introducing anything non-obvious, especially on the frontend.
- He has backend exposure (Java/Node.js) but is building full-stack from scratch.
- He prefers understanding over magic — when you make a decision, briefly explain why so he learns from it.
- The project uses only open source tools and AWS. No Amazon-internal tooling (no Brazil, Pipelines, CRUX, BuilderHub, etc.).
- Budget is limited — prefer cost-effective AWS services (Lambda over EC2, Neon over RDS, SES over SendGrid).
- Pace is slow by design — this is a learning project, not a sprint.

---

## Conventions established

- All docs live in `docs/` — requirements in `docs/requirements.md`, module designs in `docs/design/<module>.md`
- No proprietary tooling
- Avoid accounting jargon (e.g. say "money-out record" not "debit") — Dan flagged this explicitly
- When adding fields to entities, always consider whether `metadata JSONB` is the right home for extensible future fields
- Soft delete everywhere — `deleted_at` timestamp, never hard delete user data
