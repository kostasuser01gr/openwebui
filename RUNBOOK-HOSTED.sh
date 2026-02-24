#!/usr/bin/env bash
# =============================================================================
#  OPEN WEBUI — COMPLETE OPERATIONS RUNBOOK
#  Hosted Models Only (OpenRouter / Groq) — No Ollama
#  Generated: 2026-02-24
# =============================================================================
#
#  TABLE OF CONTENTS
#  ─────────────────
#  SECTION A — ASSUMPTIONS
#  SECTION B — ROOT CAUSE HYPOTHESES (RANKED)
#  SECTION C — EVIDENCE / TRIAGE COMMANDS
#  SECTION D — SAFE BACKUP
#  SECTION E — KNOWN-GOOD DEPLOYMENT (BRING-UP)
#  SECTION F — PROVIDER SETUP + TEST COMMANDS
#  SECTION G — FAST FIX (LAYER 1)
#  SECTION H — DEEP REPAIR (LAYER 2)
#  SECTION I — NUCLEAR RESET (LAYER 3)
#  SECTION J — VALIDATION CHECKLIST
#  SECTION K — SECURITY HARDENING
#  SECTION L — COST & ABUSE CONTROL
#  SECTION M — PREVENTION & MAINTENANCE
#  SECTION N — NGINX REVERSE PROXY (OPTIONAL)
#
# =============================================================================

set -euo pipefail
COMPOSE_FILE="docker-compose.hosted.yml"
ENV_FILE=".env.hosted"
CONTAINER="open-webui"
VOLUME="open-webui-data"
PORT="${OPEN_WEBUI_PORT:-3001}"
BACKUP_DIR="$HOME/open-webui-backups"
IMAGE="ghcr.io/open-webui/open-webui:v0.8.5"
IMAGE_PREV="ghcr.io/open-webui/open-webui:v0.8.4"   # rollback target

cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║         OPEN WEBUI — OPERATIONS RUNBOOK (HOSTED ONLY)          ║
║         Image: ghcr.io/open-webui/open-webui:v0.8.5            ║
╚══════════════════════════════════════════════════════════════════╝
BANNER

# =============================================================================
# SECTION A — ASSUMPTIONS
# =============================================================================
cat << 'EOF'

═══ SECTION A — ASSUMPTIONS ═══

1. Docker & Docker Compose v2 installed and working.
2. macOS or Linux host. Port 3001 will be used (3000 is occupied by Grafana).
3. Internet access to pull images and reach hosted providers.
4. OpenRouter is the DEFAULT provider (free tier available).
5. Groq is the FALLBACK provider.
6. No local Ollama — all models are hosted.
7. Team access via browser at http://<HOST_IP>:3001
8. Admin creates user accounts (open registration disabled).
9. Data persists in Docker named volume "open-webui-data".

EOF

# =============================================================================
# SECTION B — ROOT CAUSE HYPOTHESES (RANKED)
# =============================================================================
cat << 'EOF'

═══ SECTION B — ROOT CAUSE HYPOTHESES (RANKED) ═══

 #  | Hypothesis                          | Likelihood | Evidence Command
────┼─────────────────────────────────────┼────────────┼─────────────────────────────
 1  | OPENAI_API_BASE_URL missing /v1     | HIGH       | docker inspect → env vars
 2  | OPENAI_API_KEY invalid or missing   | HIGH       | curl test to provider
 3  | Port conflict (3000 occupied)       | HIGH       | lsof -nP -iTCP:3000
 4  | Container not running / crash loop  | HIGH       | docker ps -a
 5  | Ollama dependency blocking startup  | MEDIUM     | docker-compose logs
 6  | WEBUI_SECRET_KEY empty or changed   | MEDIUM     | docker inspect → env
 7  | Corrupted SQLite DB in volume       | MEDIUM     | docker exec → sqlite check
 8  | Provider rate-limiting (429)        | MEDIUM     | docker logs → 429 errors
 9  | Docker network DNS resolution fail  | LOW        | docker exec → nslookup
 10 | Disk full                           | LOW        | df -h
 11 | Resource exhaustion (OOM)           | LOW        | docker stats --no-stream

EOF

# =============================================================================
# SECTION C — EVIDENCE / TRIAGE COMMANDS
# =============================================================================
cat << 'EVIDENCE'

═══ SECTION C — EVIDENCE / TRIAGE COMMANDS ═══

Run these FIRST to diagnose any issue. Copy the entire block:

