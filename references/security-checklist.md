# Security Checklist — Mandatory Invariants

## 1. Threat Modeling & Pre-Commit Gate
- [ ] Map trust boundaries (HTTP inputs, webhooks, file uploads, third-party APIs, LLM outputs, untrusted IPC).
- [ ] Zero secrets in Git index (`git diff --cached` free of API keys, tokens, passwords, private keys).
- [ ] `.gitignore` excludes `.env*`, `*.pem`, `*.key`.

## 2. Authentication & Authorization
- [ ] Passwords hashed via Argon2, scrypt, or bcrypt (≥ 12 rounds).
- [ ] Session cookies enforce `HttpOnly`, `Secure`, `SameSite=Lax|Strict`, and explicit TTL.
- [ ] Login and token endpoints enforce rate limiting.
- [ ] Every protected route verifies both authentication and resource ownership/role (anti-IDOR).
- [ ] JWTs validate signature, algorithm allowlist, `exp`, and `iss`/`aud`.

## 3. Input, Query & Path Containment
- [ ] Allowlist validation at system boundaries (schema, type, length, numeric bounds).
- [ ] Parameterized queries only (zero string concatenation in SQL/NoSQL/OS commands).
- [ ] Context-aware output encoding; restrictive CSP (`default-src 'self'`), HSTS, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and explicit CORS origin allowlist (never `*` with credentials).
- [ ] Outbound server-side fetches validate URLs against an allowlist and block private/link-local CIDRs (anti-SSRF).
- [ ] Destructive path operations resolve symlinks first (`realpath`), verify containment inside an allowlisted root with minimum depth ≥ 1, and verify ownership before mutation.

## 4. Supply-Chain & Dependency Gate
- [ ] Single authoritative lockfile committed per workspace; CI runs frozen installs (`npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`).
- [ ] Lifecycle scripts (`postinstall`) disabled or gated by default (`--ignore-scripts` / `strict-allow-scripts` / `strictDepBuilds: true`) until package source and provenance are audited.

## 5. Error Handling & AI/LLM Boundaries
- [ ] Production responses return generic error payloads (zero stack traces, SQL queries, or internal paths).
- [ ] Sensitive fields (`passwordHash`, tokens, PII) stripped from responses and logs.
- [ ] LLM outputs treated as untrusted data: never passed to `eval`, shell, SQL, `innerHTML`, or file paths; enforce permissions in code, not prompts; bound token/loop budgets.
