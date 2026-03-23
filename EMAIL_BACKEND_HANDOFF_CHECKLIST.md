# Email Backend Handoff Checklist (Web App)

This checklist covers the `BRAVO EMAIL PHASE 2` backend block in `existingbackend/server.py` in this Flutter repo.

For Web App handoff: copy that block into your Web App backend file `server.py`.

## Required Environment Variables

Set these before enabling email:

- `EMAIL_FEATURE_ENABLED=true`
- `GOOGLE_OAUTH_CLIENT_ID=<google oauth client id>`
- `GOOGLE_OAUTH_CLIENT_SECRET=<google oauth client secret>`
- `EMAIL_OAUTH_STATE_SECRET=<long-random-secret>`
- `EMAIL_TOKEN_ENCRYPTION_KEY=<fernet-key>`
- `EMAIL_OAUTH_REDIRECT_URI=<optional override>`

Notes:
- If `EMAIL_OAUTH_REDIRECT_URI` is omitted, backend defaults to `${DOMAIN}/api/email/oauth/callback`.
- Startup fails fast when `EMAIL_FEATURE_ENABLED=true` and required email env vars are missing/invalid.

## Generate `EMAIL_TOKEN_ENCRYPTION_KEY`

```bash
python3 - <<'PY'
from cryptography.fernet import Fernet
print(Fernet.generate_key().decode())
PY
```

## Google OAuth Setup

- Authorized redirect URI must include:
  - `https://<your-domain>/api/email/oauth/callback`
- Enable Gmail API and People API in Google Cloud.
- OAuth consent scopes:
  - `https://www.googleapis.com/auth/gmail.readonly`
  - `https://www.googleapis.com/auth/gmail.send`
  - `https://www.googleapis.com/auth/contacts.readonly`

## Smoke Test Prereqs

```bash
export BASE_URL="https://<your-domain>"
export FIREBASE_ID_TOKEN="<user-id-token>"
export AAC_USER_ID="<aac-user-id>"
```

## Endpoint Smoke Tests

### Status

```bash
curl -s "$BASE_URL/api/email/status" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

### Connect URL (empty body supported)

```bash
curl -s -X POST "$BASE_URL/api/email/connect-url" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" \
  -H "Content-Type: application/json" | jq
```

### Inbox

```bash
curl -s "$BASE_URL/api/email/inbox?max_results=10" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

### Contacts

```bash
curl -s "$BASE_URL/api/email/contacts?max_results=25" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

### Send

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

### Disconnect / Revoke

```bash
curl -s -X POST "$BASE_URL/api/email/disconnect" \
  -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  -H "X-User-ID: $AAC_USER_ID" | jq
```

## Troubleshooting

- `GOOGLE_OAUTH_CLIENT_ID is required...` / `GOOGLE_OAUTH_CLIENT_SECRET is required...`
  - Missing OAuth app credentials in environment.
- `EMAIL_OAUTH_STATE_SECRET is required...`
  - Missing OAuth state signing secret.
- `EMAIL_TOKEN_ENCRYPTION_KEY...`
  - Missing/invalid Fernet key or `cryptography` package.
- `Invalid email address: ...`
  - Bad `to`, `cc`, or `bcc` address format in send request.
