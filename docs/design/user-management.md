# User Management — Module Design

**Version:** 0.2 (Draft)
**Date:** 2026-07-06
**Status:** In Review
**References:** [High-Level Requirements](../requirements.md)

---

## 1. Overview

The User Management module handles registration, authentication, session lifecycle, and profile management for all users of MiFeria. It is the foundational module — every other module depends on it for identity.

Authentication is implemented in-house using battle-tested libraries for all cryptographic operations — we never write our own crypto primitives. This approach maximises learning while maintaining security correctness.

**Core libraries:**
- `bcrypt` — password hashing (never store or compare plaintext passwords)
- `jsonwebtoken` — JWT signing and verification
- `nodemailer` — transactional email (verification, password reset) via AWS SES

---

## 2. Core Concepts

### 2.1 Passwords and Hashing

When a user registers, their password is never stored. Instead:

1. A random **salt** is generated (bcrypt does this automatically)
2. The password is run through **bcrypt** with the salt — producing a fixed-length hash
3. Only the hash is stored in the database

On login, bcrypt re-hashes the submitted password with the stored salt and compares. If the hashes match, the password is correct. An attacker who steals the database gets only hashes — useless without the original passwords.

```
"mypassword123" + salt → bcrypt → "$2b$12$X4kv7j..." (stored)
```

### 2.2 JWT Tokens

After a successful login the server issues a **JSON Web Token (JWT)**. A JWT has three parts:

```
header.payload.signature
```

- **Header** — algorithm used to sign (`HS256` or `RS256`)
- **Payload** — claims: who the user is, when the token expires (`sub`, `exp`, `iat`)
- **Signature** — cryptographic proof the token was issued by this server and hasn't been tampered with

The client sends the JWT on every request. The server validates the signature — no database lookup needed. This is what makes JWTs **stateless**.

### 2.3 Access Token + Refresh Token

Two tokens are issued at login:

| Token | Lifespan | Purpose |
|---|---|---|
| **Access token** | 15 minutes | Sent with every API request as `Authorization: Bearer <token>` |
| **Refresh token** | 30 days | Stored securely; used only to get a new access token when it expires |

Short-lived access tokens limit damage if one is stolen — it expires quickly. The refresh token is long-lived but only ever sent to one endpoint (`/auth/refresh`), reducing its exposure surface.

### 2.4 Email Verification and Password Reset Tokens

These are **not JWTs** — they are random, single-use, time-limited tokens stored in the database:

1. Generate a cryptographically random token (`crypto.randomBytes`)
2. Hash it before storing (same principle as passwords — the DB holds only the hash)
3. Email the raw token to the user as a link/code
4. On submission, hash what the user sent and compare to the stored hash
5. Mark as used — can never be reused

---

## 3. Architecture

### 3.1 Service Boundaries

User Management is its own microservice responsible for:
- All auth flows (register, login, refresh, logout, verify, password reset)
- Owning user profile data in the application database
- Issuing JWTs that other services validate independently

```
Client (React/Next.js)
        │
        ▼
┌─────────────────────┐
│   User Service      │  ← Node.js / Express
│   (REST API)        │
└──────────┬──────────┘
           │                    ┌──────────────────┐
           ├───────────────────▶│   Neon Postgres   │  Users, tokens
           │                    └──────────────────┘
           │                    ┌──────────────────┐
           └───────────────────▶│   AWS SES         │  Transactional email
                                └──────────────────┘
```

Other microservices validate JWTs directly using the shared **JWT public key** — they never call User Service on every request.

---

## 4. Data Model

### 4.1 Users Table

