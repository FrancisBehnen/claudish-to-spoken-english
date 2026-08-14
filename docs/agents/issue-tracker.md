# Issue tracker: GitHub

Issues for this repo live as GitHub issues in **`FrancisBehnen/claudish-to-spoken-english`** — Francis' fork. Use the `gh` CLI for all operations.

`gh` infers the repo from `git remote -v`, but this clone has **two** remotes: `origin` (the fork, canonical for issues) and `upstream` (`gvzdv/claudish-to-english`). A bare `gh issue ...` here resolves to **upstream**, which is someone else's repo. Always pass `-R FrancisBehnen/claudish-to-spoken-english` explicitly.

Issues were disabled on the fork by default (GitHub disables them on new forks) and were enabled on 2026-08-14 via `gh api --method PATCH repos/FrancisBehnen/claudish-to-spoken-english -F has_issues=true`.

## Conventions

- **Create an issue**: `gh issue create -R <repo> --title "..." --body-file <file>`. Use a file or heredoc for multi-line bodies — never nested `echo` quoting.
- **Read an issue**: `gh issue view <number> -R <repo> --comments`
- **List issues**: `gh issue list -R <repo> --state open --json number,title,labels,assignees`
- **Comment**: `gh issue comment <number> -R <repo> --body "..."`
- **Label**: `gh issue edit <number> -R <repo> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> -R <repo> --comment "..."`

## When a skill says "publish to the issue tracker"

Create a GitHub issue on the fork.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> -R FrancisBehnen/claudish-to-spoken-english --comments`.

## Pull requests as a triage surface

**PRs as a request surface: no.** Contributions arrive upstream, not here.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: an issue labelled `wayfinder:map`, holding the Destination / Notes / Decisions-so-far / Not-yet-specified / Out-of-scope body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue attached to the map as a GitHub **sub-issue**, plus `Part of #<map>` at the top of the body as a human-readable backstop. Labels: `wayfinder:<type>` (`research` / `prototype` / `grilling` / `task`).

  ```bash
  CHILD_ID=$(gh api repos/$R/issues/<child> --jq .id)
  gh api --method POST repos/$R/issues/<map>/sub_issues -F sub_issue_id=$CHILD_ID
  ```

- **Blocking**: GitHub's **native issue dependencies** — the canonical, UI-visible representation, which is why they're worth the extra API call.

  ```bash
  BLOCKER_ID=$(gh api repos/$R/issues/<blocker> --jq .id)
  gh api --method POST repos/$R/issues/<blocked>/dependencies/blocked_by -F issue_id=$BLOCKER_ID
  ```

  The payload takes the blocker's numeric **database id** (`.id`), _not_ its `#number` and not its `node_id` — passing the wrong one fails confusingly.

- **Frontier query**: open children with no open blockers and no assignee. `issue_dependencies_summary.blocked_by` counts **open** blockers only, so it is the live gate:

  ```bash
  for n in $(gh issue list -R $R --state open --json number --jq '.[].number'); do
    gh api repos/$R/issues/$n \
      --jq 'select((.issue_dependencies_summary.blocked_by // 0) == 0 and .assignee == null)
            | "#\(.number)  \(.title)"'
  done
  ```

  First in map order wins.

- **Claim**: `gh issue edit <n> -R $R --add-assignee @me` — the session's first write, before any work.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.

### Labels

Created 2026-08-14: `wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task`.
