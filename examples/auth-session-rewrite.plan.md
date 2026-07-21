# Auth Session Rewrite

## Context

The current session store mixes cookie issuance, refresh rotation, and logout into a single module. Agents keep patching edge cases in place, which has made the flow hard to reason about and easy to break.

## Goals

1. Split session responsibilities into clear interfaces.
2. Preserve existing client cookies during migration (no forced re-login for active users).
3. Keep logout idempotent even when refresh tokens are already revoked.
4. Make the happy path and failure path explicit enough for agent review.

## Non-Goals

- Redesigning the login UI
- Changing OAuth providers
- Multi-region session replication

## Proposed Design

### Interfaces

```text
SessionStore
  Create(user_id) -> Session
  Get(session_id) -> Session | nil
  Revoke(session_id) -> ok

TokenRotator
  Issue(session) -> { access, refresh }
  Rotate(refresh) -> { access, refresh } | error
  RevokeRefresh(refresh) -> ok
```

### Flow

1. Login creates a `Session` and issues access + refresh tokens.
2. Refresh validates the refresh token, rotates it, and updates the session last-seen stamp.
3. Logout revokes the session and best-effort revokes the refresh token.
4. Expired access tokens do not revoke the session by themselves.

### Migration

- Dual-write for one release: old blob + new tables.
- Read preference: new tables first, fall back to old blob.
- After soak, drop dual-write and the legacy blob decoder.

## Open Questions

1. Should refresh rotation be strictly one-time-use, or allow a short grace reuse window for flaky mobile clients?
2. Do we need audit events for every rotate, or only for revoke/logout?
3. Where should "session not found" vs "refresh revoked" map in the HTTP error model?

## Rollout Plan

1. Land interfaces + in-memory fake for tests.
2. Implement Postgres-backed store behind a feature flag.
3. Enable dual-write in staging.
4. Enable dual-write in production for 7 days.
5. Flip read preference to new store.
6. Remove legacy decoder.