───────────────────────────────────────────────────────────
echo "=== 1. ALL CONTAINERS ==="
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}'

echo "=== 2. OPEN WEBUI LOGS (last 300 lines) ==="
docker logs --tail=300 open-webui 2>&1 | tail -100

echo "=== 3. CONTAINER INSPECT (env vars, mounts, network) ==="
docker inspect open-webui --format='{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null
docker inspect open-webui --format='{{json .Mounts}}' 2>/dev/null | python3 -m json.tool

echo "=== 4. RESOURCE USAGE ==="
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'

echo "=== 5. VOLUMES ==="
docker volume ls --filter name=open-webui

echo "=== 6. NETWORKS ==="
docker network ls

echo "=== 7. PORT CONFLICTS ==="
lsof -nP -iTCP:3001 -sTCP:LISTEN 2>/dev/null || echo "Port 3001 is free"
lsof -nP -iTCP:3000 -sTCP:LISTEN 2>/dev/null || echo "Port 3000 is free"

echo "=== 8. DISK SPACE ==="
df -h /

echo "=== 9. MEMORY ==="
vm_stat 2>/dev/null | head -8 || free -h 2>/dev/null

echo "=== 10. HEALTH ENDPOINT ==="
curl -sf http://localhost:3001/health 2>/dev/null && echo " ← HEALTHY" || echo "UNHEALTHY or unreachable"
───────────────────────────────────────────────────────────

EVIDENCE

# =============================================================================
# SECTION D — SAFE BACKUP
# =============================================================================
cat << 'BACKUP_SECTION'

═══ SECTION D — SAFE BACKUP ═══

⚠️  WARNING: ALWAYS backup before ANY destructive change (deep repair, nuclear reset, updates).

─── D1. Identify the Volume ───

  docker volume inspect open-webui-data

  # Confirms mount path. Data lives at /app/backend/data inside container.
  # Contains: webui.db (SQLite), uploads/, config files.

─── D2. Create Backup (tar.gz) ───

  mkdir -p ~/open-webui-backups

  docker run --rm \
    -v open-webui-data:/data:ro \
    -v ~/open-webui-backups:/backup \
    alpine \
    tar czf "/backup/open-webui-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C /data .

  echo "Backup saved to ~/open-webui-backups/"
  ls -lh ~/open-webui-backups/

─── D3. Restore from Backup ───

  # Stop the container first!
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted down

  # Restore (replaces ALL data in the volume):
  docker run --rm \
    -v open-webui-data:/data \
    -v ~/open-webui-backups:/backup \
    alpine \
    sh -c "rm -rf /data/* && tar xzf /backup/CHOOSE_BACKUP_FILE.tar.gz -C /data"

  # Bring back up:
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

─── D4. Warning ───

  ⚠️  Nuclear reset (Section I) WIPES ALL:
      • Chat history
      • User accounts
      • Settings & preferences
      • Uploaded files
  Always have a backup before proceeding!

BACKUP_SECTION

# =============================================================================
# SECTION E — KNOWN-GOOD DEPLOYMENT (BRING-UP)
# =============================================================================
cat << 'DEPLOY'

═══ SECTION E — KNOWN-GOOD DEPLOYMENT ═══

─── E1. Prerequisites ───

  # Ensure you're in the project directory:
  cd /Users/user/projects/open-webui-main

  # Create your .env.hosted from the template:
  cp .env.hosted.example .env.hosted

  # Generate a strong secret key:
  openssl rand -base64 32
  # → Paste the output into .env.hosted as WEBUI_SECRET_KEY value

  # Set your OpenRouter API key in .env.hosted:
  #   OPENAI_API_KEY='sk-or-v1-YOUR_ACTUAL_KEY'

─── E2. First-Time Bring-Up ───

  cd /Users/user/projects/open-webui-main

  # Pull the pinned image:
  docker pull ghcr.io/open-webui/open-webui:v0.8.5

  # Start:
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

  # Watch logs until healthy:
  docker logs -f open-webui

  # Verify health:
  docker ps --filter name=open-webui --format 'table {{.Names}}\t{{.Status}}'
  curl -sf http://localhost:3001/health && echo " OK"

  # Open in browser: http://localhost:3001
  # First user to register becomes ADMIN (registration is one-time if ENABLE_SIGNUP=false).

