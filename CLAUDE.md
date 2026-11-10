# OpenDiving workspace: main session

**Read this first.** Claude Code also loads this file in sessions started inside `opendiving-api/` or
`opendiving-web/`, because they sit under this folder. If your working directory is inside one of the app
repos, you are a worker pane, not the main session: ignore everything below and follow that repo's own
`CLAUDE.md` and `AGENTS.md`. Never open panes or delegate from a worker.

## Layout

This repo is the install bundle and the docs. The three app repos are cloned inside it, each its own git
repository (not a submodule), git-ignored here:

| Folder               | What it is                              | Who works in it                    |
| -------------------- | --------------------------------------- | ---------------------------------- |
| `.` (this repo)      | install bundle, docs, `run.sh`          | the main session                   |
| `opendiving-api`     | FastAPI + arq worker                    | the `api` pane                     |
| `opendiving-web`     | Next.js                                 | the `web` pane                     |
| `opendiving-commons` | dive-site pool, built into the API      | the main session                   |

The local dev stack is shared and `./run.sh` owns it (see [RUN.md](RUN.md)): API on :8000, web on :3000.

## Your role

You are the main session. When the user asks for work in `opendiving-api` or `opendiving-web`, delegate
it to that repo's pane, wait for the pane's report, and report back. Don't edit those two repos yourself.
Work in this repo and in `opendiving-commons` directly.

A task that spans both apps is split per repo. When the API contract changes, send the API half first,
then give the web pane the resulting contract (endpoints, schemas, status codes) from the API's report.
Independent halves can run in both panes at once.

## The panes

Two panes in this Rex session, labelled `api` and `web`, each running its own Claude Code session in its
repo. Find them by label:

```sh
rex block ls -s "$REX_SESSION" --json | jq -r '.blocks[] | select(.label=="api" or .label=="web") | "\(.label) \(.block_id)"'
```

If one is missing, open it as a shell and start Claude in it, so the pane survives Claude exiting:

```sh
# api goes below your own pane, web to the right of api.
api=$(rex split -s "$REX_SESSION" -b "$REX_BLOCK" --split=below --ratio 45 --label api --focus=false -c "$PWD/opendiving-api" --json | jq -r '.block_ids[0]')
rex send -s "$REX_SESSION" -b "$api" 'claude --dangerously-skip-permissions' && rex send-key -s "$REX_SESSION" -b "$api" enter
web=$(rex split -s "$REX_SESSION" -b "$api" --split=right --label web --focus=false -c "$PWD/opendiving-web" --json | jq -r '.block_ids[0]')
rex send -s "$REX_SESSION" -b "$web" 'claude --dangerously-skip-permissions' && rex send-key -s "$REX_SESSION" -b "$web" enter
```

If only one is missing, anchor it on the one that is still there.

Never close, restart or interrupt a pane unless the user asks, and never send input to your own pane.

## Delegating a task

1. **Check the pane is idle.** `rex capture -s "$REX_SESSION" -b "$pane" --trim --unwrap | tail -n 20`. A
   spinner line with a running timer (`✢ Imagining… (25s · …)`) means it is busy: wait, or ask the user.
2. **Write the task to a brief file, and send only a short pointer to it.** A long `rex send` arrives with its
   start cut off, so anything over a sentence or two goes in the brief. The pane has not seen this
   conversation: the brief carries the task, the context and constraints it needs, and ends with _"When you
   finish, or if you need a decision from me, write your report or question to `<report file>` and stop."_
   Both live in `.logs/agents/` (git-ignored), named `<pane>-<YYYYmmdd-HHMMSS>.task.md` and
   `<pane>-<YYYYmmdd-HHMMSS>.md`, always as absolute paths:

   ```sh
   rex send -s "$REX_SESSION" -b "$pane" "New task from the main session: read $brief and do what it says." &&
     rex send-key -s "$REX_SESSION" -b "$pane" enter
   ```
3. **Wait in the background**, so the user can keep talking to you:
   `until [ -s "$f" ]; do sleep 5; done; cat "$f"` with `run_in_background`. If it runs long, capture the
   pane to see whether it is stuck or asking something on screen.
4. **Check before relaying.** Confirm the claims that matter cheaply (`git -C <repo> status -sb`,
   `git log -1`, `gh pr view`) and say which pane did what. Relay a question from a pane to the user as a
   question; don't answer it on their behalf.

## Rules to pass along

- **Commit, push, open or merge a PR only when the user asked for it**, and say so in the message.
  Otherwise tell the pane to leave its changes uncommitted.
- Use the running dev stack; don't start a second API or `next dev`. Ask the main session (via the report)
  if a restart is needed, and restart with `./run.sh restart`.
- `next dev` rewrites `opendiving-web/AGENTS.md` on every start: `git checkout AGENTS.md` before committing.
- Web needs Node 24 (`.nvmrc`), but a new shell gets the system Node 20, where vitest won't start. Switch
  with nvm in the same command, since each command starts a fresh shell:
  `source ~/.nvm/nvm.sh && nvm use >/dev/null && <npm/pnpm/npx command>`.
- Remotes: `origin` is the fork (`sam0910/*`), `upstream` is `opendiving/*`. PRs go to the fork's `main`
  and are squash-merged.
