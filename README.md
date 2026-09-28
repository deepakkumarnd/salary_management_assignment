# Salary Management

A Rails app where HR managers track salaries for their organization's employees. It is a single server-rendered
Rails 8.1 app using Hotwire (Turbo + Stimulus), styled with Tailwind CSS v4 and daisyUI v5, and backed by SQLite.
It needs no Node.js or npm.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Ruby | 4.0.6 | Pinned in `.ruby-version`. Install it with rbenv, asdf or mise. |
| Bundler | bundled with Ruby | |
| SQLite | 3.x | Already installed on macOS. On Debian/Ubuntu: `apt install sqlite3 libsqlite3-dev`. |
| Google Chrome | any recent | Needed only for system specs, which run in headless Chrome. |

You don't need to install Tailwind separately: the `tailwindcss-rails` gem ships the standalone Tailwind CLI, and
daisyUI is vendored in `app/assets/tailwind/daisyui.mjs`.

## Setup

```sh
git clone <repo-url> salary-management
cd salary-management
bin/setup
```

`bin/setup` installs the gems, creates and migrates the development database, clears the logs and temp files, and
then starts the app. It is safe to re-run at any time. Useful options:

- `bin/setup --skip-server` sets everything up without starting the server.
- `bin/setup --reset` drops and recreates the database.

## Running the app

```sh
bin/dev
```

This starts the Rails server and the Tailwind watcher (see `Procfile.dev`). Open http://localhost:3000.

If you run `bin/rails server` on its own, first build the CSS once with `bin/rails tailwindcss:build`.

## Running the tests

The suite uses RSpec with FactoryBot, Faker, shoulda-matchers and Capybara.

```sh
bin/rails tailwindcss:build     # system specs need the compiled CSS
bundle exec rspec               # all specs
bundle exec rspec spec/system   # browser flows only (headless Chrome)
bundle exec rspec --only-failures
```

Specs run in random order. To reproduce a failing run exactly, re-run it with the same seed:
`bundle exec rspec --seed 1234`. Faker is seeded from the same value.

## Checks before pushing

```sh
bin/ci
```

`bin/ci` runs the same steps as GitHub Actions (`.github/workflows/ci.yml`):

- RuboCop
- `bundler-audit` and `importmap audit`
- Brakeman
- Tailwind build
- RSpec

## Project layout

| Path | Contents |
|---|---|
| `app/assets/tailwind/` | `application.css` (Tailwind entry point, daisyUI plugin and themes) and the vendored `daisyui.mjs` |
| `app/javascript/controllers/` | Stimulus controllers |
| `spec/` | RSpec specs. Shared config lives in `spec/support/` and factories in `spec/factories/`. |
| `config/ci.rb` | Steps run by `bin/ci` |

## Updating daisyUI

```sh
curl -sLo app/assets/tailwind/daisyui.mjs https://github.com/saadeghi/daisyui/releases/latest/download/daisyui.mjs
```
