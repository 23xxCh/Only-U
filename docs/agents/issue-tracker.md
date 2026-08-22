# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues on `23xxCh/Only-U`. Use the `gh` CLI for all operations.

Repo: https://github.com/23xxCh/Only-U

## Conventions

- **Create an issue**: `gh issue create --repo 23xxCh/Only-U --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --repo 23xxCh/Only-U --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --repo 23xxCh/Only-U --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --repo 23xxCh/Only-U --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --repo 23xxCh/Only-U --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --repo 23xxCh/Only-U --comment "..."`

When run inside a clone of this repo, `gh` infers the remote automatically and `--repo` can be omitted.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