```sql
CREATE TABLE users (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email             TEXT        UNIQUE NOT NULL,
  password_hash     TEXT        NOT NULL,
  name              TEXT        NOT NULL,
  email_verified    BOOLEAN     NOT NULL DEFAULT false,
  base_currency     CHAR(3)     NOT NULL DEFAULT 'MXN',
  timezone          TEXT        NOT NULL DEFAULT 'UTC',
  period_start_day  SMALLINT    NOT NULL DEFAULT 1,  -- 1–28
  deleted_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 4.2 Refresh Tokens Table

Refresh tokens are stored so they can be invalidated on logout or rotation.

```sql
CREATE TABLE refresh_tokens (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash   TEXT        UNIQUE NOT NULL,  -- hashed before storage
  expires_at   TIMESTAMPTZ NOT NULL,
  revoked_at   TIMESTAMPTZ,                  -- set on logout or rotation
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Refresh token rotation:** every time a refresh token is used to get a new access token, the old refresh token is revoked and a new one is issued. This means a stolen refresh token can only be used once before it's invalidated.

### 4.3 Verification Tokens Table

Used for both email verification and password reset flows.

```sql
CREATE TABLE verification_tokens (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type         TEXT        NOT NULL,  -- 'email_verification' | 'password_reset'
  token_hash   TEXT        UNIQUE NOT NULL,
  expires_at   TIMESTAMPTZ NOT NULL,
  used_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## 5. API Endpoints

Base path: `/api/v1/auth` and `/api/v1/users`

### 5.1 Register

**`POST /api/v1/auth/register`**

1. Validate input (email format, password strength)
2. Check email not already registered
3. Hash password with bcrypt (`bcrypt.hash(password, 12)` — cost factor 12)
4. Insert user row (`email_verified = false`)
5. Generate verification token, hash it, store in `verification_tokens`
6. Send verification email via SES with raw token as a link

Request:
```json
{
  "email": "user@example.com",
  "password": "SecurePass1!",
  "name": "Dan"
}
```

Response `201`:
```json
{ "message": "Check your email to verify your account." }
```

Errors: `409` email taken — `400` validation failed

---

### 5.2 Verify Email

**`POST /api/v1/auth/verify-email`**

1. Look up `verification_tokens` by hashing the submitted token
2. Check not expired, not already used, type = `email_verification`
3. Set `users.email_verified = true`
4. Mark token as used (`used_at = now()`)

Request:
```json
{
  "token": "raw-token-from-email"
}
```

Response `200`:
```json
{ "message": "Email verified. You can now log in." }
```

---

### 5.3 Login

**`POST /api/v1/auth/login`**

1. Find user by email
2. Check `email_verified = true`
3. Compare submitted password against stored hash (`bcrypt.compare`)
4. Sign access token JWT (`exp: 15min`, `sub: user.id`)
5. Generate refresh token, hash and store in `refresh_tokens`
6. Return both tokens

Request:
```json
{
  "email": "user@example.com",
  "password": "SecurePass1!"
}
```

Response `200`:
```json
{
  "access_token": "eyJ...",
  "refresh_token": "...",
  "expires_in": 900
}
```

Errors: `401` invalid credentials (same message whether email or password is wrong — never reveal which) — `403` email not verified

---

### 5.4 Refresh Token

**`POST /api/v1/auth/refresh`**

1. Hash the submitted refresh token
2. Look it up in `refresh_tokens` — check not revoked, not expired
3. Revoke the old token (`revoked_at = now()`)
4. Issue a new access token and a new refresh token (rotation)

Request:
```json
{ "refresh_token": "..." }
```

Response `200`:
```json
{
  "access_token": "eyJ...",
  "refresh_token": "...",
  "expires_in": 900
}
```

---

### 5.5 Logout

**`POST /api/v1/auth/logout`**

Requires: `Authorization: Bearer <access_token>`

1. Revoke the submitted refresh token
2. Access token expires naturally (15 min max exposure)

Request:
```json
{ "refresh_token": "..." }
```

Response `204`

---

### 5.6 Forgot Password

**`POST /api/v1/auth/password/forgot`**

1. Look up user by email
2. If found: generate reset token, hash and store, send email
3. If not found: do nothing — but always return the same response (prevents email enumeration)

Request:
```json
{ "email": "user@example.com" }
```

Response `200` always:
```json
{ "message": "If that email is registered you will receive a reset link shortly." }
```

---

### 5.7 Reset Password

**`POST /api/v1/auth/password/reset`**

1. Hash submitted token, look up in `verification_tokens`
2. Check not expired, not used, type = `password_reset`
3. Hash new password with bcrypt
4. Update `users.password_hash`
5. Mark token used
6. Revoke all existing refresh tokens for this user (force re-login everywhere)

Request:
```json
{
  "token": "raw-token-from-email",
  "new_password": "NewSecurePass1!"
}
```

Response `200`:
```json
{ "message": "Password updated. Please log in." }
```

---

### 5.8 Get Profile

**`GET /api/v1/users/me`**

Requires: `Authorization: Bearer <access_token>`

Response `200`:
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "name": "Dan",
  "base_currency": "USD",
  "timezone": "America/New_York",
  "period_start_day": 1,
  "created_at": "2026-07-06T00:00:00Z"
}
```

---

### 5.9 Update Profile

**`PATCH /api/v1/users/me`**

Requires: `Authorization: Bearer <access_token>`

All fields optional:
```json
{
  "name": "Daniel",
  "base_currency": "EUR",
  "timezone": "Europe/Madrid",
  "period_start_day": 15
}
```

Response `200` — updated profile object.

---

### 5.10 Delete Account

**`DELETE /api/v1/users/me`**

Requires: `Authorization: Bearer <access_token>`

1. Set `deleted_at = now()` (soft delete)
2. Revoke all refresh tokens for this user

Response `204`

---

## 6. Password Policy

Enforced at the application layer on registration and password reset:

- Minimum 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character

---

## 7. Security Considerations

| Concern | Mitigation |
|---|---|
| Password storage | bcrypt with cost factor 12 — never stored in plaintext |
| Brute force on login | Rate limit `/auth/login` by IP (e.g. 10 attempts / 15 min) |
| Token theft (access) | Short 15-min expiry limits damage window |
| Token theft (refresh) | Rotation — stolen token invalidated on first legitimate refresh |
| Email enumeration | Forgot password always returns 200; login error never reveals which field is wrong |
| Verification token interception | Tokens are hashed before storage — raw token only ever in the email |
| Mass account reset after breach | Password reset revokes all refresh tokens for the user |
| HTTPS | All endpoints TLS-only; enforced at infrastructure level |

---

## 8. Future Considerations

- OAuth / social login (Google, Apple) — add alongside existing email/password, not replace
- MFA / TOTP — time-based one-time passwords (e.g. Google Authenticator)
- Biometric / PIN — client-side convenience layer; backend auth unchanged
- Account data export before deletion
- Permanent deletion scheduled job after retention period

---

## 9. Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Token storage on client | Hybrid — access token in memory, refresh token in httpOnly cookie | Access token is short-lived (15 min) so losing it on page refresh is fine; httpOnly cookie protects the long-lived refresh token from XSS |
| 2 | JWT signing algorithm | RS256 — private key signs (User Service only), public key verifies (all other services) | Microservices can verify tokens without being able to forge them; private key never leaves User Service |
| 3 | Deployment | AWS Lambda | Scales to zero cost when idle; fits personal use traffic pattern |
| 4 | Rate limiting | In-process (e.g. `express-rate-limit`) | Zero extra infrastructure; sufficient for single-instance Lambda; migrate to Redis if traffic grows |
