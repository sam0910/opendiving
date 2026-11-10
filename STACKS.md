# OpenDiving stack

What each piece is built with, and what Redis and the worker are for. How to run it all locally is in
[RUN.md](RUN.md).

```
browser ──► web (Next.js, :3000) ──► api (FastAPI, :8000) ──► PostgreSQL 18
                                        │                        ▲
                                        └──► Redis 8 ◄── worker (arq, cron only)
```

## The pieces

| Piece | Repo | Built with |
| --- | --- | --- |
| **web** | `opendiving-web` | Next.js 16 (App Router, Turbopack), React 19, Tailwind 4, shadcn/ui, Zod, MapLibre GL. Tests: Vitest + Playwright |
| **api** | `opendiving-api` | Python 3.15, FastAPI, Pydantic 2, SQLAlchemy (async) + asyncpg, Alembic, FastCRUD, `webauthn`, `divejson`. Served by uvicorn (dev) / gunicorn (prod) |
| **worker** | `opendiving-api` | arq, running the same code as the api |
| **database** | — | PostgreSQL 18 with the `pg_trgm` and `unaccent` extensions, for fuzzy dive-site search |
| **cache** | — | Redis 8 |
| **Commons** | `opendiving-commons` | GeoJSON records + Python build scripts; built into `opendiving-api/src/app/data/commons_dive_sites.geojson` |
| **map-renderer** *(prod, optional)* | `opendiving-web` image | MapLibre GL Native, draws the map tiles behind cards and page headers; off until `MAP_RENDERER_URL` is set |
| **caddy** *(prod only)* | `opendiving` | Reverse proxy and automatic Let's Encrypt TLS |

In production every container is a prebuilt image from `docker-compose.yml` in this repo. Locally, see RUN.md:
Postgres and Redis come from Homebrew, and the api, worker and web run straight from the checkouts.

## Commons: how the bundle reaches the database

On every start the API syncs `src/app/data/commons_dive_sites.geojson` (the "bundle") into the `dive_site` table
(`sync_commons` in `src/app/services/commons_records.py`). What the sync does depends on `COMMONS_PRIMARY`:

| | New site in the bundle | Changed site already in the DB | Site removed from the bundle |
| --- | --- | --- | --- |
| `COMMONS_PRIMARY=true` *(our local setting)* | inserted | **not updated**, the DB keeps its values | stays |
| unset / `false` | inserted | updated, **unless** it was accepted through a proposal review (`commons_reviewed_at` is set) | stays |

**Watch out: with `COMMONS_PRIMARY=true`, editing an existing site in `opendiving-commons` and rebuilding the
bundle does not change it locally.** In that mode the database is the source of truth and the bundle only seeds
it, so only brand-new sites come through. This is confirmed from the code, not from a test run.

While you're editing Commons data:

1. **Remove the `COMMONS_PRIMARY=true` line** from `opendiving-api/src/.env`.
2. Rebuild the bundle and run `./run.sh restart`.
3. **Check in the app that the site actually changed.** A site accepted through a review on this instance still
   won't be overwritten.
4. Add the line back when you want proposals, reviews and the export route again.

A site deleted from the bundle is never deleted from the database in either mode. Remove it by hand if you need to.

## Redis: short-lived state, never the source of truth

Everything in Redis expires on its own, and losing all of it loses no data: Postgres holds everything that
matters. The API uses Redis for:

- **Rate limiting.** Per-user and per-IP counters (`INCR` + `EXPIRE`) on sign-in, invitations, Commons proposals,
  site search, exports and so on. If Redis is down, limits **fail open**: requests go through and a warning is
  logged.
- **Passkey challenges.** The one-time WebAuthn challenge for each passkey sign-in, kept for exactly one ceremony.
  **This is the one place Redis is required**: with Redis down, passkey sign-in answers 503. Email links and codes
  keep working.
- **Refresh-token grace.** When a token refresh's reply gets lost, a retry within a short grace window gets the
  same token pair back, so the session isn't ended as a replay.
- **Response cache.** Cached API responses, capped at 1 MB per body.
- **Commons pins document.** The `GET /commons/dive-sites/points` body, which every account shares and which
  outgrows the response cache's 1 MB cap. It is rebuilt whenever the Commons rows change.
- **Outbound answer cache.** Answers from third-party providers (geocoding with Photon/Nominatim, species with
  WoRMS/Wikidata), so the same question isn't asked twice.
- **Locks.** One map tile drawn at a time per tile, one dive-conditions run at a time, and one-use export
  download tokens.
- **The worker's queue.** arq keeps its cron bookkeeping and a health-check key in Redis. `arq --check` reads that
  key, and the key is refreshed every 15 s.