─── E3. Safe Update (Rolling) ───

  cd /Users/user/projects/open-webui-main

  # 1. BACKUP FIRST!
  docker run --rm -v open-webui-data:/data:ro -v ~/open-webui-backups:/backup alpine \
    tar czf "/backup/pre-update-$(date +%Y%m%d-%H%M%S).tar.gz" -C /data .

  # 2. Update image tag in docker-compose.hosted.yml (e.g., v0.8.5 → v0.8.6)
  #    sed -i '' 's/v0.8.5/v0.8.6/' docker-compose.hosted.yml

  # 3. Pull new image:
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted pull

  # 4. Recreate container (volume persists):
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

  # 5. Verify:
  docker ps --filter name=open-webui
  curl -sf http://localhost:3001/health && echo " OK"

─── E4. Rollback ───

  cd /Users/user/projects/open-webui-main

  # 1. Change image tag back to previous version:
  #    sed -i '' 's/v0.8.6/v0.8.5/' docker-compose.hosted.yml

  # 2. Recreate:
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

  # 3. If DB was migrated and incompatible, restore from backup:
  #    (See Section D3 — Restore from Backup)

DEPLOY

# =============================================================================
# SECTION F — PROVIDER SETUP + TEST COMMANDS
# =============================================================================
cat << 'PROVIDER'

═══ SECTION F — PROVIDER SETUP + TEST COMMANDS ═══

─── F1. OpenRouter (DEFAULT) ───

  Provider:   OpenRouter
  Base URL:   https://openrouter.ai/api/v1
  Free Model: openrouter/auto  (auto-routes to free models)
  Dashboard:  https://openrouter.ai/activity

  Model Naming Rules (OpenRouter):
    • Format: provider/model-name (e.g., google/gemini-2.0-flash-exp:free)
    • Free models have ":free" suffix or $0 pricing
    • Check available models: https://openrouter.ai/models

  Test connectivity (replace YOUR_KEY):

    curl -s https://openrouter.ai/api/v1/models \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Models available: {len(d.get(\"data\",[]))}')"

  Test completion:

    curl -s https://openrouter.ai/api/v1/chat/completions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{"model":"openrouter/auto","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}' \
      | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('choices',[{}])[0].get('message',{}).get('content','ERROR: No response'))"

─── F2. Groq (FALLBACK) ───

  Provider:   Groq
  Base URL:   https://api.groq.com/openai/v1
  Free Model: llama-3.3-70b-versatile (free tier, rate-limited)
  Dashboard:  https://console.groq.com

  To switch: update .env.hosted:
    OPENAI_API_BASE_URL='https://api.groq.com/openai/v1'
    OPENAI_API_KEY='gsk_YOUR_GROQ_KEY'

  Then: docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

  Test connectivity:

    curl -s https://api.groq.com/openai/v1/models \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Models: {len(d.get(\"data\",[]))}')"

