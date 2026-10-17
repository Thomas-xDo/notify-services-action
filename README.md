# notify-services-action

Composite GitHub Action wrapper around [`notify-services`](https://github.com/Thomas-xDo/notify-services)'s
`POST /v1/notify` — lets any workflow report a result without hand-writing
`curl`.

## Setup

1. In the [notify-services dashboard](https://notify.thomas-labs.com), create
   an App for your repo and add at least one destination (Slack/Discord/
   Telegram/webhook). Copy the App's API key (`nsvc_...`, shown once).
2. In your repo: **Settings → Secrets and variables → Actions**, add a secret
   (e.g. `NOTIFY_API_KEY`) with that value.

## Usage

### The standard CI message (use this)

Give the action what ran and the results of the jobs before it; it builds
the title, the body and the level itself, so every repository reports in the
same shape:

```yaml
notify:
  needs: [test, build-and-push, deploy]
  if: always() && github.event_name != 'pull_request'
  runs-on: ubuntu-latest
  steps:
    - uses: Thomas-xDo/notify-services-action@main
      continue-on-error: true
      with:
        api-key: ${{ secrets.NOTIFY_API_KEY }}
        service: my-project-api
        event: deploy
        jobs: ${{ toJSON(needs) }}
        details: |
          Image: ${{ needs.build-and-push.outputs.tag }}
```

What arrives on Telegram (the first line is added by notify-services):

```
MY-PROJECT-API · ERROR
Deploy thất bại

Repo: Thomas-xDo/my-project
Commit: 41a9bf8f181a fix: retry khi DB chậm
Người: dominhhieu
Các bước: test ✓ · build-and-push ✓ · deploy ✗
Image: 41a9bf8f181a
Run: https://github.com/Thomas-xDo/my-project/actions/runs/123
```

- The result comes from `jobs`: one failed job makes it `thất bại` (level
  `error`), else one cancelled job makes it `bị hủy` (`warning`), else
  `thành công` (`info`). Skipped jobs don't count. Job marks: `✓` success,
  `✗` failure, `⊘` cancelled, `–` skipped.
- A workflow with no `needs` (a single job) passes `status:
  ${{ job.status }}` instead of `jobs`.
- `target` adds where it went to the title (`Deploy thành công · dev`).
- The commit line uses the first line of the pushed commit's message (or the
  pull request's title), cut to 72 characters.

### A message of your own

Set `message` and it is sent as it is, with `title` and `level` (default
`info`). This is how the action worked before, and it still works the same:

```yaml
- uses: Thomas-xDo/notify-services-action@main
  with:
    api-key: ${{ secrets.NOTIFY_API_KEY }}
    service: my-repo
    level: error
    message: "Nightly import found 3 broken rows"
```

## Inputs

| Input | Required | Default | Notes |
| --- | --- | --- | --- |
| `api-key` | yes | — | The App's `nsvc_...` key, from a secret |
| `service` | yes | — | Free-form label, shown in the notify-services dashboard and on top of the Telegram message |
| `message` | no | `""` | Body sent as it is. Empty: the standard CI message is built |
| `event` | no | `deploy` | Standard message: `deploy`, `build`, `test`, `backup`, `release`, `rollback` or any word |
| `jobs` | no | `""` | Standard message: `${{ toJSON(needs) }}` |
| `status` | no | `""` | Standard message: `success` \| `failure` \| `cancelled`; overrides the result from `jobs` |
| `target` | no | `""` | Standard message: added to the title |
| `details` | no | `""` | Standard message: extra lines, put before the run link |
| `title` | no | `""` | Notification title; with the standard message it replaces the built one |
| `level` | no | `""` | `info` \| `warning` \| `error` \| `critical`. Empty: `info`, or the level that fits the result |
| `to` | no | `""` (all enabled destinations) | Comma-separated destination types to target, e.g. `telegram` or `telegram,slack` |
| `api-url` | no | `https://notify-api.thomas-labs.com` | Override for testing against another deployment |

Every input reaches `notify.sh` as an environment variable, never pasted
into the script, so a commit message with quotes or `$(...)` is only text.
`NOTIFY_DRY_RUN=1 ./notify.sh` prints the request instead of sending it.

By default the step fails the job if the notification itself fails to send
(`curl -sf`, non-2xx = non-zero exit). Add `continue-on-error: true` on the
step if a broken notification shouldn't fail the whole workflow.
