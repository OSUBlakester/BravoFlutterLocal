# Email Backend Handoff Checklist (Web App)

This checklist covers the `BRAVO EMAIL PHASE 2` backend block in `existingbackend/server.py` in this Flutter repo.

For Web App handoff: copy that block into your Web App backend file `server.py`.

## Required Environment Variables

Set these in the Web App backend environment before enabling email:

- `EMAIL_FEATURE_ENABLED=true`
- `GOOGLE_OAUTH_CLIENT_ID=<google oauth client id>`
- `GOOGLE_OAUTH_CLIENT_SECRET=<google oauth client secret>`
- `EMAIL_OAUTH_STATE_SECRET=<long-random-secret>`
- `EMAIL_TOKEN_ENCRYPTION_KEY=<fernet-key>`
- `EMAIL_OAUTH_REDIRECT_URI=<optional override>`

Notes:
- If `EMAIL_OAUTH_REDIRECT_URI` is omitted, backend defaults to `${DOMAIN}/api/email/oauth/callback`.
- Startup fails fast when `EMAIL_FEATURE_ENABLED=true` and any required email env var is missing/invalid (`GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `EMAIL_OAUTH_STATE_SECRET`, `EMAIL_TOKEN_ENCRYPTION_KEY`).

## Generate `EMAIL_TOKEN_ENCRYPTION_KEY`

Use Python once:

```bash
python3 - <<'PY'
from cryptography.fernet import Fernet
print(Fernet.generate_key().decode())
PY
```

## Google OAuth Setup

- Authorized redirect URI must include:
  - `https://<your-domain>/api/email/oauth/callback`
- Gmail API and People API must be enabled in Google Cloud.
- OAuth consent screen scopes required:
  - `https://www.googleapis.com/auth/gmail.readonly`
  - `https://www.googleapis.com/auth/gmail.send`
  - `https://www.googleapis.com/auth/contacts.readonly`

## Smoke Test Prereqs

Set once in shell:

```bash
export BASE_URL="https://<your-domain>"
export FIREBASE_ID_TOKEN="<user-id-token>"
export AAC_USER_ID="<aac-user-id>"
```

Common headers:

```bash
-H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
-H "X-User-ID: $AAC_USER_ID" \
-H "Content-Type: application/json"
```

## Endpoint Smoke Tests

### 1) Status

```bash
curl -s "$BASE_URL/api/email/status" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

Expected:
- `provider_status.gmail.connected` is `false` before connect.

### 2) Connect URL (empty body allowed)

```bash
curl -s -X POST "$BASE_URL/api/email/connect-url" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" \
  -H "Content-Type: application/json" | jq
```

Expected:
- Returns `connect_url`.
- Open returned URL in browser and complete Google consent.

Optional explicit provider body:

```bash
curl -s -X POST "$BASE_URL/api/email/connect-url" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"provider":"gmail"}' | jq
```

### 3) Status after OAuth callback

```bash
curl -s "$BASE_URL/api/email/status" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

Expected:
- `provider_status.gmail.connected` is `true`.
- `provider_status.gmail.email_address` is non-empty.

### 4) Inbox

```bash
curl -s "$BASE_URL/api/email/inbox?max_results=10" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

Expected:
- `messages` array with items containing `subject`, `from`, `snippet`.

### 5) Contacts

```bash
curl -s "$BASE_URL/api/email/contacts?max_results=25" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

Expected:
- `contacts` array with `name` + `email`.

### 6) Send

```bash
curl -s -X POST "$BASE_URL/api/email/send" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "to": ["recipient@example.com"],
    "cc": [],
    "bcc": [],
    "subject": "Bravo email test",
    "body": "Hello from Bravo backend smoke test."
  }' | jq
```

Expected:
- `status: "sent"` with `id` and `thread_id`.

### 7) Disconnect / Revoke

```bash
curl -s -X POST "$BASE_URL/api/email/disconnect" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

Expected:
- `status: "disconnected"`.
- Follow-up `/api/email/status` shows disconnected.

## Quick Troubleshooting

- `500 EMAIL_OAUTH_STATE_SECRET is required...`
  - Missing `EMAIL_OAUTH_STATE_SECRET`.
- `500 EMAIL_TOKEN_ENCRYPTION_KEY is required...` or invalid key
  - Missing/bad Fernet key.
- OAuth callback errors (`profile fetch failed`)
  - Check Gmail API enabled, consent scopes, and redirect URI match.
- `400 Gmail refresh token missing`
  - Reconnect with Google consent (`prompt=consent`) and ensure offline access.
