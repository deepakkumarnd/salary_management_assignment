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

`bin/setup` installs the gems, creates and migrates the development database, loads the seed data, clears the logs and
temp files, and then starts the app. It is safe to re-run at any time. Useful options:

- `bin/setup --skip-server` sets everything up without starting the server.
- `bin/setup --reset` drops and recreates the database.

### Seed data and first sign-in

The seed (`db/seeds.rb`, run by `bin/setup`, or on its own with `bin/rails db:seed`) creates:

- the 8 supported countries and their currencies;
- the **ACME** organization, with setup left pending;
- the first HR user, `hr@acme.test`.

The password comes from `SEED_HR_PASSWORD` if it is set. Otherwise a random one is generated and **printed once** in
the seed output, so keep it. To choose your own:

```sh
SEED_HR_PASSWORD='choose-a-long-password' bin/rails db:seed
```

Re-running the seed is safe: nothing is duplicated, and an existing user keeps their password. To start again, run
`bin/setup --reset`.

The first sign-in opens the **setup wizard**: organization details, operating countries, country allowances, then
departments and job roles. The rest of the app is available once setup is finished.

### Demo data (optional)

To try the app at scale, fill ACME with 10,000 employees and several years of history:

```sh
bin/rails demo:populate ORG="ACME" EMPLOYEES=10000
```

It takes a few seconds and adds:

- a pay structure for every country and job role (if setup was still pending, it first applies standard defaults: all
  8 countries, HRA 40% in India, the suggested departments and roles);
- employees hired over the last six years, with a yearly appraisal every 1 April, some promotions, a few backdated
  adjustments entered this month and raises scheduled for next April;
- about 12% leavers, 1% serving notice and a few records ended as "recorded in error";
- deductions for last month and this month, and payroll export log entries for the last six months, so this month's
  export shows arrears.

The data is the same on every run. Running it again adds more employees, continuing the employee ID sequence.

## Running the app

```sh
bin/dev
```

This starts the Rails server and the Tailwind watcher (see `Procfile.dev`). Open http://localhost:3000.

If you run `bin/rails server` on its own, first build the CSS once with `bin/rails tailwindcss:build`.

Emails such as password resets aren't sent in development. Read them at http://localhost:3000/letter_opener.

## Running the tests

The suite uses RSpec with FactoryBot, Faker, shoulda-matchers and Capybara.

```sh
bundle exec rspec               # all specs
bundle exec rspec spec/system   # browser flows only (headless Chrome); the Tailwind CSS is rebuilt first
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
| `app/models/` | ActiveRecord models; `Current` holds the signed-in user and organization |
| `app/services/` | Logic spanning models: `PayCalculator`, `Insights::`, `Payroll::`, `SalaryRevisions::`, `Employment::`, `Onboarding::` |
| `app/queries/` | `EmployeeSearch`: search, filters and sorting for the employee list |
| `app/assets/tailwind/` | `application.css` (Tailwind entry point, daisyUI plugin and themes) and the vendored `daisyui.mjs` |
| `app/javascript/controllers/` | Stimulus controllers |
| `lib/demo/`, `lib/tasks/demo.rake` | The `demo:populate` task |
| `spec/` | RSpec specs. Shared config lives in `spec/support/` and factories in `spec/factories/`. |
| `config/ci.rb` | Steps run by `bin/ci` |

## Updating daisyUI

```sh
curl -sLo app/assets/tailwind/daisyui.mjs https://github.com/saadeghi/daisyui/releases/latest/download/daisyui.mjs
```
