# How to run Salary Management

A step-by-step guide to set up the app on your machine, sign in, load demo data and run the tests. For more detail on
the project itself, see [README.md](README.md).

## 1. Prerequisites

| Tool | Version | Check with |
|---|---|---|
| Ruby | 4.0.6 (pinned in `.ruby-version`) | `ruby -v` |
| SQLite | 3.x | `sqlite3 --version` |
| Google Chrome | any recent | Only needed for the browser (system) specs |

- **Ruby:** install it with a version manager, e.g. `rbenv install 4.0.6` or `mise install ruby@4.0.6`. Bundler comes
  with Ruby.
- **SQLite:** already installed on macOS. On Debian/Ubuntu: `sudo apt install sqlite3 libsqlite3-dev`.
- **Nothing else:** no Node.js, npm or separate Tailwind install. The `tailwindcss-rails` gem ships the Tailwind CLI,
  and daisyUI is vendored in the repository.

## 2. Set up

```sh
git clone <repo-url> salary-management
cd salary-management
SEED_HR_PASSWORD='choose-a-password' bin/setup
```

`bin/setup` installs the gems, creates the database, loads the seed data and starts the app. It's safe to run again at
any time.

The seed creates:

- the 8 supported countries and their currencies;
- the **ACME** organization, with its setup left to do;
- the first HR user, **`hr@acme.test`**, with the password from `SEED_HR_PASSWORD` (6 to 32 characters).

> If you leave out `SEED_HR_PASSWORD`, a random password is generated and **printed once** in the setup output, so copy
> it from there.

## 3. Start the app

`bin/setup` starts it for you. After that, start it with:

```sh
bin/dev
```

This runs the Rails server and the Tailwind watcher together. Open **http://localhost:3000** and sign in as
`hr@acme.test`.

To use another port: `PORT=4000 bin/dev`.

## 4. First sign-in: set up the organization

The first sign-in opens a short **setup wizard**:

1. **Organization:** name, employee ID prefix (e.g. `ACME`) and standard hours per week.
2. **Countries** the organization operates in.
3. **Country allowances** (optional), e.g. HRA 40% in India.
4. **Departments and job roles**, pre-filled with suggestions you can edit.
5. **Finish.** The app opens on **Pay policy**, where each job role needs a pay structure in each country before
   employees can be added.

To skip the wizard and get a realistic data set instead, load the demo data (next step) **before** signing in.

## 5. Load demo data (optional)

```sh
bin/rails demo:populate ORG="ACME" EMPLOYEES=10000
```

In about 5 seconds this adds 10,000 employees with six years of salary history, leavers, scheduled raises, deductions
and a payroll export log. If ACME's setup is still pending, it first completes it with standard defaults: all 8
countries, HRA 40% in India, and the suggested departments and roles.

The data is the same on every run. Running it again adds more employees.

## 6. Things to try

| Where | What to try |
|---|---|
| **Employees** | Search by name, email or employee ID; filter by country, department, job role and status; sort columns; open an employee. |
| Employee page | Record a salary revision (backdated or scheduled), correct or void one, end employment and undo it, add deductions. |
| **Add employee** | Pick a country and role: the starting basic is pre-filled and the pay breakdown updates as you type. |
| **Employees → Import** | Upload a CSV of new employees (download the template first). It's imported in the background: watch the progress, then see which rows were skipped and why, and download them to fix. |
| **Pay policy** | Change a country allowance or a role's pay structure and see gross and total target pay change. |
| **Insights** | Pay ranges, averages, medians and total cost to company per country; drill down by job role and department. |
| **Deductions** | Enter unpaid leave and other deductions for last month, this month or next month, row by row. |
| **Payroll export** | Pick a country and month, check the summary and warnings, then download the CSV. |

Emails, such as password resets, aren't sent in development. Read them at **http://localhost:3000/letter_opener**.

## 7. Run the tests

```sh
bundle exec rspec               # the whole suite (about 500 specs, under a minute)
bundle exec rspec spec/system   # browser flows only, in headless Chrome
bin/ci                          # everything CI runs: RuboCop, security audits, Brakeman, Tailwind build, RSpec
```

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| Lost the HR password | Start over with a password you choose: `SEED_HR_PASSWORD='new-password' bin/setup --reset`. If you don't set one, use the **last** password printed: the reset seeds twice. Or use "Forgot your password?" on the sign-in page and open the email at `/letter_opener`. |
| Want a clean database | `bin/setup --reset` (this deletes all data in the development database). |
| Pages have no styling | The CSS hasn't been built. Start the app with `bin/dev`, or run `bin/rails tailwindcss:build` once if you use `bin/rails server` on its own. |
| Port 3000 is already in use | `PORT=4000 bin/dev` |
| Signed out unexpectedly | Sessions end after 30 minutes of inactivity, and an account locks for an hour after 5 wrong passwords. |
| System specs fail to start | Install Google Chrome; the specs drive it headless. |
| `ruby: command not found` or wrong version | Install Ruby 4.0.6 with your version manager and open a new shell in the project folder. |
