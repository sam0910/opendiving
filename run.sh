#!/usr/bin/env bash
# Start and stop the local OpenDiving dev site (no Docker). See RUN.md.
#
#   ./run.sh start            Postgres, Redis, API, worker, web
#   ./run.sh stop             API, worker, web (Postgres and Redis keep running)
#   ./run.sh stop --all       ...and Postgres and Redis too
#   ./run.sh restart          stop + start
#   ./run.sh status
#   ./run.sh logs [api|worker|web]
#   ./run.sh signin           print the latest magic link and code
set -euo pipefail

# The app repos sit next to this one.
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$BASE/opendiving-api"
WEB="$BASE/opendiving-web"
# The web log lives here, outside opendiving-web: `next dev` watches its own folder,
# and a log written inside it recompiles and reloads the page on every line, forever.
WEB_LOG="$BASE/opendiving/.logs/web.log"

API_PATTERN="uvicorn app.main:app"
WORKER_PATTERN="arq app.core.worker"
WEB_PATTERN="next dev"

running() { pgrep -f "$1" >/dev/null 2>&1; }

# launch DIR LOG CMD...: run CMD in DIR in the background, detached from this shell.
# exec and </dev/null matter: without them the background job keeps this script's
# stdout open, and `./run.sh start | anything` never returns.
launch() {
  local dir=$1 log=$2
  shift 2
  (cd "$dir" && exec nohup "$@" >"$log" 2>&1 </dev/null) &
  disown
}

start() {
  brew services start postgresql@18 >/dev/null
  brew services start redis >/dev/null

  mkdir -p "$API/.logs" "$(dirname "$WEB_LOG")"

  # Run from src/ so the API and worker read src/.env.
  if running "$API_PATTERN"; then
    echo "api     already running"
  else
    launch "$API/src" "$API/.logs/api.log" ../.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
    echo "api     started"
  fi

  if running "$WORKER_PATTERN"; then
    echo "worker  already running"
  else
    launch "$API/src" "$API/.logs/worker.log" ../.venv/bin/arq app.core.worker.settings.WorkerSettings
    echo "worker  started"
  fi

  if running "$WEB_PATTERN"; then
    echo "web     already running"
  else
    # nvm is a shell function, so a script has to load it itself.
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    nvm use 24 >/dev/null
    launch "$WEB" "$WEB_LOG" pnpm dev
    echo "web     started"
  fi

  wait_ready
}

wait_ready() {
  printf "waiting for the API"
  for _ in $(seq 1 30); do
    if curl -sf localhost:8000/api/v1/health/ready >/dev/null 2>&1; then
      echo " ok"
      echo "web: http://localhost:3000   api: http://localhost:8000/docs"
      return 0
    fi
    printf "."
    sleep 1
  done
  echo " not ready after 30s, see: ./run.sh logs api"
  return 1
}

stop() {
  for name in api worker web; do
    case $name in
      api) pattern=$API_PATTERN ;;
      worker) pattern=$WORKER_PATTERN ;;
      web) pattern=$WEB_PATTERN ;;
    esac
    if pkill -f "$pattern" 2>/dev/null; then
      # Give it 10s to shut down cleanly, then force it.
      for _ in $(seq 1 10); do running "$pattern" || break; sleep 1; done
      running "$pattern" && pkill -9 -f "$pattern" 2>/dev/null
      printf "%-7s stopped\n" "$name"
    else
      printf "%-7s not running\n" "$name"
    fi
  done

  if [[ "${1:-}" == "--all" ]]; then
    brew services stop postgresql@18 >/dev/null
    brew services stop redis >/dev/null
    echo "postgres, redis stopped"
  fi
}

status() {
  for name in api worker web; do
    case $name in
      api) pattern=$API_PATTERN ;;
      worker) pattern=$WORKER_PATTERN ;;
      web) pattern=$WEB_PATTERN ;;
    esac
    if running "$pattern"; then printf "%-9s running\n" "$name"; else printf "%-9s stopped\n" "$name"; fi
  done
  if /opt/homebrew/opt/postgresql@18/bin/pg_isready -q 2>/dev/null; then
    echo "postgres  running"
  else
    echo "postgres  stopped"
  fi
  if redis-cli ping >/dev/null 2>&1; then echo "redis     running"; else echo "redis     stopped"; fi
  curl -s localhost:8000/api/v1/health/ready 2>/dev/null && echo
}

logs() {
  case "${1:-api}" in
    api) tail -f "$API/.logs/api.log" ;;
    worker) tail -f "$API/.logs/worker.log" ;;
    web) tail -f "$WEB_LOG" ;;
    *) echo "logs: api | worker | web" >&2; exit 1 ;;
  esac
}

signin() {
  grep "magic link" "$API/.logs/api.log" | tail -1 || echo "no sign-in link in $API/.logs/api.log yet"
}

case "${1:-}" in
  start) start ;;
  stop) stop "${2:-}" ;;
  restart) stop; sleep 2; start ;;
  status) status ;;
  logs) logs "${2:-}" ;;
  signin) signin ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
