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

```yaml
- name: Notify deploy success
  if: success()
  uses: Thomas-xDo/notify-services-action@main
  with:
    api-key: ${{ secrets.NOTIFY_API_KEY }}
    service: my-repo
    level: info
    message: "Deploy ${{ github.sha }} succeeded"

- name: Notify deploy failure
  if: failure()
  uses: Thomas-xDo/notify-services-action@main
  with:
    api-key: ${{ secrets.NOTIFY_API_KEY }}
    service: my-repo
    level: error
    message: "Deploy ${{ github.sha }} failed"
```

## Inputs

| Input | Required | Default | Notes |
| --- | --- | --- | --- |
| `api-key` | yes | — | The App's `nsvc_...` key, from a secret |
| `service` | yes | — | Free-form label, shown in the notify-services dashboard |
| `message` | yes | — | Notification body |
| `title` | no | `""` | Notification title |
| `level` | no | `info` | `info` \| `warning` \| `error` \| `critical` |
| `api-url` | no | `https://notify-api.thomas-labs.com` | Override for testing against another deployment |

By default the step fails the job if the notification itself fails to send
(`curl -sf`, non-2xx = non-zero exit). Add `continue-on-error: true` on the
step if a broken notification shouldn't fail the whole workflow.
