# Configuration reference

Everything is configured through one `.env` file next to `docker-compose.yml`. The compose file
feeds it to the API and the worker wholesale, and hands the web container only the handful of
variables it needs — so database and SMTP credentials never enter the Node process at all.

An edit to `.env` takes effect on `docker compose up -d`, which recreates what changed. A plain
`docker compose restart` does **not** re-read the file: it restarts the process inside a container
that keeps the environment it was created with.

The API has more settings than are listed here — token lifetimes, every rate limit, the geocoder and
species providers. [`src/.env.example`](https://github.com/opendiving/opendiving-api/blob/main/src/.env.example) in `opendiving-api` is the
full annotated list and [`src/app/core/config.py`](https://github.com/opendiving/opendiving-api/blob/main/src/app/core/config.py)
is the authority; the groups below say which of them a
self-hoster normally touches, and any setting from that file can be added to `.env` verbatim.

## The six that matter

| Variable                         | Default             | What it does                                                                                                    |
| -------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------- |
| `DOMAIN`                         | *(none — required)* | The hostname this instance answers on. Drives the certificate, the emailed links and the web app's own origin.  |
| `SECRET_KEY`                     | *(none — required)* | Signs every token the API issues. `openssl rand -hex 32`. Startup **fails** on the published placeholder value. |
| `POSTGRES_PASSWORD`              | *(none — required)* | The database password, read once when the volume is first created.                                              |
| `SMTP_HOST`, `SMTP_PORT`         | *(none)*            | The mail relay. Required on any `ENVIRONMENT` but `local`, because sign-in is passwordless.                     |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | *(none)*            | Its credentials. Both optional and independent — a relay that authenticates by IP needs neither.                |
| `EMAIL_FROM_ADDRESS`             | *(none)*            | The address mail is sent as. Required as soon as `SMTP_HOST` is set; startup fails without it.                  |

## Serving

| Variable             | Default             | What it does                                                                                                                                                                                |
| -------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `COMPOSE_PROFILES`   | `proxy`             | Runs the bundled Caddy. Comment it out to bring your own proxy — [reverse-proxy.md](reverse-proxy.md). Add `map-renderer` to the list to draw the maps on cards and page heads and give the iOS app its maps — [The map renderer](#the-map-renderer). |
| `CADDY_SITE_ADDRESS` | `${DOMAIN}`         | The address Caddy answers on. `:80` for a LAN instance with no certificate.                                                                                                                 |
| `TRUSTED_PROXY_IPS`  | `172.29.0.0/16`     | Whose `X-Forwarded-For` and `X-Forwarded-Proto` the API believes. Every per-IP rate limit depends on it, as do the admin panel's HTTPS enforcement and its IP allowlist.                    |
| `ENVIRONMENT`        | `production`        | `production` hides `/docs`. `staging` puts it behind a superuser; both require `SMTP_HOST`. `local` opens the docs and logs sign-in links instead of emailing them. The schema at `/api/v1/openapi.json` is served whatever the value. |
| `FRONTEND_URL`       | `https://${DOMAIN}` | Where emailed links point, the API's single allowed CORS origin, and the passkey domain — see [Sign-in](#sign-in) before changing its hostname. Override for a plain-HTTP instance.         |
| `SITE_URL`           | `https://${DOMAIN}` | The origin relative URLs in page metadata resolve against, and the one the [map renderer](#the-map-renderer) sends to the basemap. On the basemap the image ships, the iOS app fetches the map's sprite from it, so a phone has to be able to reach it. Override alongside `FRONTEND_URL`.                       |
| `AUTH_COOKIE_SECURE` | `true`              | The refresh cookie's `Secure` flag. `false` only for plain HTTP, where the browser otherwise drops it and every reload signs the user out.                                                  |
| `WEB_HSTS`           | `on`                | `Strict-Transport-Security`, sent only on requests that already arrived over HTTPS. `off` hands the header to a proxy in front, or supports an instance that must stay reachable over HTTP. |
| `WEB_NOINDEX`        | `off`               | `true` disallows all crawlers and adds `X-Robots-Tag: noindex, nofollow` to every page.                                                                                                     |
| `OPENDIVING_VERSION` | `latest`            | The image tag both containers run. Pin it once this instance holds dives you'd miss.                                                                                                        |
| `LOG_LEVEL`          | `INFO`              | Applied to the API and the worker alike.                                                                                                                                                    |

## Who may create an account

New installs are **invite-only**. That is the default and it is a deliberate one: an instance
reachable from the internet with nothing configured would otherwise take anybody who found it, and
this one holds people's dive logs. Set `REGISTRATION_MODE=open` if you want the other behaviour,
which is what this app did before the setting existed.

| Variable                                   | Default  | What it does                                                                                                                                                                                                                                                                                                       |
| ------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `REGISTRATION_MODE`                        | `invite` | `invite` admits only an address somebody already invited, or somebody who follows a member's invite link: the home page offers a stranger a **Request an invite** form instead of a sign-in form, and their address joins a queue you work through. `open` gives an account to anybody who proves they own an address. The first account on an empty instance needs no invitation in either mode — see below. An unknown value refuses to start. |
| `INVITATIONS_PER_USER`                     | `5`      | How many invitations one member may make per window — addresses they invite and accounts created through their invite link, counted together. A rate, not a lifetime allotment. Counted from the invitations themselves, revoked ones included, so it bounds emails sent and sign-ups through the link alike; a member at it has a link that admits nobody not already invited. Superusers are exempt. |
| `INVITATIONS_WINDOW_DAYS`                  | `1`      | The window those are counted over.                                                                                                                                                                                                                                                                                 |
| `INVITATION_ATTEMPT_RATE_LIMIT_PER_USER`   | `20`     | A separate backstop on how often one member may *attempt* an invitation, over `MAGIC_LINK_RATE_LIMIT_WINDOW_SECONDS`. Inviting an address that already has an account is refused without creating anything, so the quota above never charges for it; this is what stops that refusal being a probe. Superusers get it too. |
| `INVITE_REQUEST_RATE_LIMIT_WINDOW_SECONDS` | `3600`   | The window for the two limits below, on the anonymous request-an-invite endpoint. Consulted only in `invite` mode.                                                                                                                                                                                                 |
| `INVITE_REQUEST_RATE_LIMIT_PER_EMAIL`      | `3`      | Requests per window for one submitted address.                                                                                                                                                                                                                                                                     |
| `INVITE_REQUEST_RATE_LIMIT_PER_IP`         | `10`     | Requests per window from one caller, subject to `TRUSTED_PROXY_IPS` being right.                                                                                                                                                                                                                                   |

**The first account to sign in is yours, in both modes.** While the `user` table is empty the gate
lets the address through whatever `REGISTRATION_MODE` says, and the account it creates carries the
operator's rights. That is what keeps closed-by-default from being a first-run trap — a fresh
instance has no invitations and nobody who could send one — and it is why nothing here needs SQL or
a bootstrap script. It fires on the table being empty rather than once, so an instance whose last
account is deleted and purged hands the same deal to whoever signs in next.

**How you invite people.** Every member has an *Invitations* card in Settings, subject to the quota
above, which invites an address or hands out that member's own invite link. As the operator you
also get an **Admin** entry in the account menu — sign in as the first account, open the menu,
choose *Admin*. Its *Invite Queue* lists the addresses that used the request form, tells you which
of them already have an account, and invites or removes them in a batch; its *Stats* screen shows
daily totals of accounts created, sign-ins and active accounts; and its *Species* screen lists the
species catalog newest first, where you can hide a species' photo, pin another file from Commons in
its place, or re-fetch it by the rule.

An invitation typed against an email address is an entry against that address: the invitee signs in
with the address that was invited — by link, code or Google, exactly as anybody else does — so there
is no token for them to lose and nothing extra for you to explain. A member's **invite link** is the
other kind: one per member, shown on their card as an address and a QR code to copy, share or scan.
Whoever follows it creates an account with whatever address they sign in with, counted as that
member's invitation, and the member sees them on the card by the name on their account rather than
by address. Anybody holding the link can use it until its member resets or removes it on the same
card. It sends no email of its own.

Somebody who is not invited still gets their sign-in email. The endpoint that sends it deliberately
never learns whether an address is invited, or even whether it has an account, which is what keeps
it from being a way to enumerate your users; the refusal comes afterwards, once the link or code has
proven the address is theirs. [Troubleshooting](troubleshooting.md) has the message they see.

Requests that nobody acts on are deleted after 90 days, and so is an invitation nobody accepts; both
are somebody else's email address sitting in your database, and neither is a setting.

Flipping the mode is a restart of the `api` container with the new `.env` applied — `docker compose
up -d`, as with every setting here. The web app asks the API which mode it is in, so there is
nothing to change on the `web` service and nothing to redownload.

## Sign-in

Sign-in is passwordless, and an instance offers up to three ways in. **Email always works**: the
sign-in mail carries a link *and* a six-digit code, either of which completes it — the code is there
for the ordinary case of typing your address on a laptop and reading the mail on a phone. **Google**
appears if you set `GOOGLE_CLIENT_ID`. **Passkeys** appear when the visitor's browser can do
WebAuthn against this instance, which is a property of how you deployed it rather than a setting —
see below.

Nothing here is required. The defaults are the tested configuration, and an instance that sets none
of it still has working sign-in as long as mail is delivered. Who is *allowed* to end up with an
account is the separate question above — [Who may create an account](#who-may-create-an-account) —
and the answer to it changes none of the three methods.

| Variable                               | Default | What it does                                                                                                                                                                                                                                                                                     |
| -------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `SIGN_IN_CODE_ATTEMPTS_MAX`            | `5`     | Guesses allowed against the emailed code, the right one included. Running out spends the code only — the link in the same mail still works.                                                                                                                                                      |
| `PASSKEY_CHALLENGE_TTL_SECONDS`        | `600`   | How long a started ceremony stays completable. It is spent on the first attempt either way, so this bounds only an abandoned one.                                                                                                                                                                |
| `PASSKEY_MAX_CREDENTIALS_PER_USER`     | `10`    | Passkeys one account may hold. Abuse hygiene, not product policy.                                                                                                                                                                                                                                |
| `PASSKEY_OPTIONS_RATE_LIMIT_PER_IP`    | `240`   | Per IP, per `MAGIC_LINK_RATE_LIMIT_WINDOW_SECONDS`. High because one is minted per signed-out page view that offers passkey autofill, and an office behind one NAT gateway is a single IP here.                                                                                                  |
| `PASSKEY_VERIFY_RATE_LIMIT_PER_IP`     | `30`    | Per IP, same window.                                                                                                                                                                                                                                                                             |
| `PASSKEY_REGISTER_RATE_LIMIT_PER_USER` | `10`    | Per signed-in account, same window.                                                                                                                                                                                                                                                              |
| `API_KEY_MAX_PER_USER`                 | `10`    | API keys one account may hold, expired ones included until revoked. Abuse hygiene, as the passkey cap is — see [API access](api-access.md).                                                                                                                                                      |
| `API_KEY_CREATE_RATE_LIMIT_PER_USER`   | `10`    | API keys created per signed-in account, per `MAGIC_LINK_RATE_LIMIT_WINDOW_SECONDS`. Each creation sends an email, so this bounds a create-and-revoke loop as a mailer.                                                                                                                           |
| `REFRESH_TOKEN_EXPIRE_DAYS`            | `7`     | How long a browser stays signed in **without the app being used**. A rolling window, not a session length — read below before changing it.                                                                                                                                                       |
| `EXTENDED_REFRESH_TOKEN_EXPIRE_DAYS`   | `90`    | The same rolling window for a session that asked for a longer one when signing in with the emailed code — the iOS app always does, a browser never does. Also how long each create the app sent with an `Idempotency-Key` is remembered, so a retry days after a lost reply makes nothing twice. |
| `REFRESH_TOKEN_REUSE_GRACE_SECONDS`    | `60`    | How long a spent refresh cookie presented again is answered with what its first use was given — the retry after a reply lost on a bad connection — rather than ending the session as a stolen one. Below `5` the API refuses to start.                                                           |

**Three things worth knowing before you change these numbers.** The refresh cookie is single-use:
each time it is spent a fresh one replaces it with the clock started again, so the two windows bound
*inactivity* rather than the session. A browser used every day stays signed in indefinitely; one
left alone for longer than `REFRESH_TOKEN_EXPIRE_DAYS` asks for a sign-in link again. That is the
behaviour the web app describes, so raising or lowering it changes what the app does rather than
only how long a token lives. **`REFRESH_TOKEN_EXPIRE_DAYS` does not bound a session that asked to be
extended**: an instance that lowered it to sign people out sooner has to lower
`EXTENDED_REFRESH_TOKEN_EXPIRE_DAYS` too, or the iOS app stays signed in for the full extended
window.

The reuse grace is a trade, and it cannot be switched off. Inside it a spent cookie is honoured
rather than ending its session, so raising it widens the window in which a stolen one is replayed
successfully, and lowering it makes a retry after a longer dropout cost a sign-in. The same line is
also what tells two tabs refreshing at the same instant from a replay, which is why the API refuses
to start below 5 rather than signing a diver out for having two tabs open.

And the numbers are quoted back to divers as prose the web image ships. The note under the sign-in
button and the bundled privacy page's section on the sign-in cookie both say "about a week" from the
default of 7; the privacy page also says "about three months" from the default of 90 — for how long
the app stays signed in and for how long its retry records are kept — and "within about a minute"
from the grace's 60. None of them reads these settings, so an instance that changes one has copy
that no longer matches it. It is the same coupling as the privacy page's "within 30 days" against
[account deletion](#account-deletion), and the same remedy: pick numbers your own copy can honestly
stand behind, or expect to edit those lines.

There is deliberately **no on/off switch for passkeys**. The browser's own capability detection is
the switch: where a ceremony cannot work the web app hides the option rather than offering one that
fails, and a server flag would only be a second place for the answer to be wrong.

### Passkeys need HTTPS, and a hostname

Browsers expose WebAuthn only in a secure context, and they scope a credential to a *domain*. So an
instance is eligible when it is reached over HTTPS at a **hostname**:

- **Plain HTTP** gets no WebAuthn at all. The passkey option simply never appears; the emailed link
  and code serve that instance fully. This is the `AUTH_COOKIE_SECURE=false` LAN shape in
  [reverse-proxy.md](reverse-proxy.md) — nothing about it is broken, it just has two methods instead
  of three.
- **An IP address is never eligible**, certificate or not. `https://192.168.1.10` is a secure
  context, so the browser offers the API and then fails every ceremony: an IP is not a valid
  relying-party id. A hostname is the fix, not a better certificate.
- **`localhost` is exempt** by specification, which is why passkeys work in local development over
  plain HTTP.

The bundled Caddy gets a certificate for `DOMAIN` on its own, so the default install is already
eligible. A LAN box can become eligible without going public: anything that gives it a real hostname
and a certificate the browser trusts — a Tailscale HTTPS name, an internal CA — works, as long as
`FRONTEND_URL` is then set to that `https://` hostname.

### `FRONTEND_URL` is the passkey domain

The relying-party id and the expected origin are both derived from it; there is no separate setting.
Two consequences worth knowing before you edit it:

- **Changing its hostname orphans every passkey already registered.** Browsers will not offer a
  credential created under one domain to another, and the API will not accept one. Nobody is locked
  out — the emailed link is the recovery path, and everyone re-adds a passkey afterwards — but it is
  silent, so treat a hostname change as "everyone signs in by email once".
- **Write it without a trailing slash.** Everything checked against what the browser sends — the
  allowed CORS origin, the passkey origin, the Google redirect URI — is rebuilt from the parsed URL,
  so `https://dive.example.com/` is tolerated there. Emailed links are the value with a path
  appended, though, and would carry a double slash.

`SITE_URL` is the web app's own origin and should move with it.

### Setting up Google sign-in

Google sign-in needs an OAuth client of your own, created once in the
[Google Cloud Console](https://console.cloud.google.com/apis/credentials). It is the only optional
feature here that requires anything outside this instance, and there is no shared or default client
to fall back on — an OAuth client is tied to the exact URLs it will redirect to, so it has to be
yours.

Create credentials of type **OAuth client ID**, application type **Web application**. Two things
come out of it and both go in your `.env`:

| From the Console  | Into `.env`            | Secret?                                                                                           |
| ----------------- | ---------------------- | ------------------------------------------------------------------------------------------------- |
| **Client ID**     | `GOOGLE_CLIENT_ID`     | No. It travels in a URL the visitor can read, and the web app uses it too.                        |
| **Client secret** | `GOOGLE_CLIENT_SECRET` | **Yes.** It stays on the API. Never put it anywhere the browser or the `web` container can reach. |

Then register, on that same client:

- **Authorized redirect URI** — `{FRONTEND_URL}/auth/google/callback`, exactly. For the default
  install that is `https://dive.example.com/auth/google/callback`; locally it is
  `http://localhost:3000/auth/google/callback`. This is where Google sends the visitor back.

**Upgrading an instance that already had Google sign-in?** That client almost certainly has no
redirect URI at all — the previous flow never sent one, so a client created for it carries an
authorized JavaScript *origin* and nothing else, and the gap is invisible until the first sign-in
attempt after the upgrade. Add the redirect URI above. The origin already on it does no harm and can
stay.

Google constrains both lists the same way, and has done all along — this is not a new restriction,
only one that was never written down here:

- **Redirect URIs must use HTTPS**, with `http://localhost` URIs exempt.
- **The host cannot be a raw IP address**, with localhost IPs exempt.

So a plain-HTTP instance on a LAN address has never been able to offer Google sign-in and still
cannot: there is no redirect URI Google will accept for it. That instance has the emailed link and
code, which serve it fully. It is the same eligibility question passkeys have, for a different
reason, and the same fix — a real hostname and a certificate the browser trusts.

Three separate things can be wrong here, and each says so differently:

- **`GOOGLE_CLIENT_ID` set with no `GOOGLE_CLIENT_SECRET`** — the API refuses to start, naming both
  variables. It fails at startup rather than at the first click because the web app decides whether
  to show the button from its own copy of the client id and cannot know the API is short a secret.
- **`FRONTEND_URL` disagreeing with the origin visitors actually reach** — `POST /auth/google`
  answers 400 naming `FRONTEND_URL`, from this app.
- **A redirect URI you have not registered** — Google refuses the exchange and sign-in answers 401.
  Set `LOG_LEVEL=DEBUG` and the API logs the short reason Google gave (`redirect_uri_mismatch`,
  `invalid_client`, …). Nothing from Google's answer is logged above that level, deliberately.

### When something is down

The three methods fail independently, which is most of the argument for having three:

| Down       | Email link / code    | Passkey                    | Google |
| ---------- | -------------------- | -------------------------- | ------ |
| Mail relay | ✗                    | ✓                          | ✓      |
| Redis      | ✓ (limits fail open) | ✗ (challenges fail closed) | ✓      |
| Google     | ✓                    | ✓                          | ✗      |
| Postgres   | ✗                    | ✗                          | ✗      |

Redis is deliberately the odd one out. Rate limiting there fails *open* — an outage must not lock
everyone out of an app — but a passkey challenge **is** the replay protection, so with Redis
unreachable the passkey endpoints answer 503 rather than verifying a ceremony without one. Email
sign-in is pure Postgres and is unaffected.

The `Google` row covers two different reachability problems, and only one of them is the visitor's.
Their browser has to reach `accounts.google.com` to sign in at all, and **your API has to reach
`oauth2.googleapis.com`** to redeem the code they come back with. So an instance with filtered
outbound traffic can have Google sign-in fail on a network that looks perfectly healthy from the
diver's side, with a 503 rather than a rejected credential. The other two methods are unaffected,
which is the row as drawn.

## Database, cache, migrations

`POSTGRES_SERVER`, `POSTGRES_PORT`, `REDIS_CACHE_HOST` and `REDIS_QUEUE_HOST` are set by the compose
file to the service names and are not yours to change. `POSTGRES_USER` and `POSTGRES_DB` both
default to `opendiving` and can be overridden in `.env` before the first start (afterwards they name
a database that already exists under a different name).

| Variable                 | Default       | What it does                                                                                                                                                                                                                                                                                                                                               |
| ------------------------ | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MIGRATE_ON_START`       | `true`        | Runs `alembic upgrade head` as the API starts, which is what makes an upgrade `pull` + `up -d`. Turn it off only if you'd rather run `docker compose run --rm api alembic upgrade head` yourself.                                                                                                                                                          |
| `REDIS_PASSWORD`         | *(none)*      | For pointing the app at a managed Redis instead of the bundled one. The bundled one needs no password and is not reachable outside the compose network.                                                                                                                                                                                                    |
| `FILE_STORAGE_BACKEND`   | `local`       | Where uploaded files are kept: `local` writes them into `FILE_STORAGE_DIR`, `s3` puts them in an S3-compatible bucket. The bundle mounts a volume for `local`, so a compose install on one machine has nothing to set here — see [Object storage](#object-storage) for the install that does. Any other value refuses to start.                             |
| `FILE_STORAGE_DIR`       | `/data/files` | Where the `local` backend writes uploaded dive-computer exports, c-card images, profile pictures, portraits, species photographs and the [map tiles](#the-map-renderer) behind cards and page heads, inside the container. The compose file mounts the `files-data` volume there, so there is nothing to set unless you replaced that volume with a bind mount — and then the host directory has to be owned by uid 1000 or the API refuses to start. Ignored entirely under `s3`. |

Redis holds cache entries, open rate-limit windows, in-flight passkey challenges and, for the
[reuse grace](#sign-in), the answer each recent refresh was given. Losing it costs a cold cache,
interrupts passkey sign-in until it is back and makes a refresh retried inside the grace sign in
again; nothing durable lives there. What is durable lives in two places, and a backup has to cover
both: the records are in Postgres, and the uploaded files themselves are on the `files-data` volume — or in
your bucket, if you switched the backend below. See [backup-restore.md](backup-restore.md).

### Object storage

The default is a filesystem volume, and for almost every install that is the right answer: one
machine, one disk, no credentials to hold. `FILE_STORAGE_BACKEND=s3` is for the install where it is
not — a platform whose disk attaches to one service at a time, while both the `api` and the `worker`
container need the same files. Any S3-compatible store will do: Cloudflare R2, MinIO, Garage, Ceph,
Backblaze B2, AWS itself. Nothing about the app changes; the same uploads go to a bucket instead of a
directory, under the same names.

| Variable                                   | Default  | What it does                                                                                                                                                                                                            |
| ------------------------------------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `S3_ENDPOINT_URL`                          | *(none)* | The store's full origin, scheme included — `https://<account-id>.eu.r2.cloudflarestorage.com` for R2, `http://minio:9000` for a MinIO beside this stack. There is no default because every store's is different.       |
| `S3_BUCKET`                                | *(none)* | The bucket. It has to exist already; nothing here creates one.                                                                                                                                                          |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | *(none)* | The credential. It needs to read, write, delete and list inside that one bucket, and nothing beyond it.                                                                                                                 |
| `S3_REGION`                                | `auto`   | `auto` is what R2 documents and what every other S3-compatible store ignores. A real AWS bucket needs its own region here instead.                                                                                      |
| `S3_PREFIX`                                | *(none)* | An optional key prefix, for sharing one bucket between instances. Prepended to every object name. The keys the database holds are the same either way, so adding or removing it later means moving the objects to match. |

**The first four are required, and startup enforces it.** With `FILE_STORAGE_BACKEND=s3` and any of
them unset, the API refuses to start and names the ones that are missing, rather than starting and
failing on the first diver's upload. Then it writes a probe object and deletes it again, so a wrong
bucket name, a credential that can read but not write, or a bucket in somebody else's account fails
at `docker compose up -d` with the endpoint and the bucket in the message. A key that cannot list is
the one gap: startup does not refuse it, but once anything is stored it logs an ERROR at every boot,
`Could not list …`, instead of checking that the bucket holds the files the database references —
and the orphan sweep and a copy out of the bucket fail.

**The worker needs the credentials too**, and the compose file already hands them over — `.env` goes
to `api` and `worker` wholesale, so there is nothing extra to set. It is worth knowing why it
matters: the worker is what destroys a deleted account's files once the grace period runs out (see
[Account deletion](#account-deletion)), and it runs that same probe at startup, so a worker that
cannot reach the bucket dies loudly instead of reporting erasures it did not perform. The
`files-data` mount on both services goes unused under `s3`; leave it there, and switching back stays
one variable.

**Keep the bucket private.** Every byte is served through the API, which reads the object and hands
it to a request it has already authorised — nothing generates a public or pre-signed URL, so a
bucket that allows anonymous reads is not enabling anything, only exposing c-card scans and
portraits to whoever guesses a key.

**Deletions land just after the job, not at the click.** What a purge destroys is unchanged, but on
`s3` the objects go in a request the app does not wait for: the transaction commits, the rows are
gone, and the delete follows a moment later on a background thread — because waiting for a round trip
to the store there would stall everything else the process is serving. So a bucket you are watching
may still list a purged account's keys for a few seconds. If one fails, it is logged and the object
becomes an orphan, which is what the sweeper reclaims:

```bash
docker compose exec api python -m src.scripts.sweep_orphaned_files          # report only
docker compose exec api python -m src.scripts.sweep_orphaned_files --delete
```

**Switching between the two backends is a copy, not a migration** — the key a row carries is the same
string on both, which is why nothing in the database has to change. Put the `S3_*` group in `.env`
and leave `FILE_STORAGE_BACKEND` naming the backend you are moving *away* from, so that both are
configured at once. Then recreate the containers, and copy:

```bash
docker compose up -d
docker compose exec api python -m src.scripts.migrate_blobs --to s3
```

That `up -d` is doing real work, and skipping it fails in a confusing way. `exec` runs a process
inside a container that still holds the environment it was *created* with, so on the container
started before you edited `.env` the copy refuses, saying the `S3_*` group is unset — while you are
looking at it in `.env`. It is the trap the top of this page warns about, met in the one procedure
here that reaches into a running container rather than restarting it.

The copy never deletes from the source, and it is resumable: every key ends in the sha256 of the file
as uploaded — followed by `.zst` for a dive-computer file, which is stored compressed — so an object
already sitting under that key cannot hold a different file and is skipped rather than re-sent. What
it does copy is checked against that digest first, a compressed object by decoding it, and one that
does not match is reported as a failure and left behind rather than carried across. Interrupt it and
run it again. When it reports no failures, set `FILE_STORAGE_BACKEND` to the backend you copied
*into* and `docker compose up -d` once more — that second recreate is what actually moves the
instance across.

`--to local` runs the same procedure in the other direction, with the two backend names swapped
throughout.

Run it against a quiet instance. Anything uploaded after the copy has walked past its key stays on
the old backend, and its row will point at bytes the new one does not have — a second run after the
switch catches whatever arrived in between. Reclaiming the old copy is a separate, deliberate step
once the new backend has been seen to serve: `docker volume rm opendiving_files-data` with the stack
down, or the bucket's own lifecycle rules going the other way.

## Optional features

| Variable                                                                                                           | Default             | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------------------------------------ | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CONTACT_FORM_EMAIL`                                                                                               | *(none)*            | Where the support form delivers. Unset, that endpoint answers 503 and the form is off.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `CONTACT_EMAIL`                                                                                                    | *(none)*            | Shown on the support page as a fallback, and published as the contact in the API's schema at `/api/v1/openapi.json`, on every instance.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `GOOGLE_CLIENT_ID`                                                                                                 | *(none)*            | Offers Google Sign-In, which needs an OAuth client of your own — see [Setting up Google sign-in](#setting-up-google-sign-in). Nothing of Google's loads in a visitor's browser; pressing the button takes them to Google. Unset, the button is hidden.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `GOOGLE_CLIENT_SECRET`                                                                                             | *(none)*            | The other half of that OAuth client, and a real secret. Required whenever `GOOGLE_CLIENT_ID` is set — the API refuses to start without it. See [Setting up Google sign-in](#setting-up-google-sign-in).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `MAP_STYLE_URL`, `MAP_STYLE_URL_DARK`                                                                              | OpenFreeMap         | A MapLibre vector style of your own, in place of the pair the web image ships — see [Third-party calls](#third-party-calls). Wins over the raster group below outright, on every map the app draws, leaving those variables inert. The dark one falls back to the light one; setting it alone does nothing. Serve the style's tiles, glyphs and sprite from the style URL's own host: that origin is the only one the CSP admits, so a style reaching a second host draws blank.                                                                                                                                                                                                                                                                                                                            |
| `MAP_ATTRIBUTION`                                                                                                  | the basemap's       | The credit drawn over whichever basemap is active — one variable, not one per mode, which is why it is no longer `MAP_TILE_ATTRIBUTION`. **Required whenever `MAP_STYLE_URL` is set**: the app refuses to serve without it, because it cannot know what your style's licence asks for.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `MAP_TILE_URL`, `MAP_TILE_URL_DARK`, `MAP_TILE_API_KEY`                                                            | *(none)*            | The raster escape hatch, in `{z}/{x}/{y}` form, for a tile server you run or a keyed provider. A whole-map mode chosen instead of the vector default, not a second renderer: MapLibre wraps the template into a minimal style. Ignored entirely when `MAP_STYLE_URL` is set. The CSP follows all of these automatically. **`MAP_TILE_API_KEY` is not a secret and cannot be one** — the dive site finder's and the forms' maps are drawn in the browser, so the key is handed to every visitor along with the tile URL and is readable in the page, and the iOS app is handed it in the style. Use a key the provider has restricted to your own domain, and never one that also buys geocoding, routing or anything else on the same account. With the [map renderer](#the-map-renderer) on, the key is sent from this stack too, with your domain as the origin, so that restriction keeps working — except in the iOS app, whose requests name no origin: see [Third-party calls](#third-party-calls).                                                                                                                                    |
| `GEOCODER_URL`                                                                                                     | Nominatim           | Names the spot behind a map pin, server-side, and has to name a Nominatim-compatible host. Set to `""` to switch geocoding off entirely, place search included, whatever `GEOCODER_SEARCH_URL` says.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `GEOCODER_SEARCH_URL`                                                                                              | Photon              | Answers a place typed into the dive site finder — the Sites section's search and the dive form's, in the browser and in the iOS app — and into the search on the dive site form and the trip form, server-side: the typed search string goes out, nothing identifying the diver, and not the map's centre the finder's search carries. Has to name a Photon-compatible host. The default is the public instance komoot runs, a demo server with no availability guarantee — when it fails, no places come back, the finder still lists sites, and a form's diver types the name in. It does not follow `GEOCODER_URL`: pointing that at your own Nominatim still sends searches to komoot until this names a Photon of yours. Set to `""` to switch place search off while pins are still named; the finder then searches sites alone.                                                                                                                                                                                                                            |
| `GEOCODER_USER_AGENT`                                                                                              | the project's       | The `User-Agent` on every geocoder call, to both providers, and the only place it is sent. Ships as `OpenDiving (+https://github.com/opendiving/opendiving-api)`. It fails closed harder than `SPECIES_USER_AGENT` does: Nominatim answers **403** to an empty value *and* to a merely generic one — `python-httpx/0.27` was measured taking the same 403 as `""`, where the shipped default takes a 200 — and a 403 there costs naming the spot behind a pin. Photon's maintainers give a generic agent no guarantees, so place search is at risk too. Either way the API stays healthy, and the only trace is a warning in the API log naming the provider and what went wrong. Change it because the default identifies the *project*, not your instance — see [Third-party calls](#third-party-calls).  |
| `DIVE_SITE_SEARCH_RATE_LIMIT_PER_USER`, `DIVE_SITE_SEARCH_RATE_LIMIT_WINDOW_SECONDS` | `300`, `300` | Searches one account may make of the dive site finder per window of that many seconds. The finder asks once a pause in typing and once per *Search this area*, so the default is a request a second for five minutes, past anyone typing; beyond it the search answers 429 until the window passes. |
| `DIVE_SITE_SEARCH_GEOCODER_BUDGET_SECONDS` | `2` | How long a typed finder search waits on `GEOCODER_SEARCH_URL` for its places. Past it the answer comes back with the sites and without the places, so a slow geocoder costs the places and nothing else. A typed search also spends the account's geocoder budget, and a spent one costs the places, never the search. |
| `KHOA_API_KEY` | *(none)* | A data.go.kr service key for the water depth API of KHOA, the Korea Hydrographic and Oceanographic Agency, and a real secret. It is the finest source the seafloor explorer has in Korean waters; unset, KHOA is reported as not configured there and the global sources answer instead. The explorer's other sources need no key — see [Third-party calls](#third-party-calls). Encoded or decoded, as data.go.kr issues it, both work. Its quota is 10,000 requests a day, shared by every account, and a view the cache can't answer spends one or two. |
| `SEAFLOOR_RATE_LIMIT_PER_USER`, `SEAFLOOR_RATE_LIMIT_WINDOW_SECONDS` | `120`, `3600` | Seafloor views one account may ask for per window of that many seconds, cache hits included. Beyond it the explorer's endpoint answers 429 until the window passes. A view the cache can't answer can cost a dozen third-party requests and some of KHOA's shared daily quota, which is why this is tighter than the finder's. |
| `WORMS_API_URL`, `WIKIDATA_API_URL`                                                                                | public              | The two name registers the species picker searches, called server-side. WoRMS is the taxonomic authority every catalog row is keyed on; Wikidata supplies the common names it lacks — WoRMS records exactly one vernacular for the clownfish, and it is in Japanese. Emptying one does not switch the feature off the way `GEOCODER_URL` does: search falls back to the species already in your catalog, and resolving one nobody has logged yet fails.                                                                                                                                                                                                                                                                                                                                                     |
| `COMMONS_API_URL`                                                                                                  | public              | Wikimedia Commons, asked for a species photo's credit metadata and the URL of one scaled copy once Wikidata or an admin has named the file, and for the files in a species' Commons category when an admin opens its photo picker — never for anything a diver typed. This one *is* optional in the way the two above are not: `""` or an unreachable host simply means species have no photos. It configures the **metadata** calls only. The image bytes, the picker's previews included, are only ever fetched from `thumb.wikimedia.org` or `upload.wikimedia.org`, the two hosts one Commons reply can name; that pair is hard-coded and deliberately has no setting in front of it, because it is an SSRF fence — see [Third-party calls](#third-party-calls).                                                                                                                                                                            |
| `SPECIES_USER_AGENT`                                                                                               | the project's       | The `User-Agent` on every species call — both registers, and every Commons call, metadata and image bytes alike. Ships as `OpenDiving (+https://github.com/opendiving/opendiving-api)`. Emptying it is **not** the graceful off switch the row above is: Wikimedia answers **403** to an empty one, on the metadata call and the byte fetch both, and the same header goes to WoRMS and Wikidata — so a blank value takes species search and resolution with it, not only the photos, and the API starts normally either way. Change it because the default identifies the *project*, not your instance: every deployment sends that one string, so one operator's runaway backfill is attributed to everyone running OpenDiving; put your own contact in — see [Third-party calls](#third-party-calls).   |
| `SPECIES_WORMS_RATE_LIMIT_REQUESTS`, `SPECIES_WIKIDATA_RATE_LIMIT_REQUESTS`, `SPECIES_COMMONS_RATE_LIMIT_REQUESTS` | `120`, `300`, `120` | What the whole instance may spend on each upstream, over `SPECIES_WORMS_RATE_LIMIT_WINDOW_SECONDS`, `SPECIES_WIKIDATA_RATE_LIMIT_WINDOW_SECONDS` and `SPECIES_COMMONS_RATE_LIMIT_WINDOW_SECONDS` — `60` seconds each. Counted across every user and charged only to calls that actually leave, so exceeding one is never a 429: that upstream drops out and the rest still answer. Neither provider publishes a limit — WoRMS states none at all, and Wikimedia's applies to anonymous heavy use rather than to a call every few seconds — so all three are self-imposed politeness, set well above what a picker generates. Commons's is lower than Wikidata's and still ample — it is charged at most twice per *new* species, the credit call and the byte fetch, rather than once per search candidate, and an admin adds a few: two for a re-fetch or a pin, two or three to open the photo picker, whose previews are charged nothing. |
| `DIVE_CONDITIONS_PROVIDER`                                                                                         | *(none)*            | Off as it ships: nothing is asked. `open-meteo`, the one provider, has a cron in the worker fill a dive's empty air temperature, weather and waves from the weather, sea state and tide at the dive's place and hour, and the dive page shows the rest of what came back; a filled value is marked as fetched until the diver types another. Any other value is refused at startup. Open-Meteo's free API is for non-commercial use only — read [Third-party calls](#third-party-calls) before setting it. |
| `DIVE_CONDITIONS_OPEN_METEO_API_KEY`                                                                               | *(none)*            | A subscriber's key, and a real secret. Set, every call goes to Open-Meteo's `customer-` hosts carrying it; unset, to the free ones. It has to be on a plan that includes the Historical Weather API — Professional or above: a key without it, Standard included, is refused on the archive and nothing is filled. |
| `DIVE_CONDITIONS_OPEN_METEO_RATE_LIMIT_REQUESTS`, `DIVE_CONDITIONS_OPEN_METEO_RATE_LIMIT_WINDOW_SECONDS`           | `400`, `3600`       | What the whole instance may spend on Open-Meteo over that many seconds, charged only to calls that leave. The default sits under the free API's hourly, daily and monthly caps at once, which leaves room for one instance behind an address, not two — Open-Meteo limits by address. Over it, the run stops and the remaining dives wait for a later one; nothing errors. |

### The map renderer

The cards that list dives and trips carry a map behind them — every card in the lists of dives and
trips, the dashboard's recent dives and trips, and the dives listed on the
page of a dive site, a trip, a piece of gear, a species, a course or a person — and so does the head
of a dive's, a trip's and a dive site's own page. This stack draws those maps, not the browser: the
`map-renderer` service, a second program in the web image, draws square tiles of the map, and the
API stores each one once for the whole instance. A card or a page head is put together from the
tiles that cover it, with its own pins drawn over them, so one tile serves every card, page head and
account that shows that stretch of coast. It is **off unless you switch it on**, and with it off
every card and every page head shows water where its map would be. The service is in the bundle
from the release after 0.3.0.

The iOS app's maps need it too — the Sites tab, the dive form's *Find a Dive Site* and the forms —
for a different thing: not tiles, which stop too far out to place a pin on, but the basemap's style. The renderer resolves the same `MAP_*` variables the web app reads,
the API passes the result on at `GET /api/v1/map-style/{theme}`, and the app draws it itself wherever
`/api/v1/config` says `map_tiles` and names `map_attribution`. With the renderer off that route
answers 404 and the app draws no map: its finder is a list and a search, and a form's pin is still
placed by coordinates, place search or "Use my location". The web app's maps — the Sites section's,
the dive form's *Find a dive site* and the forms' — are drawn in the browser either way.

Switching it on takes two lines in `.env`, and both are needed:

```bash
COMPOSE_PROFILES=proxy,map-renderer   # starts the service; just map-renderer behind your own proxy
MAP_RENDERER_URL=map-renderer:3000    # tells the API to use it
```

then `docker compose up -d`. Either line alone changes nothing a diver can see —
[troubleshooting.md](troubleshooting.md#cards-and-page-heads-show-water-instead-of-a-map) has what
each looks like. An install made from an earlier release has to re-download `docker-compose.yml`
first, since the service is defined there —
[upgrade.md](upgrade.md#cards-and-page-heads-need-the-map-renderer).

Switching it off is the same two lines taken out again, and one command more: `docker compose up -d`
leaves alone a service whose profile is no longer listed rather than stopping it, so
`docker compose rm -sf map-renderer` is what stops it.

| Variable                              | Default  | What it does                                                                                                                                                                                                                           |
| ------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MAP_RENDERER_URL`                    | *(none)* | Where the API reaches the renderer — `map-renderer:3000` for the bundled service. Empty draws no maps, nothing asks for one, and the iOS app has none to show.                                                                                                       |
| `MAP_RENDERER_TIMEOUT`                | `90`     | Seconds one tile may take to arrive, its wait in the renderer's queue included. Raise it, never lower it — see below.                                                                                                                  |
| `MAP_RENDERER_DRAW_LIMIT_PER_USER`    | `150`    | Tiles one account may have drawn per window. Past it, a card or page head that needs a tile nobody has drawn yet shows water until it is shown again; a tile already stored, or one being drawn for another request, is never counted. |
| `MAP_RENDERER_REQUEST_LIMIT_PER_USER` | `1200`   | Tile requests one account may make per window, stored tiles included, and the iOS app's reads of the map style with them. Past it every card and page head that still needs a tile shows water, and a screen in the app that still needs the style has no map. It is there because a stored tile answers faster than a drawn one — see below.             |
| `MAP_RENDERER_LIMIT_WINDOW_SECONDS`   | `60`     | The window both limits are counted over.                                                                                                                                                                                               |

**What it costs.** Memory first: the renderer peaks at roughly 210 MB, measured on amd64 held to
half a CPU and 512 MB, which is why it is off by default — the 1 vCPU, 1 GB floor in
[install.md](install.md#what-you-need) is for an install without it, and two GB is the floor with
it. Then time: on that measurement a cold tile — the renderer's first of a square, with nothing of
it fetched yet — took 0.4 to 1.6 seconds to draw, 0.8 at the median, and the renderer draws one at a
time. A card can need up to six tiles and shows none of them until it has
them all, so the first view of a stretch of coast nobody here has been shown fills in card by card;
every view after that, by anyone on this instance, is the stored tiles. Nobody has measured it on a
Raspberry Pi yet; it runs there, being the same image on arm64, but expect it to be slower.

**`MAP_RENDERER_TIMEOUT` is raised, never lowered.** The renderer queues up to 55 draws, and the
setting is one deadline for the whole of a tile's wait, so it has to cover a full queue: 90 seconds
covers 55 draws at the slowest time measured. The renderer logs each draw —
`docker compose logs map-renderer` shows lines like
`drew a tile, light 9/301/215, in 790 ms, after 0 ms in the queue` — and where 55 times the slowest
cold draw you see is more than 90 seconds, set it to that. Below what a full queue needs, the last
cards of a busy page give up and show water. A proxy of your own in front of the stack has to wait
at least as long: [reverse-proxy.md](reverse-proxy.md) has the nginx line.

**It draws the basemap the browser draws.** The compose file hands it the same `MAP_*` variables and
`SITE_URL` it hands `web`, so there is nothing more to set, and a card or a page head shows the same
map as the Sites section and the dive site and trip forms. On the default basemap that is OpenFreeMap, whose terms ask for
permission before anything collects from it automatically. It has given it: asked by the project, it
answered that drawing card maps on the server is fine for self-hosted installs as well as for the
project's own instance, asking that the request rate stay reasonable and the caching stay in place.
The project reads that as covering the page heads, which are drawn from the same tiles, and the
renderer keeps both conditions as it ships — it draws one tile at a time, and a tile once drawn is
stored and shared by every card, page head and account that shows it, so the provider is asked for
each square once for each theme and label language rather than once per dive, trip or site. On a
basemap of your own, it is that provider's terms that apply.

**The tiles are files, kept like uploads and belonging to nobody.** Each tile, one per theme and
label language, is stored in the same place as the uploaded files — the `files-data` volume, or
your bucket — and deleted after 30 days in which nobody was shown it. A tile holds nothing of
anybody's logbook: it is drawn from the basemap alone, so it counts against no
[storage limit](#storage-limit), is not in an export, and is not deleted with an account, and a
restore without the tiles simply draws them again.

**What sharing tells your members.** Because a stored tile answers faster than one drawn on the
spot, a signed-in member could learn that someone on this instance was shown a given square — a
region tens of kilometres across — in the last 30 days, though not who, or what dive or site it was
for, and, for a tile labelled in a second language, that their browser asked for that language.
`MAP_RENDERER_REQUEST_LIMIT_PER_USER` bounds how fast anyone can ask, and does not remove it; the
bundled privacy page tells your members about the square. Its effect on third parties is under
[Third-party calls](#third-party-calls): for these maps the basemap's provider sees this server, not
the diver.

**Nothing but the API should reach it.** It takes no credential, so the service publishes no port and
the Caddyfile has no route to it; leave both that way.

### Storage limit

| Variable           | Default | What it does                                                                                                                                                 |
| ------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `STORAGE_LIMIT_MB` | `1024`  | How much one account may keep stored, in MB (1024-based). `STORAGE_LIMIT_MB=` with nothing after the `=` means no limit. A value below 1 refuses to start.   |

**It is on unless you turn it off**, on a new install and on one upgraded from a version without it:
an `.env` that does not name the setting gets the default, and so does one where the line is still
commented out. Only the blank value means unlimited. It is one number for every account, the
administrators' included, with no per-account override.

**What counts is what the account occupies on your disk or in your bucket**: its dive-computer files
as stored, which is compressed — a Suunto JSON export keeps about a tenth of its size, a FIT file
about a quarter — plus its c-card scans, and its profile picture and portrait, the original and the
resized copy of each. At those sizes the default holds a few thousand dives' worth of recordings.
Species photographs are a catalogue the whole instance shares, and count against nobody; so do the
[map tiles](#the-map-renderer), which this server draws rather than anybody uploads. A
dive-computer file stored by an earlier version stays as it was, uncompressed, and counts at its
full size.

**The files of a waiting [import](#imports) are not counted**, and one import per account is what
bounds them: at most the 500 MB one import may carry, plus what a plain zip's readable files unzip
to, since those are held unzipped and the zip is not, and one import reads at most 100 MB of them.
What an import keeps counts once it is applied.

**An upload that would take an account past it is refused**, before anything is stored, with a
message that names both figures: "This upload would take your account past its storage limit: … of
… used." A dive being logged is still saved, without the file; an import whose files would cross
the limit — the files of one dive it keeps, or those a full-export archive restores — is refused
whole, at the upload or again when it is applied, with nothing imported. Nothing already stored is ever removed, so lowering the number below
what an account holds leaves its files in place — it can still delete, and replace a c-card scan or
a picture with a smaller one, but cannot add. Nothing locks around the check either: two uploads
racing each other can overshoot the limit by one of them.

### Imports

| Variable                        | Default | What it does                                                                                                                                                                                                   |
| ------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `IMPORT_PENDING_LIFETIME_HOURS` | `24`    | How long an uploaded import waits to be applied or discarded, in hours, before it and its files are deleted. `IMPORT_PENDING_LIFETIME_HOURS=` with nothing after the `=` keeps it until the diver finishes it. |
| `IMPORT_HISTORY_RETENTION_DAYS` | `30`    | How long an applied import's review and log stay in its history, in days. `IMPORT_HISTORY_RETENTION_DAYS=` with nothing after the `=` keeps each until the diver deletes it.                                   |

A value below 1 refuses to start, for either: blank is the one way to say no limit.

**A logbook import is uploaded once and lives on the server.** The files the app could read go into
the same storage as every other upload and the review into the database, which is what lets any of
the diver's devices open it. An account has one import waiting at a time, and a second upload is
refused until that one is applied, discarded or past its lifetime. Applying it deletes its files and
starts its history: the review and the log stay readable from the import page until the retention
runs out or the diver deletes them.

**Each import carries its own deadline**, set at the upload and set again at the apply, so a changed
value reaches the imports uploaded or applied after it and leaves the rest as they are. Past its
deadline an import stops answering at once, and the worker deletes it on the next hour. Leaving the
pending lifetime blank means a diver who walks away from an import leaves its files on your disk or
in your bucket, uncounted by the [storage limit](#storage-limit), until they come back to it.

### Account deletion

| Variable                      | Default | What it does                                                                                                              |
| ----------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------- |
| `ACCOUNT_DELETION_GRACE_DAYS` | `14`    | How long a deleted account stays restorable before it and everything it owns are destroyed. `0` purges on the next sweep. |

Deleting an account takes effect immediately — the app stops opening, on every device — but the data
is not destroyed until the grace period runs out. A cron in the `worker` container runs hourly at
:30 and issues a real `DELETE FROM "user"` for each account past its deadline, taking that diver's
dives, dive drafts, dive sites, their notes on Commons sites, any proposals for the
[Commons](#opendiving-commons), certifications, check-in details, gear, trips, contacts, people,
tags and every uploaded file with it. A record the Commons has already accepted stays, being the
Commons' and no longer that diver's.
Nothing else purges an account, and nothing decides on a user's behalf that one should go: the job
only ever executes a request the user already made.

**Two things worth knowing before you change the number.** The bundled privacy page states that
personal information is permanently deleted within 30 days. That sentence is true at the default and
stays true up to about 29 days; raise this past that and the page your instance serves is making a
promise your configuration breaks. And at `0` there is no way back at all — the confirmation email
says so instead of naming a date, but a misclick is then final.

**You are the controller.** OpenDiving is software; the operator of an instance is who data
protection law has obligations for. This setting is the knob that erasure requests are served by —
what it does, and how promptly, is your call to make and to document.

**Two things the purge cannot reach**, and both are yours to handle rather than the app's. Your
backups keep a deleted account until they rotate, and restoring one older than the request brings
that account back — see [backup-restore.md](backup-restore.md). And if you have turned the admin
panel on, its own event and audit tables hold a second copy of whatever you edited there; see
[The admin panel](#the-admin-panel).

### The admin panel

Off by default, and a deliberate opt-in: it is a full CRUD interface over every model and bypasses
the ownership checks the API applies to everything else. It is **not** where you work the invite
queue — that is the app's own [Admin section](#who-may-create-an-account), which needs none of this.

```bash
CRUD_ADMIN_ENABLED=true
ADMIN_PASSWORD=a-real-password        # only local starts without one, or with a placeholder
ADMIN_USERNAME=admin
CRUD_ADMIN_MOUNT_PATH=/crud-admin     # required now: /admin is the app's own admin section
CRUD_ADMIN_ALLOWED_NETWORKS=10.0.0.0/8   # optional, comma-separated
```

**`CRUD_ADMIN_MOUNT_PATH` is the line that is new, and enabling the panel without it gets you the
wrong page.** The panel still defaults to `/admin`, and `/admin` is now a page of the web app, which
is where the bundled Caddyfile sends it. Move the panel somewhere else and the two stop colliding —
then add a route for the path you chose, since the bundle routes only what it knows about. The
Caddyfile carries a commented-out block for exactly this at the top; for your own proxy it is one
more `location` or router, alongside the one in [reverse-proxy.md](reverse-proxy.md).

The compose file already points its tables at the app's Postgres (`CRUD_ADMIN_DB_URL`), which is
what makes it work behind four API workers. If your `POSTGRES_PASSWORD` contains `@`, `/`, `:` or
`#`, percent-encode it in that derived URL.

The allowlist matches the caller's address only when `TRUSTED_PROXY_IPS` names the proxy actually in
front of the app — the panel's own middleware reads the forwarded address the app was told to
believe. The same setting is what stops the panel redirecting its own path to the HTTPS URL it is
already on: it enforces HTTPS on `ENVIRONMENT=production`, and a proxy the app hasn't been told
about makes every request look like plain HTTP. Both symptoms are one misconfiguration, and the
shipped value covers the bundled Caddy.

Running your own proxy? The panel is the one thing a single `web:3000` upstream does not carry, so
route whatever you set `CRUD_ADMIN_MOUNT_PATH` to at `api:8000` yourself — and make sure your proxy
is in `TRUSTED_PROXY_IPS` **and** sets `X-Forwarded-Proto`. Nothing else needs splitting out:
`/admin` is a page of the web app and reaches the API the way every other page does.

**The panel signs its administrators in with cookies of its own**, set under `CRUD_ADMIN_MOUNT_PATH`
when someone logs in to it. They are part of the surface you operate rather than anything a diver
meets: nobody using the app receives one, and they exist only in the browser of whoever administers
this copy. That is why the bundled privacy page — written for the people whose dives your instance
holds — does not describe them, and points operators here instead. They belong to `crudadmin` and
their names are its business, not this app's, so read them out of your own browser rather than from
a list here that a dependency upgrade could quietly falsify. Leave the panel off, as it ships, and
there are none.

**Turning it on gives you a second copy of personal data, and account deletion does not reach it.**
The panel keeps its own tables — `admin_event_log`, a row per action with the admin's address and
user agent, and `admin_audit_log`, which for every create, update and delete stores the row's JSON
state *before* and *after*. Edit a diver through the panel and their email address is now in that
audit row as well as on the `user` row. One setting gates both tables, `CRUD_ADMIN_TRACK_EVENTS`,
and it defaults to on — so enabling the panel enables these unless you say otherwise. They live
wherever `CRUD_ADMIN_DB_URL` points, which the compose file points at the app's own Postgres, so a
`pg_dump` carries them too.

The [account purge](#account-deletion) deliberately leaves them alone. Those tables have no foreign
key to `user` and a different lifecycle: they are a record of what *an operator* did, which is the
one thing an audit log is for, and a purge that quietly rewrote it would be an audit log worth
nothing.

That makes them yours to manage, and nothing manages them for you — `crudadmin` has a retention
helper but nothing in this app calls it, so both tables grow for as long as the panel is enabled. If
you turn it on, prune them yourself on whatever schedule matches what you tell your users:

```bash
docker compose exec -T db psql -U opendiving -d opendiving \
  -c "DELETE FROM admin_audit_log WHERE timestamp < now() - interval '90 days';" \
  -c "DELETE FROM admin_event_log WHERE timestamp < now() - interval '90 days';"
```

Audit rows carry the id of the event they belong to, but not as a foreign key — nothing stops you
deleting the events and leaving the audit rows pointing at nothing, so keep the two windows the
same. And when you serve an erasure request for someone whose row you once edited by hand, remember
this copy. Leave the panel off, as it ships, and none of this exists.

## OpenDiving Commons

[OpenDiving Commons](https://github.com/opendiving/opendiving-commons) is an open pool of real dive
sites, and the API image carries it. There is nothing to set up and no outbound call: the API brings
the records into the database as it starts, every signed-in account can use them, and a diver's
notes and tags on one stay that diver's.

**Your copy is read-only, and the image is what refreshes it.** A release carries the records as they
stood when it was cut, so upgrading is how new sites and corrections arrive
([upgrade.md](upgrade.md)). A Commons record cannot be changed from the app, and an edit made through
the [admin panel](#the-admin-panel) is overwritten the next time the API starts. A diver's own site
is left alone; where one shares an OpenStreetMap or Wikidata entry with a Commons record, its page
offers to replace it with that record, and nothing moves until the diver accepts.

**Proposing happens on the project's instance.** New sites and corrections go in at
<https://opendiving.app>, which is invite-only, where a reviewer accepts them; they reach your copy
in a later release. An install of yours has no proposal routes, no review queue and no controls for
either, and nothing leaves it for the Commons.

## Third-party calls

Nothing here phones home. What the app can be told to contact:

- **From the browser**: the basemap, for the maps it draws itself. Nothing else, in any
  configuration — profile pictures, portraits and species photographs included. A diver's profile
  picture and portrait are stored by your own instance and served by your own API, and so is the
  Commons photograph on a species: the server fetches it and stores it, so no visitor's browser
  ever contacts Wikimedia. (Gravatar used to be an option here, disclosing a hash of every signed-in
  user's email address and their IP to Automattic on every page. It is gone, along with its
  `GRAVATAR_ENABLED` variable.)

  **The visitor's position is asked for in one place**, the finder's *Use my location*, and only
  when it is pressed; the page header lets only the app's own pages ask. The answer moves the map
  and goes nowhere by itself: what reaches this server is the map's centre, which every finder
  search carries in its URL rounded to two decimals, about a kilometre — so it is in whatever
  request log your proxy keeps. The iOS app asks the phone the first time its finder opens, and
  sends that position the same way.

  **The basemap** is fetched wherever a page draws a map in the browser, and each request carries
  the `z/x/y` of the area shown, along with what a browser sends to any site, the languages it is
  set to among them. Unconfigured, that is the MapLibre vector pair the web image
  ships — its tiles, its label glyphs and a low-zoom raster underlay, all from
  `tiles.openfreemap.org`. The browser draws a map in the Sites section, the dive site finder, as soon
  as it opens; in the dive form's *Find a dive site*, the same finder, once the diver opens it; on
  the form to add or edit a dive site and the form to add or edit a trip, both as soon as they open;
  and on the form to add or edit a contact only once the visitor asks it to show one — and nowhere
  else. Whoever serves the
  basemap therefore sees a visitor's IP address, roughly where they dive and the languages their
  browser is set to — not their account, their dive log, or the name of anything on the map.

  **The cards' and page heads' maps are not among them.** The cards that list dives and trips, and
  the heads of a dive's, a trip's and a dive site's own page, are drawn by this stack
  when the [map renderer](#the-map-renderer) is on, and show no map when it is off, so in neither
  case does a visitor's browser fetch the basemap for them. With it on, the basemap's provider sees
  your server and the regions drawn instead, once per tile rather than once per view — see *From the
  server* below.

  **Removing the third party takes one variable.** Every one of those maps draws through MapLibre,
  and so do the iOS app's, so a single setting reaches all of them: `MAP_STYLE_URL` for a vector style you serve, or
  `MAP_TILE_URL` for a raster tile server you run. The two are alternatives rather than layers — a
  style set alongside the raster group leaves it inert — so there is no second fetch to close off
  separately. The shipped default contacts one host, `tiles.openfreemap.org`, and pointing either
  variable at something you serve is what stops anything leaving your machine.

  The raster group is a whole-map mode, not a second renderer: MapLibre wraps a `{z}/{x}/{y}`
  template into a minimal style and draws it the way it draws a vector one. It stays as the escape
  hatch — for a tile server you already run, or a keyed provider you prefer.

  **If that provider wants a key, the key goes to the visitor.** The browser's maps are drawn
  client-side, so `MAP_TILE_API_KEY` is served to every browser that loads a page with a map on it,
  exactly as the tile URL is, and with the map renderer on it reaches the iOS app inside the style
  — there is no arrangement in which it stays on your server, and none is
  coming, because those tiles are fetched by the browser and not by this stack. Every keyed provider
  offers a domain restriction for precisely this; set one, so a key lifted from your page is refused
  everywhere else. With the map renderer on, the key leaves your server as well, for the cards' and
  page heads' maps, and it carries your domain in `Origin` and `Referer` exactly as a browser on one
  of your pages does — so a key restricted that way keeps working for both. The iOS app is
  the exception: it sends neither header, so a provider that checks them refuses it, and its maps
  draw the credit with no tiles under it — the finder's list and search still work, and a form's pin
  can still be placed by tap, coordinates, search or "Use my location". The remedy is yours: a key
  the provider does not restrict by domain, which gives up the restriction this section recommends,
  or maps that stay that way. No setting turns the app's maps off alone. Issue the key for tiles alone, too: a key that also buys geocoding or routing on the same account is a bill someone else
  can run up. This is the ordinary way keyed web maps work rather than a shortcoming of the escape
  hatch — but it is the sort of thing that is obvious only after it has happened to you.

  **Google sign-in is deliberately absent from that bullet**, and it is worth saying why rather than
  leaving it to be inferred. With `GOOGLE_CLIENT_ID` set, no page this app serves fetches, embeds or
  executes anything of Google's — the front page and the sign-in page included, and whether or not
  the visitor ever intends to use the button. What pressing "Continue with Google" does is send the
  browser *away*: a top-level navigation to `accounts.google.com`, where the visitor is on Google's
  own site under Google's own policy. Whatever Google stores at that point, it stores as the site
  being visited rather than as a third party embedded in yours. The URL necessarily tells Google
  which instance sent them — it has to carry your client id and the address to come back to — and
  that, together with whatever they choose to do on Google's own page, is the whole of it. They
  return carrying a one-time code, and turning that code into a sign-in happens between your API and
  Google, never in the browser.

  Leaving `GOOGLE_CLIENT_ID` unset still removes the option entirely: no button, and the bundled
  privacy page has no Google section at all.

- **From the iOS app**: the basemap, for its maps — the Sites tab, the dive form's *Find a Dive
  Site* and its forms — when the
  [map renderer](#the-map-renderer) is on. The app asks this server for the style, naming the
  phone's language, then fetches that style's tiles and glyphs from the basemap's host itself, as a
  browser does, so those do not pass through this stack; on the basemap the image ships, only the
  sprite comes from `SITE_URL`. Whoever serves the basemap
  therefore sees the phone's IP address, the part of the world on screen, the app's name and version
  and the iOS version in the `User-Agent`, and the language settings in `Accept-Language` — not the
  account, the dive log, or the name of anything on the map. The requests carry neither `Origin` nor
  `Referer`, which matters to a keyed provider: see *If that provider wants a key* above. The app's
  cards and page heads are this server's tiles, so the provider does not see the phone for those.

- **From the server**: the basemap, for the cards' and page heads' maps, when the
  [map renderer](#the-map-renderer) is on; two geocoders and the two species *name registers*, WoRMS and
  Wikidata, on cache misses only. A pinned coordinate goes to Nominatim (`GEOCODER_URL`) to be
  named; a place typed into the dive site finder's search, or the dive site or trip form's, goes to Photon
  (`GEOCODER_SEARCH_URL`), by default the public instance komoot runs; a typed species search goes to the registers. Nothing
  identifying the diver goes with any of them, the finder's map centre included, and the source IP
  is your server's. Each is
  configurable, and geocoding can be switched off outright — place search alone, or pins and search
  together.

  **The renderer fetches what one tile needs, once**: the basemap's own tile and label glyphs for
  that square — on the default basemap one vector tile, and at zoom 6 and below up to four tiles of
  the low-zoom underlay — from whichever basemap the `MAP_*` variables name, the same one the
  browser draws. Its requests carry a `User-Agent` naming OpenDiving's map renderer, and `Origin` and
  `Referer` naming `SITE_URL`, the headers your own pages send for the same tiles. A tile is drawn
  the first time any card or page head shows its square, and stored for every account, so the
  provider sees a region again only when it is first shown in another label language, when your
  basemap or a new release changes how it is drawn, or after 30 days in which nobody here was shown
  it.

  **Wikimedia Commons is one more, and it is not one of those registers.** It is never asked
  anything a diver typed — it receives a file title derived from an AphiaID, or one an admin chose,
  and answers with a photograph's credit metadata and the URL of one scaled copy, which the server
  then fetches. That is not a cache miss on a search: it happens when a species is first resolved
  into your catalog, again for species already in it whenever an operator runs the photo backfill
  script in the API container by hand — nothing runs it on a schedule — and when an admin works on a
  species' photo on the *Species* screen: a re-fetch asks again, a pin fetches the file the admin
  named, and the photo picker lists the files in the species' Commons category and fetches a small
  preview of each. `COMMONS_API_URL` points the metadata calls at a mirror, and `""` switches
  species photos off entirely. A photograph narrower than 500 px is refused rather than stored soft,
  so a species whose chosen file is that narrow has no photo; only an admin's pin stores one,
  unscaled. The image bytes themselves are only ever fetched from `thumb.wikimedia.org` or
  `upload.wikimedia.org` — one Commons reply names both, a scaled copy on the first and, for a file
  narrower than the copy asked for, the unscaled original on the second. Those two hostnames are
  hard-coded and have no setting, because that is an SSRF fence and a fence with an environment
  variable in front of it is not a fence.

  **Every one of those species calls carries the same `User-Agent`**, `SPECIES_USER_AGENT` — the two
  registers, the Commons metadata calls and the byte fetches. It says what the software is, never
  who the diver is, and both upstreams want it: WoRMS asks to be told who is calling, and
  [Wikimedia's policy](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy)
  requires one. **Unlike `COMMONS_API_URL` it is not an off switch.** An empty value was measured
  answering 403 on the Commons metadata call and on the image bytes alike, and the registers carry
  the same header, so blanking it costs species search and resolution rather than only the photos —
  and nothing warns you, because the API starts and serves normally either way. The default
  identifies this project rather than your deployment, which is the reason to change it on a public
  instance: every install that leaves it alone is one indistinguishable client to Wikimedia, so one
  operator's runaway backfill is attributed to everybody running OpenDiving.

  **The geocoders carry their own, `GEOCODER_USER_AGENT`, sent to both, and Nominatim is stricter
  about it.** [Its usage policy](https://operations.osmfoundation.org/policies/nominatim/) asks for
  "a valid HTTP Referer or User-Agent identifying the application", and adds that a stock one set by
  an HTTP library will not do — which is enforced rather than advisory. Measured against the public
  instance on 2026-08-31: an empty agent **403**, a plain `python-httpx/0.27` **403**, the shipped
  default 200. That middle result is what makes this header unlike the species one — non-empty is
  not enough. A 403 from Nominatim costs naming the spot behind a pin: reverse returns "we could not
  ask", and a dropped pin gets no suggested name. Photon's maintainers give a generic agent no
  guarantees, and its public instance signals a block with an HTML 404, a 504 or a refused
  connection rather than a 429 — so a proxy that rewrites outbound headers, or a generic string
  pasted in, can cost the place search in the finder and on the dive site and trip forms as well. Either way the API
  stays healthy, and the trace is a warning in its log naming the provider and what it answered —
  `The nominatim geocoder answered /reverse with 403` — or, for a refused connection, the exception
  class. The reason to change it on a public instance is the one above, and it is **not** that the
  default is generic: it is not, and Nominatim accepts it. It identifies the project rather than
  your deployment, so every OpenDiving instance arrives at both providers under the same name —
  leaving their operators no way to tell one from another, or to reach the one giving them trouble.
  Put your own project and contact address in.

  **Open-Meteo is one more, and only once `DIVE_CONDITIONS_PROVIDER` names it.** As it ships nothing
  leaves for this. Set it to `open-meteo` and a cron in the worker asks Open-Meteo's Historical
  Weather and Marine APIs about dives whose air temperature, weather or waves are empty: what goes
  out is the dive's position rounded to two decimals — about a kilometre — and the dates around it,
  at most three days and never an hour, on a cache miss, so every dive in one square on one day shares
  an answer. Nothing identifying the diver goes with it — no account, no dive, no name — and the
  source IP is your server's. If you publish a privacy policy, this belongs in it. The requests carry
  the project's `User-Agent`, which has no setting of its own. The free API is for non-commercial use
  only — [Open-Meteo's terms](https://open-meteo.com/en/terms) count private or non-profit sites and
  apps without subscriptions or advertising — and its data is CC BY 4.0, so the dive page shows
  Open-Meteo's attribution beside what it filled. A commercial operator subscribes and sets
  `DIVE_CONDITIONS_OPEN_METEO_API_KEY`, on a plan that covers the Historical Weather API: that moves
  every call to Open-Meteo's `customer-` hosts, and a plan without the archive is refused there and
  fills nothing.

  **The seafloor explorer's bathymetry services**, when a signed-in diver opens the 3D view of a
  spot the cache can't answer. The API probes NOAA's coastal elevation models, EMODnet, GMRT and
  ETOPO 2022, and KHOA when `KHOA_API_KEY` is set, then fetches the depth grid from the finest one
  covering the spot; for KHOA's soundings it also fetches OpenFreeMap's coastline tiles and AWS
  Terrain Tiles' land heights. What goes out is the point, rounded to about 10 m: as a box about
  2 km a side, or as the `z/x/y` of the tiles covering it. Nothing identifying the diver goes with it, the source IP is your
  server's, and the answer is cached for a week for every account. None of these has a setting to
  point it elsewhere.

  Two more, only if you have set `GOOGLE_CLIENT_ID`. **Every Google sign-in redeems its authorization
  code** at `oauth2.googleapis.com`, over TLS from your server, using `GOOGLE_CLIENT_SECRET` — that
  call is on the sign-in path itself, so an instance whose outbound traffic is filtered has to allow
  it. And **when somebody signs up with Google**, the API fetches their Google profile picture once
  — from `googleusercontent.com`, at account creation and never again — and stores it with everything
  else you host. That one is best-effort; a failure just means the account starts with initials.

There is no analytics of any kind. The web app's Content-Security-Policy narrows where anything
could be *sent*: `connect-src` names this instance's own origin, its API and the host serving the
basemap, and nothing else, in every configuration, so a `fetch`, an `XMLHttpRequest`, a WebSocket or
a `navigator.sendBeacon` aimed at a third-party collector is refused by the browser until the policy
itself is widened. (The basemap sits in that directive in both of its modes rather than in
`img-src`, because MapLibre decodes even raster tile bytes from an `ArrayBuffer` it fetched. So
`img-src` names no third-party host at all, in any configuration — `'self'`, `data:`, `blob:` and
this instance's own API, and nothing else.)
Google sign-in needs no exception to that and is granted none — a navigation is not a fetch, and
CSP's fetch directives govern what a page loads rather than where the visitor goes next. Take that
for what it is and no more — it constrains destinations, not dependencies. Script bundled into the
web app loads under `'strict-dynamic'`, because your own build already vouches for it, and anything
reporting back to this instance's own origin passes as ordinary first-party traffic.

**Add any of it and the consent duty is yours.** The `/privacy` page is part of the web image, and
it describes exactly the posture above: nothing here is advertising or analytics, which is the whole
reason it offers no cookie banner. Add a tracker, an analytics script, an advertising tag or any new
third-party subresource to your copy and two things happen together — that page stops being true of
your instance, and asking for consent *before* the storage or access happens becomes an obligation
on you, along with building the flow that collects it. Under ePrivacy that duty falls on whoever
operates the service, which is you and not this project, and nothing in the image can discharge it
on your behalf.
