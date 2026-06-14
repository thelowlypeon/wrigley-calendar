# Wrigley Calendar

Generates a single `.ics` feed of everything happening at Wrigley Field:

- Chicago Cubs home games (via the MLB StatsAPI, filtered to the Wrigley
  venue)
- Concerts and other special events (via the Ticketmaster Discovery API)

## Calendar URL

Subscribe to this in any calendar app:

```
https://raw.githubusercontent.com/thelowlypeon/wrigley-calendar/main/wrigley.ics
```

## How it's regenerated

A GitHub Actions workflow (`.github/workflows/build-calendar.yml`) runs:

- **Daily** at ~6am Chicago time (`11:00 UTC` cron schedule)
- On every push to `main` (runs the test suite only — it does not rebuild
  the calendar)
- On manual trigger from the Actions tab (`workflow_dispatch`)

On the scheduled/manual runs, it executes `ruby generate.rb`, which fetches
fresh data from both sources, builds `wrigley.ics`, and commits + pushes it
back to `main` if anything changed.

Because the generated file's `DTSTAMP` is always set to the current time,
the file changes (and the bot commits) on essentially every scheduled run —
so the repo never goes 60 days without activity, which is what would
otherwise cause GitHub to automatically disable the scheduled workflow.

### ⚠️ Do not require pull requests on `main`

The build job commits the regenerated `wrigley.ics` directly to `main` using
`github-actions[bot]`. If branch protection on `main` requires pull requests
(or status checks) for all changes, the bot's push will be rejected and the
calendar will stop updating. Keep direct pushes to `main` allowed for this
bot (or the `github-actions[bot]` actor specifically) when configuring branch
protection.

## Making changes

1. Create a branch and open a pull request as normal — the `test` job runs
   `bundle exec rspec` on every push and PR.
2. Once merged to `main`, the next scheduled (or manually triggered) run will
   pick up your code changes and regenerate the calendar with them.

## Running specs locally

```sh
bundle install
bundle exec rspec
```

## Running the generator locally

```sh
TM_API_KEY=your_ticketmaster_api_key ruby generate.rb
```

- `TM_API_KEY` is required to fetch concerts/special events from
  Ticketmaster. If unset, that source is skipped (with a warning) and only
  Cubs games are included.
- Output defaults to `wrigley.ics` in the repo root; override with
  `OUTPUT_PATH`.
- The generator refuses to write an empty calendar (exits non-zero) if both
  sources return zero events, so a bad run won't overwrite a good
  `wrigley.ics`.
