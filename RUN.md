# Running OpenDiving locally (dev)

The dev site runs straight on this Mac, without Docker. It is made of four checkouts: this repo, with the three
app repos cloned inside it. Each app repo is its own git repository, not a submodule, and this repo's `.gitignore`
keeps them out of it:

```
~/Code/00-CSMB/Software/opendiving/   # this repo: install bundle + docs (nothing to run)
├── opendiving-api       # FastAPI + arq worker   → http://localhost:8000  (docs at /docs)
├── opendiving-web       # Next.js                → http://localhost:3000
└── opendiving-commons   # dive-site pool, built into the API's bundle
```

| Process  | Runs from                    | Log                    |
| -------- | ---------------------------- | ---------------------- |
| Postgres | `brew services` (postgresql@18) | brew                |
| Redis    | `brew services` (redis)      | brew                   |
| API      | `opendiving-api/.venv`       | `opendiving-api/.logs/api.log`    |
| Worker   | `opendiving-api/.venv`       | `opendiving-api/.logs/worker.log` |
| Web      | Node 24 (nvm) + pnpm         | `.logs/web.log`                   |

## Quick: `run.sh`

```bash
./run.sh start            # Postgres, Redis, API, worker, web; waits for the API to be ready
./run.sh stop             # API, worker, web (Postgres and Redis keep running)
./run.sh stop --all       # ...and Postgres and Redis too
./run.sh restart
./run.sh status
./run.sh logs api         # or worker, web (tail -f)
./run.sh signin           # latest magic link and code
```

The sections below are what it does, step by step.

## Start

```bash
OD=~/Code/00-CSMB/Software/opendiving

# 1. Postgres + Redis (they also come back at login once started)
brew services start postgresql@18
brew services start redis

# 2. API + worker (run from src/ so they read src/.env)
cd $OD/opendiving-api/src && mkdir -p ../.logs
nohup ../.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload > ../.logs/api.log 2>&1 &
nohup ../.venv/bin/arq app.core.worker.settings.WorkerSettings > ../.logs/worker.log 2>&1 &

# 3. Web
cd $OD/opendiving-web && mkdir -p $OD/.logs
nvm use 24
# The log goes outside opendiving-web: `next dev` watches its own folder, and a log
# written inside it makes the page recompile and reload on every line.
nohup pnpm dev > $OD/.logs/web.log 2>&1 &
```

Check it's up:

```bash
curl -s localhost:8000/api/v1/health/ready   # {"status":"ready","database":"ok","redis":"ok"}
open http://localhost:3000
```

To watch the output instead, run any of the three commands in the foreground in its own terminal, without
`nohup … &`.

## Stop

```bash
pkill -f "uvicorn app.main:app"            # API
pkill -f "arq app.core.worker"             # worker
pkill -f "next dev"                        # web

# Optional: Postgres + Redis too (otherwise they keep running in the background)
brew services stop postgresql@18
brew services stop redis
```

## Signing in

No mail server is set up, so the API **writes the magic link and the six-digit code to its log** instead of
sending an email:

```bash
grep "magic link" ~/Code/00-CSMB/Software/opendiving/opendiving-api/.logs/api.log | tail -1
```

Open the link, or type the code on the sign-in page. Both expire in 30 minutes. The first account to sign in is
the superuser, which is who reviews Commons proposals.

## Commons

`opendiving-api/src/.env` sets `COMMONS_PRIMARY=true`, so this instance behaves like the one where the Commons is
edited: proposals, the review queue, and `GET /api/v1/commons/dive-sites` all work. With it on, the database is
the source of truth and the bundle only seeds it.

**With `COMMONS_PRIMARY=true`, a rebuild only adds new sites. Edits to existing sites don't come through.** Remove
that line from `.env` while you edit Commons data, and see [STACKS.md](STACKS.md#commons-how-the-bundle-reaches-the-database).

After changing sites in `opendiving-commons`, rebuild the API's bundle, then restart the API:

```bash
cd ~/Code/00-CSMB/Software/opendiving/opendiving-api
ENVIRONMENT=local SECRET_KEY=x .venv/bin/python scripts/build_commons_bundle.py ../opendiving-commons
```

That rewrites `src/app/data/commons_dive_sites.geojson`, which git tracks. Don't commit it unless you mean to.

## Local setup at a glance

- **Postgres 18** (Homebrew): role `postgres` / password `postgres`, database `opendive`. Tests use their own
  `opendive_test*` databases.
- **API `.venv`**: Python **3.15.2** via `uv`. Not 3.15.0a8, whose SQLAlchemy build crashes. Rebuild with
  `rm -rf .venv && uv sync --extra dev --python 3.15.2`.
- **`opendiving-api/src/.env`**: points at `localhost` for Postgres and Redis, stores uploads in
  `opendiving-api/.data/files`, and leaves `SMTP_HOST` unset.
- **Web**: Node 24 through nvm. Dependencies are installed with pnpm from a `pnpm-lock.yaml` made by `pnpm import`,
  which is git-ignored locally.
- **Migrations**: run `cd opendiving-api/src && ../.venv/bin/alembic upgrade head` after pulling.
- **Not available without Docker**: `divejson-raw`, so the raw dive-computer bytes the iOS app downloads are
  not read. Exported files (FIT, UDDF and so on) import normally.

## Gotchas

- `next dev` rewrites the managed block at the bottom of `opendiving-web/AGENTS.md` when a Next.js upgrade
  changes it. If `AGENTS.md` shows modified after starting the web app, commit that rewrite with your work
  instead of reverting it; reverting only brings the change back on the next start.
- Remotes: `origin` is your fork (`sam0910/*`) and `upstream` is `opendiving/*`. To bring in new work, run
  `git fetch upstream && git merge upstream/main`.