- **Admin panel sessions** *(optional)*. Only when `CRUD_ADMIN_REDIS_ENABLED=true`.

Settings: `REDIS_CACHE_HOST/PORT` (cache, limits, locks) and `REDIS_QUEUE_HOST/PORT` (arq). Both point at the same
Redis here, and `REDIS_PASSWORD` is optional.

## The worker: scheduled jobs only

The worker is **cron only**. The API never enqueues a job (`functions = []` in
`src/app/core/worker/settings.py`), and nothing a user clicks waits on the worker. If the worker stops, the site
keeps working, but housekeeping and emails pause until it's back.

| When | Job | What it does |
| --- | --- | --- |
| hourly at :00, and at startup | `purge_expired_tokens`, `purge_expired_authentication_requests`, `purge_expired_user_sessions`, `purge_expired_auth_audit_events`, `purge_expired_idempotency_holds`, `purge_expired_checkin_links`, `purge_expired_invitations`, `purge_expired_invite_requests`, `purge_unserved_map_tiles`, `purge_expired_logbook_imports` | Delete rows past their expiry: spent sign-in tokens, dead sessions, old audit rows, expired check-in share links, unused invitations, map tiles unserved for 30 days, and finished or abandoned imports |
| hourly at :00, and at startup | `record_sign_in_totals` | Write sign-in counts |
| hourly at :15, and at startup | `read_dive_file_fixes` | Read GPS fixes out of stored dive-computer files, for example after an upgrade or an archive restore |
| hourly at :30 | `purge_deleted_accounts` | Permanently erase accounts whose deletion grace period is over. Never at startup, so a restart loop can't erase an account early |
| daily, at `GEAR_SERVICE_DIGEST_HOUR` | `send_gear_service_digests`, `send_renewal_reminders`, `send_year_in_review` | Emails: gear service due, a c-card or insurance policy about to expire, and the January year-in-review. Never at startup, so a restart can't resend them |
| every minute | `fetch_dive_conditions` | Fetch the surface conditions for dives that need them. Does nothing unless `DIVE_CONDITIONS_PROVIDER` is set, and a Redis lock stops runs from overlapping |

Every job is safe to run twice: the deletes only remove rows already past an absolute cutoff, and the emails check
whether they were already sent. Locally, with no `SMTP_HOST`, every email sender returns early, so the email jobs send nothing.

## Hosting: can it run on Vercel?

**Only the web app fits Vercel well.** The API can probably be made to run there, but the worker can't run on Vercel
as it is, and Vercel doesn't host Redis 8 itself.

| Piece | On Vercel? | What it takes |
| --- | --- | --- |
| **web** (Next.js) | **Yes** | Vercel is built for Next.js. Set `NEXT_PUBLIC_API_URL` to wherever the API runs. |
| **api** (FastAPI) | **Possible, with work** | See below. |
| **worker** (arq) | **No, not without code changes** | It's an always-running process with its own timers, including one every minute. Vercel has nothing that stays running. To use Vercel Cron, each job would need rewriting as an HTTP endpoint for Cron to call. Until then cleanup, account erasure and emails never run. |
| **Redis 8** | **Not from Vercel directly** | The Marketplace has **Upstash Redis**, which is Redis-compatible. Rate limits, passkey challenges and caches would likely work. arq is a poor fit, since it keeps polling and Upstash bills per command. Untested. |
| **Postgres 18** | **Yes, through Neon** (Marketplace) | Neon offers the `pg_trgm` and `unaccent` extensions this app needs. |

What the API would need on Vercel, where each request runs as a short-lived function:

- **Somewhere to keep uploaded files.** The function's disk is wiped between requests, so switch to
  `FILE_STORAGE_BACKEND=S3` with a bucket. The API already supports that (`S3_BUCKET`, `S3_ENDPOINT_URL`).
- **Python 3.15.** Check that Vercel's Python runtime offers it; not confirmed.
- **No startup work on cold starts.** Migrations and the Commons sync (about 4,300 sites) run whenever a new
  instance starts. Set `MIGRATE_ON_START=false` and run `alembic upgrade head` from CI.
- **No `divejson-raw`.** That binary ships only in the Docker image, so raw dive-computer data stays unread, the same
  as the local setup.

### Recommended

- **Simplest: the whole stack on one VPS** with this repo's `docker-compose.yml` and `install.sh`. That's what it's
  designed for: Caddy for HTTPS, prebuilt amd64/arm64 images, and an upgrade is `docker compose pull && up -d`.
- **If you want Vercel: put only the web app there.** Run the API, worker and Redis together on one container host
  (Fly.io, Railway, Render or a small VPS), from the same Docker images the project ships. Postgres can be Neon or
  run on that same host.
