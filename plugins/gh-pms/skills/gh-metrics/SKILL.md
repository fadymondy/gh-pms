---
name: gh-metrics
description: Project flow analytics — median time-in-status, gate failure rate, throughput, severity mix. Reads per-issue state files + GitHub closed-issue timestamps to surface metrics PMs actually need. Auto-invoke when the user says "metrics", "velocity", "how's our flow", "throughput last month".
---

# gh-metrics

Aggregate the per-issue state-file timestamps and GitHub close-times into the metrics teams ask for during retros and planning.

## When to use

- Retro / planning: "how did we do last sprint", "what's our throughput"
- Investigating bottlenecks: "why are issues piling up in `in-review`"
- Forecasting: "if we keep this velocity, when do we ship the milestone"

## Inputs

```
gh-metrics [--days <n>] [--format text|json] [--milestone <number>]
```

| Flag | Default | Effect |
|---|---|---|
| `--days` | `30` | Lookback window for closed-issue + transition data. |
| `--format` | `text` | `text` for human reading, `json` for piping (one record per issue). |
| `--milestone` | none | Restrict to issues attached to a specific milestone. |

## What it computes

### 1. Time-in-status (median + p90)

For each gate transition, read the per-issue state file (`~/.cache/gh-pms/state/<owner>-<repo>.json`) for `last_transition_at` per status. Compute time-in-status per issue, then aggregate:

```
Status                Median    p90
todo                  3.2 d     14.0 d
in-progress           1.8 d     5.5 d
ready-for-testing     0.4 d     1.2 d
in-testing            0.6 d     2.1 d
ready-for-docs        0.2 d     0.8 d
in-docs               0.5 d     1.4 d
documented            0.3 d     0.9 d
in-review             0.8 d     2.5 d
```

### 2. Gate failure rate

A "gate failure" = a transition that bounced back to a prior status (e.g. `in-review → in-progress` after `Needs Edits`). Read the state file's transition history per issue:

```
Gate 1 (in-progress → ready-for-testing):   passed 12, bounced 1 (8% failure)
Gate 2 (in-testing → ready-for-docs):       passed 11, bounced 0 (0% failure)
Gate 3 (in-docs → documented):              passed 8 (3 auto-skipped for bug/hotfix/testcase)
Gate 4 (documented → in-review):            passed 11, bounced 0 (0% failure)
Gate 5 (in-review → done):                  passed 11, rejected 1 (8% rejection)
```

### 3. Throughput

Count issues closed in the lookback window, optionally weighted by `effort:*`:

```
Throughput (last 30 days)
  Issues closed: 14
  By kind:       8 features, 4 bugs, 2 chores
  By effort:     S:5, M:6, L:2, XL:1
  Story points:  ~52   (S=1, M=3, L=5, XL=8)
  Daily rate:    ~1.7 points/day
```

Issues without an `effort:*` label don't contribute to story-point totals (so missing data doesn't inflate the metric — they show up in raw count only).

### 4. Severity mix

Distribution of severity for issues SHIPPED in the window — reveals whether the team is firefighting or building:

```
Severity mix of closed work (last 30 days)
  Critical: 1   (7%)
  High:     5   (36%)
  Medium:   7   (50%)
  Low:      1   (7%)
```

A high `Critical/High` ratio in successive windows is a smell — surface it for the user.

### 5. Milestone progress + ETA

If `--milestone <number>` is set, also include:

```
Milestone v0.7 — Tier 2 features
  Closed:     4 / 4   (100%)
  Open:       0
  Days open:  3
  ETA:        completed
```

For an in-flight milestone with the throughput above, project an ETA using the daily rate.

## Implementation notes

- `lib/gh-metrics.sh` is the data layer; the skill drives it. The script reads:
  1. Local state files (transitions + timestamps)
  2. `gh issue list --state closed --search "closed:>$DATE"` for closures the local file may have missed
  3. `gh api repos/$REPO/milestones` for milestone progress
- All output is computed at runtime — no metric is cached longer than 5 minutes (analytics need to be fresh)
- Story-point weights (S=1, M=3, L=5, XL=8) are a Fibonacci default; per-repo override goes in `.github/gh-pms.yaml` under `metrics.effort_points`

## Cross-skill contract

- `gh-status` answers "where are we now"; `gh-metrics` answers "how have we been doing"
- The two never conflict: `gh-status` reads current state, `gh-metrics` reads transition history. Run both during retros.

## Notes

- Out of scope: charts / dashboards (text + JSON output is the contract; pipe JSON to your favorite plotter)
- Out of scope: cross-repo aggregation (covered by #14 cross-repo plans once it lands)
- Caveat: state files are local. If multiple developers work on the same issue from different machines, transition history fragments. Until a server-side state store is added, treat metrics as approximate, not authoritative.