─── F3. Common Errors ───

  ERROR: "404 Not Found" on /chat/completions
  CAUSE: Missing /v1 in OPENAI_API_BASE_URL
  FIX:   Ensure URL ends with /v1 (e.g., https://openrouter.ai/api/v1)

  ERROR: "401 Unauthorized"
  CAUSE: Invalid or expired API key
  FIX:   Regenerate key at provider dashboard

  ERROR: "429 Too Many Requests"
  CAUSE: Rate limit hit (free tier)
  FIX:   Wait 60s, or upgrade plan, or switch to fallback provider

  ERROR: "model_not_found"
  CAUSE: Incorrect model name
  FIX:   Use exact name from provider's model list (case-sensitive)

─── F4. PII Guidance ───

  • Never paste PII (names, emails, SSNs, passwords) into prompts
  • OpenRouter and Groq log prompts for abuse detection
  • For sensitive work, use a provider with BAA/DPA (not free tiers)

PROVIDER

# =============================================================================
# SECTION G — FAST FIX (LAYER 1)
# =============================================================================
cat << 'FASTFIX'

═══ SECTION G — FAST FIX (LAYER 1) ═══

Use when: container exists but misbehaving, minor config issues.
Risk: NONE (no data loss)
Time: < 2 minutes

─── G1. Restart Container ───

  docker restart open-webui
  sleep 10
  docker ps --filter name=open-webui --format '{{.Status}}'
  curl -sf http://localhost:3001/health && echo " OK" || echo "STILL UNHEALTHY"

─── G2. Fix Environment Variables ───

  # Edit .env.hosted, then:
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d
  # (This recreates the container with new env, volume persists)

─── G3. Fix Port Conflict ───

  # Check what's using the port:
  lsof -nP -iTCP:3001 -sTCP:LISTEN

  # Option A: Change port in .env.hosted:
  #   OPEN_WEBUI_PORT=3002
  # Then: docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

  # Option B: Kill the conflicting process (use exact PID):
  #   kill <PID>
  # Then: docker restart open-webui

─── G4. Clear Bad Admin Config (via UI) ───

  # If UI loads but models don't work:
  # 1. Log in as admin
  # 2. Go to Admin Panel → Settings → Connections
  # 3. Verify OpenAI API URL = https://openrouter.ai/api/v1
  # 4. Verify API Key is set
  # 5. Click "Verify connection" / Save

FASTFIX

# =============================================================================
# SECTION H — DEEP REPAIR (LAYER 2)
# =============================================================================
cat << 'DEEPREPAIR'

═══ SECTION H — DEEP REPAIR (LAYER 2) ═══

Use when: container won't start, image corrupt, crash loop.
Risk: LOW (volume preserved, container recreated)
Time: 5–10 minutes

─── H1. Stop & Remove Container (keep volume!) ───

  cd /Users/user/projects/open-webui-main

  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted down
  # ⚠️ Do NOT use "down -v" — that deletes the volume!

─── H2. Pull Fresh Image ───

  docker pull ghcr.io/open-webui/open-webui:v0.8.5

─── H3. Recreate ───

  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

─── H4. Verify ───

  sleep 15
  docker ps --filter name=open-webui --format '{{.Names}} {{.Status}}'
  curl -sf http://localhost:3001/health && echo " OK" || echo "UNHEALTHY"

─── H5. Check DB Integrity (if suspecting corruption) ───

  docker exec open-webui \
    python3 -c "
import sqlite3, sys
db = sqlite3.connect('/app/backend/data/webui.db')
result = db.execute('PRAGMA integrity_check').fetchone()
print(f'DB integrity: {result[0]}')
sys.exit(0 if result[0] == 'ok' else 1)
"

  # If corrupted: restore from backup (Section D3)

DEEPREPAIR

# =============================================================================
# SECTION I — NUCLEAR RESET (LAYER 3)
# =============================================================================
cat << 'NUCLEAR'

═══ SECTION I — NUCLEAR RESET (LAYER 3) ═══

Use when: everything else failed, DB corrupted beyond repair.
Risk: HIGH — ALL DATA WIPED (chats, users, settings)
Time: 5–10 minutes

⚠️⚠️⚠️  THIS DESTROYS ALL DATA. BACKUP FIRST!  ⚠️⚠️⚠️

─── I1. BACKUP (MANDATORY) ───

  mkdir -p ~/open-webui-backups

  docker run --rm \
    -v open-webui-data:/data:ro \
    -v ~/open-webui-backups:/backup \
    alpine \
    tar czf "/backup/pre-nuclear-$(date +%Y%m%d-%H%M%S).tar.gz" -C /data .

  echo "Backup saved. Proceed only after confirming file exists:"
  ls -lh ~/open-webui-backups/pre-nuclear-*.tar.gz

─── I2. DESTROY ───

  cd /Users/user/projects/open-webui-main

  # Stop and remove container AND volume:
  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted down -v

  # Verify volume is gone:
  docker volume ls --filter name=open-webui-data
  # Should show nothing

─── I3. RECREATE CLEAN ───

  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

  # Wait for startup:
  sleep 20
  docker ps --filter name=open-webui --format '{{.Names}} {{.Status}}'
  curl -sf http://localhost:3001/health && echo " OK"

  # Open browser: http://localhost:3001
  # Register new admin account (first user = admin)

─── I4. RESTORE FROM BACKUP (optional) ───

  # If you want to restore data instead of starting fresh:

  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted down

  docker run --rm \
    -v open-webui-data:/data \
    -v ~/open-webui-backups:/backup \
    alpine \
    sh -c "rm -rf /data/* && tar xzf /backup/CHOOSE_YOUR_BACKUP.tar.gz -C /data"

  docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d

NUCLEAR

# =============================================================================
# SECTION J — VALIDATION CHECKLIST
# =============================================================================
cat << 'VALIDATION'

═══ SECTION J — VALIDATION CHECKLIST ═══

Run ALL of these after any deployment or repair. ALL must pass.

  ┌─────┬───────────────────────────────┬────────────────────────────────────────────┐
  │  #  │ Check                         │ Command                                    │
  ├─────┼───────────────────────────────┼────────────────────────────────────────────┤
  │  1  │ Container running             │ docker ps --filter name=open-webui         │
  │  2  │ Health status: healthy        │ docker inspect open-webui --format=        │
  │     │                               │   '{{.State.Health.Status}}'               │
  │  3  │ UI reachable (HTTP 200)       │ curl -sI http://localhost:3001 | head -1   │
  │  4  │ Health endpoint OK            │ curl -sf http://localhost:3001/health       │
  │  5  │ Login page loads              │ curl -s http://localhost:3001 | grep -c     │
  │     │                               │   "Open WebUI"                             │
  │  6  │ Provider reachable            │ (see curl test in Section F)               │
  │  7  │ No crash loops                │ docker inspect open-webui --format=        │
  │     │                               │   '{{.RestartCount}}'                      │
  │  8  │ Volume persists               │ docker volume inspect open-webui-data      │
  │  9  │ Restart persistence           │ docker restart open-webui && sleep 15 &&   │
  │     │                               │   curl -sf http://localhost:3001/health    │
  │ 10  │ No secrets in logs            │ docker logs open-webui 2>&1 | grep -i      │
  │     │                               │   "sk-or-v1" && echo "LEAK!" || echo "OK" │
  └─────┴───────────────────────────────┴────────────────────────────────────────────┘

Quick validation one-liner:

  docker inspect open-webui --format='{{.State.Health.Status}}' && \
  curl -sf http://localhost:3001/health > /dev/null && \
  echo "✅ ALL CHECKS PASSED" || echo "❌ VALIDATION FAILED"

VALIDATION

# =============================================================================
# SECTION K — SECURITY HARDENING
# =============================================================================
cat << 'SECURITY'

═══ SECTION K — SECURITY HARDENING ═══

─── K1. Strong Secret Key ───

  # Generate:
  openssl rand -base64 32

  # Set in .env.hosted. NEVER change after first deployment (invalidates sessions).
  # NEVER commit .env.hosted to git.

─── K2. Disable Open Registration ───

  # In .env.hosted:
  ENABLE_SIGNUP=false

  # Admin creates accounts via: Admin Panel → Users → Add User

─── K3. Network Exposure ───

  RECOMMENDED: Bind to localhost + reverse proxy (Nginx/Caddy)

  # In .env.hosted, change port binding:
  OPEN_WEBUI_PORT=127.0.0.1:3001

  # This makes it ONLY accessible via localhost (reverse proxy required).

  # For LAN-only access (no proxy):
  OPEN_WEBUI_PORT=0.0.0.0:3001

─── K4. Git Ignore Secrets ───

  # Add to .gitignore:
  echo ".env.hosted" >> .gitignore

─── K5. Log Redaction ───

  # Check for leaked keys in logs:
  docker logs open-webui 2>&1 | grep -iE "sk-or-|gsk_|bearer" && echo "⚠️ KEY IN LOGS" || echo "✅ Clean"

  # Open WebUI should NOT log API keys. If found, report as security bug.

─── K6. Least Privilege ───

  • Run container as non-root (Open WebUI image already does this)
  • Use read-only mount where possible
  • Restrict Docker socket access
  • Do not expose Docker API to network

─── K7. TLS (if exposed externally) ───

  • Use a reverse proxy (Nginx/Caddy) with Let's Encrypt
  • Never expose port 3001 directly to the internet without TLS
  • See Section N for Nginx example

SECURITY

# =============================================================================
# SECTION L — COST & ABUSE CONTROL
# =============================================================================
cat << 'COST'

═══ SECTION L — COST & ABUSE CONTROL ═══

─── L1. Provider Free Tier Limits ───

  OpenRouter:
  • Free models: ~10-20 RPM, ~200 RPD for free-tier keys
  • Paid models: billed per token (check pricing per model)
  • Monitor: https://openrouter.ai/activity

  Groq:
  • Free tier: ~30 RPM, 14,400 RPD (varies by model)
  • No charges on free tier, but hard rate limits
  • Monitor: https://console.groq.com/usage

─── L2. Team Usage Policy ───

  RECOMMENDED DAILY LIMITS:
  • Max 50 messages per user per day (enforce socially or via admin)
  • Avoid uploading large files (>1MB context fills up fast)
  • No automated/scripted requests through the UI
  • Rotate API keys monthly

─── L3. Open WebUI Admin Controls ───

  As Admin, configure:
  1. Admin Panel → Users: Control who can access
  2. Admin Panel → Settings → Models: Restrict which models are visible
  3. Admin Panel → Settings → General: Set default model to a free one
  4. Admin Panel → Settings → Interface: Disable features you don't need

─── L4. Rate Limit Detection ───

  Signs of rate limiting:
  • "429 Too Many Requests" in docker logs
  • Slow or empty responses
  • "Rate limit exceeded" messages in chat

  Response:
  1. Wait 60 seconds
  2. Switch to fallback provider (Groq)
  3. Reduce team usage
  4. Upgrade provider plan

─── L5. Key Rotation ───

  1. Generate new key at provider dashboard
  2. Update .env.hosted with new key
  3. Recreate container:
     docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d
  4. Revoke old key at provider dashboard
  5. Verify: send a test message in UI

COST

# =============================================================================
# SECTION M — PREVENTION & MAINTENANCE
# =============================================================================
cat << 'PREVENTION'

═══ SECTION M — PREVENTION & MAINTENANCE ═══

─── M1. Pin Image Versions ───

  ALWAYS use a specific tag (e.g., v0.8.5), never "latest" or "main".
  This prevents surprise breaking changes.

  Current pinned version: v0.8.5
  Change only in docker-compose.hosted.yml after testing.

─── M2. Update Cadence ───

  RECOMMENDED: Check for updates monthly.

  # Check latest release:
  curl -s https://api.github.com/repos/open-webui/open-webui/releases/latest \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'{r[\"tag_name\"]} ({r[\"published_at\"][:10]})')"

  # Read changelog before updating:
  # https://github.com/open-webui/open-webui/releases

─── M3. Automated Backup (cron) ───

  # Add to crontab (daily at 2 AM):
  # crontab -e
  0 2 * * * docker run --rm -v open-webui-data:/data:ro -v ~/open-webui-backups:/backup alpine tar czf "/backup/auto-$(date +\%Y\%m\%d).tar.gz" -C /data .

  # Keep last 30 days of backups:
  0 3 * * * find ~/open-webui-backups -name "auto-*.tar.gz" -mtime +30 -delete

─── M4. Monitoring ───

  # Quick health check (can be scripted/cron'd):
  curl -sf http://localhost:3001/health > /dev/null || echo "ALERT: Open WebUI is DOWN"

  # Container restart count (should be 0 in steady state):
  docker inspect open-webui --format='RestartCount: {{.RestartCount}}'

  # Resource usage:
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'

PREVENTION

# =============================================================================
# SECTION N — NGINX REVERSE PROXY (OPTIONAL)
# =============================================================================
cat << 'NGINX'

═══ SECTION N — NGINX REVERSE PROXY (OPTIONAL) ═══

Use this if exposing Open WebUI to external users or needing TLS.

─── N1. Minimal Nginx Config ───

  # /etc/nginx/sites-available/open-webui.conf

  server {
      listen 80;
      server_name chat.yourdomain.com;

      # Redirect to HTTPS (uncomment after TLS setup)
      # return 301 https://$host$request_uri;

      location / {
          proxy_pass http://127.0.0.1:3001;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # Timeouts for long completions
          proxy_read_timeout 300s;
          proxy_send_timeout 300s;

          # Max upload size
          client_max_body_size 50M;
      }
  }

  # HTTPS block (after certbot):
  # server {
  #     listen 443 ssl http2;
  #     server_name chat.yourdomain.com;
  #     ssl_certificate /etc/letsencrypt/live/chat.yourdomain.com/fullchain.pem;
  #     ssl_certificate_key /etc/letsencrypt/live/chat.yourdomain.com/privkey.pem;
  #     # ... same location block as above ...
  # }

─── N2. Enable & Test ───

  sudo ln -s /etc/nginx/sites-available/open-webui.conf /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx

─── N3. TLS with Let's Encrypt ───

  sudo apt install certbot python3-certbot-nginx  # or brew install certbot
  sudo certbot --nginx -d chat.yourdomain.com

NGINX

echo ""
echo "═══ RUNBOOK COMPLETE ═══"
echo ""
echo "Quick Start:"
echo "  1. cd /Users/user/projects/open-webui-main"
echo "  2. cp .env.hosted.example .env.hosted"
echo "  3. Edit .env.hosted → set OPENAI_API_KEY and WEBUI_SECRET_KEY"
echo "  4. docker-compose -f docker-compose.hosted.yml --env-file .env.hosted up -d"
echo "  5. Open http://localhost:3001"
echo "  6. Register admin account (first user = admin)"
echo ""
