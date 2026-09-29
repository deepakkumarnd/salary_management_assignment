# Salary Management — Design (v1)

Companion to [REQUIREMENTS.md](REQUIREMENTS.md). That document says *what* v1 does and why. This one
says *how*.

## 1. Architecture

A single **Rails 8.1 monolith** that renders HTML on the server and uses Hotwire for interactivity. It has one codebase,
one language and one deploy. Nothing separates frontend from backend: no JSON API layer, no client-side state, and no
duplicated validation.

```
Browser ── HTML over HTTP (Turbo Drive / Frames / Streams) ──► Rails app ──► SQLite
             ▲ small Stimulus controllers for live UI                │
             └──────────── server-rendered views ◄───────────────────┘
          Devise auth → tenant (Current.organization) → setup gate → controllers → models / services
```

| Concern | Choice | Why |
|---|---|---|
| Framework | Rails 8.1 on Ruby 4.0 | Conventions cover forms, validation, routing, migrations and testing, which is most of this app. |
| Authentication | **Devise** | Mature email + password auth: secure password hashing (bcrypt), reset-password emails, lockout and session timeout come as modules instead of hand-written code. |
| UI | ERB views + **Hotwire** (Turbo, Stimulus) | Server-rendered forms and tables. Turbo Frames refresh filters, paging and form errors without full reloads. Stimulus handles the few live bits (pay breakdown preview, basic-pay pre-fill). No SPA build. |
| Styling | **Tailwind CSS v4** through the `tailwindcss-rails` gem | Utility classes keep styling next to the markup in ERB partials. The gem uses Tailwind's standalone CLI, so there is still no Node toolchain. `bin/dev` runs the watcher. |
| Components | **daisyUI v5** (free, MIT) | Ready-made component classes on top of Tailwind: `btn`, `table`, `input`, `select`, `modal`, `alert`, `badge`, `stats`, `tabs`, `steps`, `timeline`, `join` (pagination). It is **pure CSS with no JavaScript**, so it doesn't compete with Turbo/Stimulus. It loads as a single vendored `daisyui.mjs` plugin file, which needs no npm. Built-in light/dark themes. |
| JS delivery | Importmap (Rails default) | No bundler or `node_modules`. |
| Database | SQLite 3 (production-grade in Rails 8) | Zero setup, fast at 10k rows. Rails 8 opens SQLite write transactions as `IMMEDIATE`, which serialises writers (relied on in §5). Swapping to Postgres means changing `database.yml`. |
| CSV | Ruby's `csv` library (a bundled gem since Ruby 3.4, so listed in the `Gemfile`) | Standard, streaming-capable CSV writing with correct quoting. |
| Pagination | `pagy` gem | Small, fast, no model patching. |
| Email (dev) | `letter_opener_web` | Password-reset and invite emails can be read at `/letter_opener` locally, with no mail server. |
| Tests | **RSpec** (`rspec-rails`) with **FactoryBot** (`factory_bot_rails`) and **Faker**, plus `shoulda-matchers` and Capybara for system specs | Readable, behaviour-style specs. Factories build exactly the objects each test needs, with realistic Faker data, instead of shared fixtures. |

**Code organisation**

| Location | Contents |
|---|---|
| `app/models` | ActiveRecord models: associations, validations, scopes. `Current` (`ActiveSupport::CurrentAttributes`) holds `user` and `organization` for the request. |
| `app/services` | Plain Ruby objects for logic that spans models: `PayCalculator`, `SalaryStats`, `Insights::CountryReport`, `AllowanceNameGuard`, `Onboarding::Wizard`, `Team::InviteUser`, `SalaryRevisions::Record` / `Void` / `Correct`, `Employment::End` / `UndoEnd`, `Payroll::Roster`, `Payroll::MonthlyPay`, `Payroll::Run`, `Payroll::CsvExport`. |
| `app/queries` | `EmployeeSearch`: search, filters and sorting for the employee list (§6.1). |
| `app/controllers` | Thin RESTful controllers. All app controllers inherit from `AuthenticatedController` (§3). It also maps `ActiveRecord::StaleObjectError` and `RecordNotDestroyed` to user-facing messages. |
| `app/controllers/onboarding` | The setup wizard, one controller per step. |
| `app/views` | ERB + Turbo Frames, styled with Tailwind utilities + daisyUI classes. Devise views are generated and restyled. |
| `app/views/components` | Small partials that wrap repeated daisyUI patterns: form field with error, money cell, status badge, stat card, conflict alert, pagination. Styling decisions live in one place. |
| `app/assets/tailwind` | `application.css` (`@import "tailwindcss"; @plugin "./daisyui.mjs";`, theme config) and the vendored `daisyui.mjs`. |
| `app/javascript/controllers` | Stimulus: `search_form` (debounced auto-submit), `basic_pay_prefill`, `pay_preview`, `dialog`. |
| `lib/tasks/demo.rake` | `demo:populate`, which adds pay structures, 10k employees, salary history and leavers to an organization (§9). |

## 2. Data model

### 2.1 Entities

```
Organization ──< User (HR users, Devise)
     │
     ├──< OrganizationCountry >── Country (global reference data)
     ├──< Department
     ├──< JobRole
     ├──< CountryAllowance >── Country
     ├──< PayStructure >── Country, JobRole
     │        └──< PayStructureAllowance
     ├──< Employee >── Department
     │        ├── PayStructure (via country_id + job_role_id)
     │        └──< SalaryRevision            (basic pay over time)
     ├──< PayrollDeduction >── Employee       (unpaid leave / other, per month)
     └──< PayrollExport >── Country, User     (export log)
```

| Model | Scope | Purpose |
|---|---|---|
| `Organization` | tenant root | Name, employee ID prefix and counter, standard weekly hours, `setup_completed_at`. |
| `User` | organization | An HR user (Devise). Belongs to exactly one organization. |
| `Country` | **global** | The supported countries and their currency. Shared reference data, seeded. |
| `OrganizationCountry` | organization | The countries this organization operates in (chosen during setup). |
| `JobRole`, `Department` | organization | The organization's own catalogues. |
| `CountryAllowance` | organization | Allowance for **every employee of this organization in a country**, e.g. HRA 40% in India. |
| `PayStructure` | organization | One per **country + role**: default basic pay (pre-fills new hires), target variable pay % and overtime rate. `accepts_nested_attributes_for :allowances`. |
| `PayStructureAllowance` | via structure | Allowance for that country + role only, on top of the country's. |
| `Employee` | organization | A person's employment: identity, country (fixed), role, department, hire date and, once they leave, last working day and exit reason. **Holds no pay amount itself**; pay lives in `SalaryRevision`. |
| `SalaryRevision` | organization | One basic-pay value with its **effective date**, reason, notes and author. Append-only; mistakes are voided, never edited or deleted. |
| `PayrollDeduction` | organization | A deduction for one employee in one pay month: **unpaid leave** (days) or **other** (amount + description). Editable monthly input. |
| `PayrollExport` | organization | A log entry for each downloaded payroll CSV: country, month, row count, checksum, who and when. |

### 2.2 Schema (migrations → `db/schema.rb`)

```ruby
create_table :organizations do |t|
  t.string   :name,                    null: false
  t.string   :employee_code_prefix,    null: false                # e.g. "ACME" → ACME-00042
  t.integer  :next_employee_number,    null: false, default: 1    # per-org sequence for employee IDs
  t.integer  :standard_hours_per_week, null: false, default: 40   # overtime hourly rate (§4)
  t.datetime :setup_completed_at                                 # nil → setup wizard is shown
  t.timestamps
  t.check_constraint "standard_hours_per_week BETWEEN 1 AND 80"
  t.check_constraint "employee_code_prefix GLOB '[A-Z]*' AND length(employee_code_prefix) BETWEEN 2 AND 6"
end

create_table :users do |t|                                       # Devise
  t.references :organization, null: false, foreign_key: { on_delete: :restrict }
  t.string   :full_name,          null: false
  t.string   :email,              null: false                     # unique among active accounts (index below)
  t.string   :encrypted_password, null: false
  t.string   :reset_password_token, index: { unique: true }
  t.datetime :reset_password_sent_at
  t.integer  :failed_attempts,    null: false, default: 0         # :lockable
  t.string   :unlock_token,       index: { unique: true }
  t.datetime :locked_at
  t.datetime :deactivated_at                                     # "removed" by a colleague; can't sign in
  t.references :deactivated_by, foreign_key: { to_table: :users, on_delete: :restrict }
  t.timestamps
  t.index :email, unique: true, where: "deactivated_at IS NULL"  # email free again once deactivated
end

create_table :countries do |t|                                   # global, no organization_id
  t.string :name,          null: false, index: { unique: true }
  t.string :currency_code, null: false, limit: 3                 # ISO 4217
  t.check_constraint "length(currency_code) = 3"
end

create_table :organization_countries do |t|
  t.references :organization, null: false, foreign_key: { on_delete: :cascade }
  t.references :country,      null: false, foreign_key: { on_delete: :restrict }
  t.timestamps
  t.index [:organization_id, :country_id], unique: true
end

create_table :job_roles do |t|
  t.references :organization, null: false, foreign_key: { on_delete: :cascade }
  t.string :name, null: false, collation: "NOCASE"
  t.timestamps
  t.index [:organization_id, :name], unique: true
end

create_table :departments do |t|
  t.references :organization, null: false, foreign_key: { on_delete: :cascade }
  t.string :name, null: false, collation: "NOCASE"
  t.timestamps
  t.index [:organization_id, :name], unique: true
end

create_table :country_allowances do |t|
  t.references :organization, null: false, foreign_key: { on_delete: :cascade }
  t.references :country,      null: false, foreign_key: { on_delete: :restrict }
  t.string  :name,         null: false, collation: "NOCASE"
  t.integer :percent_bp,   null: false                           # basis points: 4000 = 40.00%
  t.integer :lock_version, null: false, default: 0               # optimistic locking (Rails built-in)
  t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
  t.timestamps
  t.index [:organization_id, :country_id, :name], unique: true
  t.check_constraint "percent_bp BETWEEN 1 AND 20000"
end

create_table :pay_structures do |t|
  t.references :organization, null: false, foreign_key: { on_delete: :cascade }
  t.references :country,      null: false, index: false, foreign_key: { on_delete: :restrict }
  t.references :job_role,     null: false, foreign_key: { on_delete: :restrict }
  t.integer :default_basic_pay,       null: false                # annual, local currency, whole units
  t.integer :variable_pay_percent_bp, null: false, default: 0    # target variable, % of gross: 1000 = 10%
  t.integer :overtime_percent_bp,     null: false                # 15000 = 150%
  t.integer :lock_version,            null: false, default: 0
  t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
  t.timestamps
  t.index [:country_id, :job_role_id], unique: true              # job_role is org-specific, so unique per org; FK target
  t.check_constraint "default_basic_pay > 0"
  t.check_constraint "variable_pay_percent_bp BETWEEN 0 AND 20000"
  t.check_constraint "overtime_percent_bp BETWEEN 0 AND 40000"
end

create_table :pay_structure_allowances do |t|
  t.references :pay_structure, null: false, foreign_key: { on_delete: :cascade }
  t.string  :name,       null: false, collation: "NOCASE"
  t.integer :percent_bp, null: false
  t.timestamps
  t.index [:pay_structure_id, :name], unique: true
  t.check_constraint "percent_bp BETWEEN 1 AND 20000"
end

create_table :employees do |t|
  t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
  t.string  :employee_code,       null: false                    # readable ID, e.g. ACME-00042; immutable
  t.string  :full_name,           null: false
  t.string  :email,               null: false                    # normalised to lower case
  t.integer :country_id,          null: false                    # immutable after create (§2.3)
  t.integer :job_role_id,         null: false, index: true
  t.references :department,       null: false, foreign_key: { on_delete: :restrict }
  t.string  :employment_type,     null: false
  t.date    :hire_date,           null: false
  t.date    :employment_end_date                                 # last working day; nil → no exit recorded
  t.string  :exit_reason
  t.text    :exit_notes
  t.integer :lock_version,        null: false, default: 0
  t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
  t.timestamps
  t.index [:organization_id, :employee_code], unique: true       # lookups by URL + uniqueness
  t.index [:organization_id, :email], unique: true,              # unique among employees without an exit;
          where: "employment_end_date IS NULL"                   # a rehire may reuse their email
  t.index [:organization_id, :country_id, :department_id]        # list filters (country, department, role)
  t.index [:organization_id, :department_id]
  t.index [:organization_id, :job_role_id]
  t.index [:organization_id, :full_name]
  t.index [:organization_id, :employment_end_date]               # status filter, "employed during" queries
  t.index [:country_id, :job_role_id]                            # composite FK + country filter
  t.check_constraint "employment_type IN ('full_time','part_time','contractor')"
  t.check_constraint "(employment_end_date IS NULL) = (exit_reason IS NULL)"
  t.check_constraint "employment_end_date IS NULL OR employment_end_date >= hire_date"
  t.check_constraint "exit_reason IS NULL OR exit_reason IN ('resignation','termination','retirement'," \
                     "'end_of_contract','internal_transfer','recorded_in_error','other')"
end

# Composite foreign key: every employee must have a pay structure for their country + role.
add_foreign_key :employees, :pay_structures,
                column: [:country_id, :job_role_id], primary_key: [:country_id, :job_role_id],
                on_delete: :restrict

create_table :salary_revisions do |t|
  t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
  t.references :employee,     null: false, index: false, foreign_key: { on_delete: :restrict }
  t.date    :effective_on, null: false                           # applies from the start of this day
  t.integer :basic_pay,    null: false                           # annual, employee's local currency
  t.string  :reason,       null: false
  t.text    :notes
  t.references :created_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
  t.datetime :voided_at                                          # nil → in force
  t.references :voided_by, foreign_key: { to_table: :users, on_delete: :restrict }
  t.string  :void_reason
  t.timestamps
  t.index [:employee_id, :effective_on], unique: true, where: "voided_at IS NULL"   # one per day; serves "as of"
  t.index [:employee_id], unique: true, name: "one_hire_revision_per_employee",
          where: "reason = 'hire' AND voided_at IS NULL"
  t.index [:organization_id, :created_at]                        # "entered this month" (backdated detection)
  t.check_constraint "basic_pay > 0"
  t.check_constraint "reason IN ('hire','appraisal','promotion','market_adjustment','correction')"
  t.check_constraint "(voided_at IS NULL) = (voided_by_id IS NULL) AND (voided_at IS NULL) = (void_reason IS NULL)"
end

create_table :payroll_deductions do |t|
  t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
  t.references :employee,     null: false, foreign_key: { on_delete: :restrict }
  t.date    :period_start,     null: false                       # first day of the pay month
  t.string  :kind,             null: false                       # 'unpaid_leave' | 'other'
  t.integer :unpaid_half_days                                    # unpaid_leave only: 3 = 1.5 days
  t.integer :amount                                              # other only: whole units, local currency
  t.string  :description                                         # other only
  t.integer :lock_version,     null: false, default: 0
  t.references :created_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
  t.references :updated_by, foreign_key: { to_table: :users, on_delete: :restrict }
  t.timestamps
  t.index [:organization_id, :period_start]                      # month page + export
  t.index [:employee_id, :period_start], unique: true, where: "kind = 'unpaid_leave'"   # one leave entry per month
  t.check_constraint "period_start = date(period_start, 'start of month')"
  t.check_constraint "kind IN ('unpaid_leave','other')"
  t.check_constraint "(kind = 'unpaid_leave' AND unpaid_half_days > 0 AND amount IS NULL AND description IS NULL)" \
                     " OR (kind = 'other' AND amount > 0 AND description IS NOT NULL AND unpaid_half_days IS NULL)"
end

create_table :payroll_exports do |t|
  t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
  t.references :country,      null: false, foreign_key: { on_delete: :restrict }
  t.date    :period_start, null: false                           # first day of the pay month
  t.integer :row_count,    null: false
  t.string  :sha256,       null: false                           # checksum of the file as downloaded
  t.references :exported_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
  t.datetime :created_at, null: false
  t.index [:organization_id, :created_at]
end
```

**Models (key declarations)**

```ruby
class Organization < ApplicationRecord
  has_many :users,                  dependent: :restrict_with_error
  has_many :organization_countries, dependent: :destroy
  has_many :countries, through: :organization_countries
  has_many :departments, :job_roles, :country_allowances, :pay_structures, :employees,
           :salary_revisions, :payroll_exports
  def setup_completed? = setup_completed_at.present?
end

class User < ApplicationRecord
  devise :database_authenticatable, :recoverable,
         :lockable, :timeoutable                                   # no :registerable (no public sign-up);
                                                                   # no :rememberable (would bypass the timeout);
                                                                   # no :validatable, whose email check is global
  belongs_to :organization
  scope :active, -> { where(deactivated_at: nil) }
  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :email, presence: true, format: URI::MailTo::EMAIL_REGEXP,
                    uniqueness: { conditions: -> { active } }, if: :active?
  validates :password, length: { within: 6..32 }, if: :password_required?

  def active? = deactivated_at.nil?
  def active_for_authentication? = super && active?               # deactivated → can't sign in
  def inactive_message = active? ? super : :deactivated
  def self.find_for_authentication(conditions) = active.find_by(conditions)   # sign-in + password reset look up
  def self.find_first_by_auth_conditions(conditions, opts = {}) = active.find_by(conditions.merge(opts))
end

class Employee < ApplicationRecord
  EXIT_REASONS = %w[resignation termination retirement end_of_contract internal_transfer recorded_in_error other]

  belongs_to :organization
  belongs_to :country
  belongs_to :job_role
  belongs_to :department
  belongs_to :updated_by, class_name: "User", optional: true
  belongs_to :pay_structure, foreign_key: [:country_id, :job_role_id],
                             primary_key: [:country_id, :job_role_id]
  has_many   :salary_revisions, dependent: :restrict_with_error   # employees are never deleted anyway

  enum :employment_type, { full_time: "full_time", part_time: "part_time", contractor: "contractor" },
       validate: true
  normalizes :email, with: ->(e) { e.strip.downcase }
  attr_readonly :employee_code, :country_id                        # assigned once, never change
  attribute :initial_basic_pay, :integer                           # create only → becomes the hire revision
  before_validation :assign_employee_code, :build_hire_revision, on: :create
  def to_param = employee_code                                     # /employees/ACME-00042

  # Employment status, always derived from dates (never stored)
  scope :employed_on,     ->(date)     { where(hire_date: ..date).where("employment_end_date IS NULL OR employment_end_date >= ?", date) }
  scope :employed_during, ->(from, to) { where(hire_date: ..to).where("employment_end_date IS NULL OR employment_end_date >= ?", from) }
  scope :countable,       ->           { where("exit_reason IS NOT 'recorded_in_error'") }  # insights + exports
  scope :with_basic_pay_as_of, ->(date) { select("employees.*", SalaryRevision.basic_pay_as_of_sql(date)) }

  def status(today = Date.current)
    return :active  if employment_end_date.nil?
    employment_end_date >= today ? :leaving : :exited
  end

  validates :full_name, :hire_date, presence: true
  validates :email, presence: true, format: URI::MailTo::EMAIL_REGEXP
  validates :initial_basic_pay, numericality: { only_integer: true, greater_than: 0 }, on: :create
  validates :exit_reason, inclusion: { in: EXIT_REASONS }, allow_nil: true
  validate  :email_unique_among_current_employees, :hire_date_not_in_future,
            :pay_structure_exists, :references_same_organization, :not_exited_when_editing
end

class SalaryRevision < ApplicationRecord
  REASONS = %w[hire appraisal promotion market_adjustment correction]

  belongs_to :organization
  belongs_to :employee
  belongs_to :created_by, class_name: "User"
  belongs_to :voided_by,  class_name: "User", optional: true

  scope :in_force, -> { where(voided_at: nil) }
  before_update { raise ActiveRecord::ReadOnlyRecord if (changed - %w[voided_at voided_by_id void_reason updated_at]).any? }

  def self.basic_pay_as_of_sql(date)                               # correlated subquery, uses the partial unique index
    sanitize_sql_array([<<~SQL, date])
      (SELECT r.basic_pay FROM salary_revisions r
        WHERE r.employee_id = employees.id AND r.voided_at IS NULL AND r.effective_on <= ?
        ORDER BY r.effective_on DESC LIMIT 1) AS basic_pay
    SQL
  end

  validates :effective_on, presence: true
  validates :basic_pay, numericality: { only_integer: true, greater_than: 0 }
  validates :reason, inclusion: { in: REASONS }
  validate  :within_employment, :hire_revision_on_hire_date
end

class PayStructure < ApplicationRecord
  belongs_to :organization
  belongs_to :country
  belongs_to :job_role
  has_many :allowances, class_name: "PayStructureAllowance", dependent: :destroy
  has_many :employees, foreign_key: [:country_id, :job_role_id],
                       primary_key: [:country_id, :job_role_id], dependent: :restrict_with_error
  accepts_nested_attributes_for :allowances, allow_destroy: true
  validate :country_is_operating_country, :references_same_organization
end
```

### 2.3 Design decisions

| Decision | Rationale |
|---|---|
| **`organization_id` on every tenant table, even where it can be derived** | Every tenant query is a simple `WHERE organization_id = ?`, with no join needed to prove ownership. Unique indexes are scoped per organization (employee email, role/department names, allowance names). `PayStructureAllowance` is the one exception: it is only ever reached through its structure. |
| **`Country` is global; `OrganizationCountry` records which ones an organization uses** | Currency is a fact about the country, not a per-tenant setting. Organizations choose their operating countries without copying reference data. |
| **Cross-organization references are rejected by validation** | A `references_same_organization` validation checks that an employee's department and role, a structure's role, and a revision's employee belong to the record's own organization. Controllers only offer records from `Current.organization` anyway, so the validation is defence in depth. |
| **Employees reference `pay_structures` by `(country_id, job_role_id)`** | The database guarantees every employee has a structure for their country and role. Because `job_role_id` is organization-specific, the pair is unique across tenants too. Rails 7.1+ supports composite keys in associations and `add_foreign_key`. *The first migration spec must confirm the composite FK is actually created on SQLite. If it isn't, fall back to model validation plus `dependent: :restrict_with_error`.* |
| **Readable employee ID (`employee_code`) instead of exposing database ids** | HR recognises `ACME-00042`, not `8731`. The code is stored in full, is unique per organization and read-only after creation, and it is the route parameter (`to_param`), so URLs never reveal internal ids or row counts across tenants. |
| **Employee IDs come from a per-organization counter, not `MAX()+1`** | `EmployeeCode.next_for(org)` runs `UPDATE organizations SET next_employee_number = next_employee_number + 1 WHERE id = ? RETURNING next_employee_number - 1` inside the employee's create transaction. It is atomic, so two HR users creating employees at once never get the same number. Numbers are never reused, including for rehires, who get a new record. The number is zero-padded to 5 digits (it grows beyond 99,999 naturally). Changing the prefix in Settings affects **new** employees only. Existing IDs are never rewritten. |
| **Basic pay lives only in `salary_revisions`; there is no `employees.basic_pay` column** | A cached "current basic" would go stale at midnight whenever a **scheduled** revision takes effect, unless a nightly job rewrote it: another moving part, and a source of wrong numbers if it fails. Instead, "basic as of date D" is a correlated subquery that hits the partial unique index `(employee_id, effective_on) WHERE voided_at IS NULL`. For 10k employees that is roughly 10k index seeks, which takes milliseconds in SQLite. On Postgres the same query becomes a `LATERAL` join. |
| **Revisions are append-only; mistakes are voided** | Pay history must explain every past payment. The model refuses updates to anything except the three void columns, and there is no destroy path. *Correct* is a single transaction that voids the wrong revision and records the right one (see §5). Voided rows stay visible (struck through) with who voided them and why. |
| **Exactly one hire revision per employee, on the hire date** | It is created with the employee (from `initial_basic_pay`) in the same transaction, and a partial unique index plus validation enforce it. Changing the hire date *corrects* the hire revision: it voids the old one and records a new one on the new date in the same transaction. The new hire date may not be after any other revision in force. |
| **Status is derived from dates, never stored** | *Active* / *Leaving* / *Exited* change with the calendar (a leaver becomes *Exited* the day after their last working day). A stored status would need a job to keep it correct. The `employed_on` / `employed_during` scopes are the single definition, used by the list, insights and export. |
| **Email is unique among employees without an exit** | A partial unique index `WHERE employment_end_date IS NULL`, mirrored by a model validation. A rehire (new record) can reuse their email once the old record has an exit recorded. |
| **Employees are never deleted** | There is no destroy route. Records created by mistake are ended with reason *recorded in error*, which the `countable` scope excludes from insights and exports. All foreign keys to employees are `restrict`. Because former employees still reference their pay structure, structures, roles and departments used by anyone, ever, can't be deleted. |
| **`country_id` is read-only after create** | Revisions carry no currency of their own; they are in the employee's country's currency. Making the country immutable guarantees that is always true. Transfers become *leave (internal transfer) + new hire*, which is also how separate payrolls per country see it. |
| **Variable pay is a % of gross, set on the pay structure** | Offers and policies usually state variable pay relative to fixed pay ("10% variable"). Basing it on gross means an allowance change flows through to variable pay consistently. It is a single column on `pay_structures`, not a separate table, because v1 has one target per role and no payout records. Upper bound 200% covers sales roles with large commissions. |
| **Monthly pay is computed, never stored** | `Payroll::MonthlyPay` derives it from revisions, employment dates, policy and deductions, so the export always reflects the latest data. The export log (with checksum) records what was actually handed over. |
| **Unpaid leave stored as half-days (integer)** | Exact arithmetic, like basis points; the form accepts "1.5". |
| **No arrears** | A backdated revision changes pay from the month it is first included in; earlier months are not recalculated and nothing is paid or recovered for them. HR settles such differences with the payroll provider outside the app. Arrears are out of scope for now (see requirements). |
| **Payroll exports are generated on demand; only a log is stored** | A stored copy of every file would be another pile of salary data to protect. The `payroll_exports` log records who, when, which country and month, the row count and a **SHA-256 checksum**, so HR can tell whether a re-download differs from what was sent. |
| **User email is unique among *active* accounts** | It is the login identifier, so two accounts that can sign in must never share it. Deactivated accounts keep their row (their name stays on revisions, voids, deductions and exports) but release the email through the partial unique index `WHERE deactivated_at IS NULL`. The same person can then get a new account, e.g. in another organization. Devise lookups for sign-in and password reset are scoped to active accounts. Devise's `:validatable` is replaced by explicit validations because its uniqueness check is global. |
| **Deactivation is separate from Devise's `locked_at`** | `locked_at` means "too many failed attempts" and unlocks after an hour. `deactivated_at` means "removed from the team" and is permanent until a colleague reactivates the account. Keeping them apart stops a timed unlock from reviving a removed colleague. |
| **Allowance amounts, gross, variable and total pay are never stored** | Derived by `PayCalculator` (§4) from basic (as of a date) and the current policy percentages. Changing a percentage reaches every affected employee immediately. *Known limitation (requirements):* policy percentages are not dated, so figures for past months use today's percentages. |
| **Percentages stored as integer basis points; money as integer whole units** | Exact integer arithmetic. The forms accept "40.00" (%) and convert. Currency comes from `countries` and is formatted with `number_to_currency(unit: …)`. |
| **Names use `NOCASE` collation plus case-insensitive model validation** | Stops near-duplicates such as "Engineering" vs "engineering", or "HRA" vs "hra". |
| **`on_delete: :restrict` plus `dependent: :restrict_with_error`** | You cannot delete a structure, role, department or operating country that is still used. The model error becomes a flash message, and the DB constraint is the backstop. Deleting an organization (not exposed in the UI) cascades to its data. |
| **Cross-level allowance-name rule in `AllowanceNameGuard`** | "A role cannot redefine a country allowance, and vice versa" spans two tables, so no unique index can express it. Both models validate through the guard, scoped to the organization. Because Rails 8 opens SQLite transactions as `IMMEDIATE`, the check and the write cannot interleave with another writer. |
| **`lock_version` + `updated_by` on `employees`, `pay_structures`, `country_allowances`** | Rails' built-in optimistic locking (§5). `updated_by` (set from `Current.user`) lets the conflict notice say *who* changed the record. Revisions don't need `lock_version`: they are inserts, and their conflicts are caught by unique indexes and conditional updates (§5). |
| **"Today" = `Date.current` in UTC; times shown in the viewer's time zone** | The app runs in UTC (`config.time_zone = "UTC"`): stored times, "today", status and the default export month all use one definition. Views render timestamps with `local_time`, a `<time datetime>` in UTC that the `local-time` Stimulus controller rewrites in the browser's own time zone (UTC text is the fallback without JavaScript). Per-organization time zones are out of scope. |
| **No free-text search index** | `LIKE '%term%'` over 10k rows takes milliseconds. SQLite FTS5 or Postgres `pg_trgm` is the upgrade path. |

## 3. Authentication, tenancy and setup

### 3.1 Authentication (Devise)

| Module | Setting |
|---|---|
| `database_authenticatable` | Email + password. Password length 6 to 32 characters. bcrypt cost from Devise defaults. Devise's `validatable` is **not** used; explicit validations make email unique among *active* accounts only (§2.3, §3.5). |
| `recoverable` | Forgot / reset password by email. Also used to let invited colleagues set their first password (§3.5). Reset tokens expire after 6 hours. |
| `lockable` | Locks after **5** failed attempts. Unlocks automatically after 1 hour (`unlock_strategy: :time`). |
| `timeoutable` | Signs out after **30 minutes** of inactivity (this is salary data). |
| *not* `rememberable` | No "remember me". Devise skips the inactivity timeout while a remember-me cookie is valid, so a 2-week cookie would keep a session to salary data open for 2 weeks. Every session therefore ends after 30 minutes of inactivity, with no exceptions. |
| *not* `registerable` | No public sign-up. Users come from the seed script or are added by colleagues. |

**Only HR users can sign in.** `User` (people who operate the app) and `Employee` (people whose pay is managed) are
separate tables with no link between them:
- `employees` has no password or token columns, and Devise is mounted only for `User`.
- The only ways a `User` is created are the seed script and *Settings → Team* (`Team::InviteUser`). Nothing in the
  app turns an employee record into a login, and an employee's email being on file grants nothing.
- An HR person who is also on the payroll has two independent records: a `User` to sign in, and an `Employee` for
  their pay.

A request spec asserts that an employee's email cannot sign in (no matching `User`) and that no route creates a `User`
outside Team.

`config.paranoid = true`, so login and reset screens never reveal whether an email exists. Devise views are generated
(`rails g devise:views`) and restyled with daisyUI.

### 3.2 Request pipeline

Every application controller inherits from `AuthenticatedController`:

```ruby
class AuthenticatedController < ApplicationController
  before_action :authenticate_user!                 # Devise: unauthenticated → /users/sign_in
  before_action :set_current_tenant                 # Current.user / Current.organization
  before_action :require_organization_setup         # setup incomplete → onboarding wizard

  private

  def set_current_tenant
    Current.user = current_user
    Current.organization = current_user.organization
  end

  def require_organization_setup
    redirect_to onboarding_path unless Current.organization.setup_completed?
  end
end
```

The onboarding controllers `skip_before_action :require_organization_setup`. After sign-in, Devise's
`after_sign_in_path_for` sends users to the wizard if setup is incomplete, and to Employees otherwise.

### 3.3 Tenant isolation rule

**Every lookup goes through `Current.organization`:**

```ruby
@employee = Current.organization.employees.find_by!(employee_code: params[:id])   # another org's code → 404
@departments = Current.organization.departments.order(:name)
```

- `default_scope` and tenancy gems (e.g. `acts_as_tenant`) are deliberately not used. Scoping stays explicit and
  visible in every controller, and it can't be bypassed accidentally by `unscoped`.
- Background work and rake tasks take an explicit organization argument.
- A shared request-spec example (`it_behaves_like "tenant isolated"`) is run against every resource. It proves that
  another organization's record returns 404 for show, edit, update and nested actions (revisions, end of employment),
  and never appears in index, insights or a payroll export.

### 3.4 Organization setup wizard

The first screen after login until `setup_completed_at` is set. It is a linear wizard (daisyUI `steps`). Each step saves
on submit, so the wizard can be resumed after sign-out, and several HR users can work through it.

| Step | Captures | Rules |
|---|---|---|
| 1. Organization | Name, employee ID prefix (suggested from the name, e.g. "Acme Corp" → `ACME`), standard hours per week (default 40) | Required. Prefix is 2–6 uppercase letters. |
| 2. Countries | Operating countries (multi-select from the global list) | At least one. |
| 3. Country allowances | Named % allowances per selected country, e.g. HRA 40% in India | Optional. Same validation as in §2. |
| 4. Departments & job roles | Editable suggested lists (e.g. Engineering, Sales, …; Software Engineer, Accountant, …) | At least one of each. |
| Finish | Sets `setup_completed_at`, redirects to **Pay policy** with a prompt to create the first pay structures | Pay structures come after setup because they need countries and roles to exist. The employee form explains that an employee needs a structure for their country + role. |

`Onboarding::Wizard` decides which steps are complete and which one is next, from the data itself rather than a
separate step counter. It is a pure service with its own specs. After setup, the same data can be edited under
**Settings** (organization, countries, allowances, departments, roles). Removing an operating country is blocked while
pay structures or employees use it.

### 3.5 Team

**Settings → Team** lists the organization's HR users. *Add colleague* (name, email) is handled by `Team::InviteUser`:

1. It creates a `User` in `Current.organization` with a random password.
2. It sends Devise's reset-password email, worded as "set your password", so passwords are never emailed or
   chosen by someone else.

Colleagues can be removed, but you can't remove yourself, which guarantees an organization always has at least one HR
user. A removed user's name stays on the revisions, voids, deductions and exports they made (`on_delete: :restrict`), so
removing a user **deactivates** the account (`deactivated_at`, `deactivated_by`) rather than deleting the row:

- A deactivated account **can't sign in or reset its password**, and any open session ends on its next request
  (`active_for_authentication?`).
- It is **excluded** from Team, from every user list and picker, and from anything exported. Payroll exports contain
  employees only; HR accounts never appear in them. Past records still show the name, marked *(former)*.
- Its **email is free again**. *Add colleague* with that email:
  - in the **same organization**, reactivates the old account and sends a new set-password email, so their history
    stays linked;
  - in **another organization**, creates a new account there;
  - if an *active* account anywhere already has the email, returns *"This email is already in use"*, and nothing more,
    so it doesn't reveal which organization.

## 4. Pay calculation

`PayCalculator` is a plain Ruby object and the single source of truth for the employee page, the live form previews,
the list, the insights and the payroll export.

```ruby
PayCalculator.new(basic_pay:, allowances: [{ name:, percent_bp:, source: :country | :role }],
                  variable_pay_percent_bp:, overtime_percent_bp:, standard_hours_per_week:)
  .breakdown  # => { basic:, allowances: [{ name:, source:, percent_bp:, amount: }], gross:,
              #      variable_target:, total_target:, overtime_hourly: }

amount          = (basic_pay * percent_bp + 5_000) / 10_000             # integer round-half-up, per allowance
gross           = basic_pay + allowances.sum(amount)                   # fixed pay
variable_target = (gross * variable_pay_percent_bp + 5_000) / 10_000   # target at 100% performance
total_target    = gross + variable_target
hourly_basic    = basic_pay / (52 * standard_hours_per_week).to_r       # organization setting
overtime_hourly = (hourly_basic * overtime_percent_bp / 10_000).round(2)
```

- `basic_pay` is always **basic as of a date**: today for the employee page, list and insights; the relevant day of
  the pay month for the export (§7). The calculator doesn't know about dates.
- Rounding is applied **per allowance**, then summed, so the breakdown HR sees always adds up to the gross. Variable pay
  is calculated from that rounded gross, so gross + variable always equals the total shown.
- **Insights** need gross and total target pay for up to 10k employees. `Insights::CountryReport` takes
  `employees.employed_on(today).countable.where(country:).with_basic_pay_as_of(today)` and plucks
  `(job_role_id, department_id, basic_pay)`, then loads the allowance percentages in a few queries, groups the rows in
  Ruby, and runs the calculator and `SalaryStats` (min/max/avg/median) over them. This takes milliseconds at this scale
  and avoids a second copy of the rounding rules in SQL.
- **Live preview**: when basic pay, country or role changes in the employee form, or the new basic changes in the
  revision form, the Stimulus `pay_preview` controller requests a server-rendered breakdown partial through a Turbo
  Frame. The calculation never runs in JavaScript.

## 5. Concurrency and write rules

**Optimistic locking (employees, pay structures, country allowances).** Rails provides this through `lock_version`:

1. Edit forms carry `lock_version` as a hidden field (`f.hidden_field :lock_version`).
2. `update` runs `UPDATE … SET …, lock_version = lock_version + 1 WHERE id = ? AND lock_version = ?`, and sets
   `updated_by = Current.user`.
3. If another HR user has saved in between, Rails raises `ActiveRecord::StaleObjectError`. The controller rescues it
   and re-renders the form with **409 Conflict** and the notice *"Priya Nair changed this record at 10:42"*. The form
   shows the **latest saved values** next to the user's own edits, plus the fresh `lock_version`, so the user can
   re-apply the edit knowingly.
4. **Ending and un-ending employment** are updates to the employee, so they carry `lock_version` and conflict the same way.
5. Saving a `PayStructure` with nested allowances happens in one transaction and bumps the structure's `lock_version`,
   so any concurrent edit to the structure or its allowances is detected.

**Salary revisions (append-only).**

| Operation | Service | Rules and conflict handling |
|---|---|---|
| Record | `SalaryRevisions::Record` | The employee must not be *Exited*. `effective_on` must be ≥ hire date and ≤ last working day (if set), and `reason` ≠ `hire`. A second revision in force for the same employee and date hits the partial unique index. It is rescued as a **422** field error, *"A revision already exists for 1 Apr 2026: void or correct it instead"*. The response flags a **backdated** entry (`effective_on` before the current month) and says that earlier months' payroll isn't recalculated. |
| Void | `SalaryRevisions::Void` | Needs a reason. It is a conditional update `WHERE id = ? AND voided_at IS NULL`. **0 rows** means someone else already voided it, which returns **409** with who and when. The hire revision can't be voided on its own, only corrected. |
| Correct | `SalaryRevisions::Correct` | Void + record in **one transaction**. The replacement defaults to the same date and reason. It is used for the hire revision and for any wrong amount or date. |

**End of employment.**

| Operation | Service | Rules |
|---|---|---|
| End | `Employment::End` | Last working day ≥ hire date, a reason is required, and notes are optional. It is **refused while revisions in force are effective after the last working day**; the form lists them with *Void* links. Backdated and future dates are both allowed. |
| Undo | `Employment::UndoEnd` | Clears the three exit columns. It is refused if another current employee now has the same email (e.g. they were already rehired). |

Everything else on an *Exited* employee is read-only (`not_exited_when_editing`). The UI hides the edit actions, and the
model refuses them anyway.

## 6. Routes & screens

RESTful resources, all HTML and all server-rendered.

```ruby
devise_for :users, skip: :registrations
authenticated :user do
  root "employees#index", as: :authenticated_root
end
devise_scope(:user) { root "devise/sessions#new" }

namespace :onboarding do                     # GET /onboarding → current step
  root "steps#show"
  resource :organization, only: %i[edit update]
  resource :countries,    only: %i[edit update]
  resource :allowances,   only: %i[edit update]
  resource :catalogue,    only: %i[edit update]   # departments + job roles
  resource :completion,   only: :create
end

resources :employees, except: :destroy do           # :id is the employee code, e.g. ACME-00042
  resources :salary_revisions, only: %i[index new create] do
    resource :void,       only: %i[new create], controller: "salary_revision_voids"
    resource :correction, only: %i[new create], controller: "salary_revision_corrections"
  end
  resource :employment_end, only: %i[new create destroy]   # destroy = undo exit
end
resources :countries, only: %i[index show] do       # the organization's operating countries → pay policy
  resources :allowances, controller: "country_allowances", except: %i[index show]
end
resources :pay_structures, except: :show do
  get :preview, on: :collection                     # pay breakdown partial for forms (Turbo Frame)
end
resources :insights, only: %i[index show], param: :country_id
resources :payroll_exports, only: %i[index new create]   # new = choose + summary; create = log + download
get "deductions/:month", to: "payroll_deductions#index", as: :month_deductions   # ?country_id=…
resources :payroll_deductions, only: %i[create update destroy]

namespace :settings do
  resource  :organization, only: %i[edit update]
  resource  :countries,    only: %i[edit update]
  resources :job_roles,    only: %i[index create destroy]
  resources :departments,  only: %i[index create destroy]
  resources :users,        only: %i[index new create destroy]   # Team (destroy = lock, §3.5)
end
```

| Screen | Contents |
|---|---|
| **Sign in / forgot password** | Centred daisyUI card. Generic error messages (paranoid mode). |
| **Setup wizard** (`/onboarding`) | `steps` indicator, one form per step (§3.4), Back / Save & continue. |
| **Employees** (`/employees`) | Search box (name, email or employee ID) plus **Country**, **Department**, **Job role** and **Status** filters, see §6.1. Columns: Employee ID, name, email, country, department, role, status, basic, gross (local currency, as of today). Sortable columns (allow-listed), `pagy` pagination, 25 per page, and a result count. Rows link to `/employees/ACME-00042`. |
| **New employee** | Country (operating countries only), role, department, and the other fields from §2, plus **starting basic pay**. Choosing country + role pre-fills it from the structure (`basic_pay_prefill`). The live breakdown labels each allowance *Country* or *Role*. Saving creates the employee and their hire revision. |
| **Employee page** | Header with name, employee ID, status badge and actions (**Record salary revision**, **End employment** / **Undo exit**, **Edit**). **Pay** tab: today's breakdown, plus a notice for any scheduled revision (*"Rises to ₹21,00,000 on 1 Apr 2027"*). **Salary history** tab: every revision newest first (effective date, basic, change vs. previous in amount and %, reason, notes, entered by/at, and *Backdated* / *Scheduled* / *Voided* badges), with *Correct* and *Void* actions. **Employment** tab: hire date, end date, reason and notes. **Deductions** tab: by month, unpaid-leave days and other deductions, with add/edit/delete (also for an exited employee's employed months). |
| **Edit employee** | Name, email, role, department, employment type, hire date. **Not** country (read-only, with a hint about transfers) and **not** pay (pay changes are revisions). |
| **Record salary revision** | Effective date (default today), new annual basic (pre-filled with the current basic), reason, notes. It shows the change vs. the basic in force on that date, and the new gross/total via `pay_preview`. It warns when the entry is backdated or scheduled. |
| **End employment** | Last working day, reason, notes. It shows the resulting status (*Leaving* / *Exited*) and lists any blocking scheduled revisions. |
| **Pay policy** (`/countries/:id`) | For one operating country: its allowances and all of its role pay structures (default basic, role allowances, variable pay %, overtime %), with nested-form create and edit. |
| **Insights** (`/insights`, `/insights/:country_id`) | A country summary table (current headcount, currency, min/max/avg/median of basic, gross and total target, as of today). Drilling down shows role and department tables. |
| **Deductions** (`/deductions/2026-09?country_id=…`) | The month's roster for one country: employee ID, name, days employed, an **unpaid days** input and **other deductions** per row (add/edit inline through Turbo Frames), searchable by name or ID. Totals at the bottom. |
| **Payroll export** (`/payroll_exports`) | Form: country + pay month (default: current month). A **summary** before download (§7.6): headcount, joiners, leavers, pay changes, totals of gross salary, deductions and net salary, and warnings, with links to the affected employees and to the month's Deductions page. **Download CSV**, and a log of recent exports (who, when, country, month, rows, checksum). |
| **Settings** | Organization profile and hours, operating countries, departments, job roles, and Team. |

Validation errors re-render the form with **422** and field-level messages. Conflicts return **409** as in §5.
Records from another organization return **404**. Nothing fails silently.

### 6.1 Employee search & filters

**URL is the state.** `GET /employees?q=priya&country_id=3&department_id=7&job_role_id=12&status=current&sort=full_name&dir=asc&page=2`.
A filtered list can be bookmarked and shared, Back/Forward work, and a request spec can exercise any combination directly.

**Form behaviour.** The search box and the selects sit in one `GET` form that targets the `employees` Turbo Frame
and uses `data-turbo-action="advance"`, so the URL updates. The Stimulus `search_form` controller submits
automatically: on `input` after 300 ms of no typing, and immediately when a select changes. Changing the search or a
filter resets to page 1. Without JavaScript it is still a normal form with a Search button.

**Query object.** `EmployeeSearch` (`app/queries/employee_search.rb`) is the only place listing logic lives:

```ruby
EmployeeSearch.new(Current.organization, params.permit(:q, :country_id, :department_id, :job_role_id, :status, :sort, :dir),
                   today: Date.current).results
# → ActiveRecord::Relation, paginated by pagy in the controller

scope = organization.employees.includes(:country, :department, :job_role).with_basic_pay_as_of(today)
scope = scope.where(country_id: country_id)        if country_id.present?
scope = scope.where(department_id: department_id)  if department_id.present?
scope = scope.where(job_role_id: job_role_id)      if job_role_id.present?    # any combination → AND
scope = STATUSES.fetch(status, STATUSES["current"]).call(scope, today)
if q.present?
  term = "%#{Employee.sanitize_sql_like(q.strip)}%"                           # % and _ matched literally
  scope = scope.where("employees.full_name LIKE :t OR employees.email LIKE :t OR employees.employee_code LIKE :t",
                      t: term)                                                # LIKE is case-insensitive for ASCII in SQLite
end
scope.order(SORTABLE.fetch(sort, "employees.employee_code") => dir == "desc" ? :desc : :asc)
```

| Rule | Detail |
|---|---|
| Search fields | Name, email and employee ID, with partial, case-insensitive matching. `priya`, `nair`, `@acme.com`, `acme-0004` and `00042` all work. Surrounding whitespace is trimmed. |
| Filter options | **Country** lists the organization's operating countries; **Department** and **Job role** list its departments and roles. All three default to "All". Ids that don't belong to the organization match nothing (they are applied inside the org scope), so they never error or leak data. |
| Status filter | `current` (**default**: Active + Leaving) = `employment_end_date IS NULL OR employment_end_date >= today`; `active` = no end date; `leaving` = end date ≥ today; `exited` = end date < today, excluding *recorded in error*; `all` = everything, including *recorded in error*. |
| Combination | Search, country, department, job role and status are ANDed, and each is optional. |
| Sorting | Allow-listed `SORTABLE` columns (employee ID, name, country, department, job role, basic, hire date, last working day). Basic sorts on the `basic_pay` subquery alias. Default is employee ID ascending. Unknown values fall back to the default. |
| Gross pay column | Calculated for the **25 rows on the page only** with `PayCalculator` (allowances preloaded once per page), so it doesn't slow the query. Gross pay is **not sortable** (agreed): sorting by a derived value would mean calculating it for the whole organization on every request. Basic pay is sortable. |
| Performance | The filters use the `(organization_id, country_id, department_id)`, `(organization_id, department_id)`, `(organization_id, job_role_id)` and `(organization_id, employment_end_date)` indexes. The leading-wildcard `LIKE` and the basic-pay subquery touch at most one organization's rows (10k, milliseconds). FTS5 is the upgrade path if that changes. |

**UI building blocks (daisyUI)**

| Need | Component |
|---|---|
| App shell | `navbar` with the organization name + `menu` (Employees, Pay policy, Insights, Payroll export, Settings) and a user `dropdown` (sign out). |
| Auth screens | `card` with `fieldset` / `input`, `alert` for errors. |
| Setup wizard | `steps` for progress, `checkbox` grid for countries, and a repeatable-row `table` for allowances, departments and roles. |
| Employee list | `table table-zebra table-pin-rows`, `input` search with a search icon, four `select` filters (country, department, job role, status), a `badge` per active filter with a ✕ to clear it, and a "Clear all" `btn-ghost`. `join` pagination (a custom `pagy` template). Employee ID and money columns use `font-mono` / `tabular-nums`, and money is right-aligned. Empty state: "No employees match 'priya' in India · Engineering · Software Engineer" with a clear-filters button. |
| Status | `badge badge-success` *Active*, `badge badge-warning` *Leaving (until 30 Sep)*, `badge badge-ghost` *Exited*. |
| Salary history | `timeline timeline-vertical` (or a compact `table` on small screens). Change vs. previous shown as `+₹1,50,000 (+8.0%)`. `badge` for *Backdated* / *Scheduled*. Voided rows are `line-through opacity-60` with the void reason. |
| Forms | `fieldset` / `input` / `select`, with `input-error` + helper text for field errors. `btn btn-primary` for primary actions. `alert alert-info` for backdated/scheduled hints. |
| Pay breakdown | A compact `table`: basic, allowances with `badge` labels *Country* / *Role*, a **gross** subtotal, **target variable pay** (with its %), and a **total target pay** row. |
| Payroll export | Two `stats` rows (people: in file, joiners, leavers, pay changes; money: gross salary, deductions, net salary), `alert alert-warning` for warnings, the download `btn btn-primary`, and a `table` of the export log. |
| Deductions page | `table table-pin-rows` with a small `input` (step 0.5) per row for unpaid days and a `btn-ghost btn-xs` to add other deductions in a row-level Turbo Frame. |
| Confirmation (void, end, undo) | `modal` (native `<dialog>`) opened by the `dialog` Stimulus controller, or Turbo's `data-turbo-confirm` as the fallback. |
| Flash / conflict notice | `alert alert-success`, `alert alert-warning` for a 409 conflict (who changed it, and the latest values), `alert alert-error`. |
| Insights | `stats` cards for the headline numbers (headcount, median basic, median gross, median total target), `table` for role and department breakdowns, and `tabs` to switch between basic, gross and total target. |

**Theme:** daisyUI's built-in `corporate` theme (light) with `business` as dark, following the OS setting. This is set once in
`application.css`, so no per-page colour decisions are needed.

## 7. Monthly pay, deductions and payroll export (CSV)

### 7.1 Who is in the month

`Payroll::Roster`, for country *C* and pay month *M* (`period_start` … `period_end`, *D* = calendar days in *M*):

```ruby
organization.employees.where(country: C).countable.employed_during(period_start, period_end)
```

That includes everyone employed on at least one day of the month: joiners, leavers and people serving notice.
*Recorded in error* records are never included. Each row's **employed range** is
`max(hire_date, period_start) .. min(last_working_day, period_end)`.

Everything the month needs is loaded in a handful of queries for the whole roster: revisions, deductions for *M*,
allowances and pay structures. It is grouped in Ruby, with no N+1 queries, so a
10k-row country takes a few seconds.

### 7.2 Monthly pay (`Payroll::MonthlyPay`)

1. **Segments.** Split the employed range at every revision in force whose `effective_on` falls inside it. Each segment
   has one basic in force and a day count *d*.
2. **Components.** For basic and for each allowance *c*:
   `monthly_c = round_half_up( Σ_segments annual_c(segment basic) × d / (12 × D) )`, using `PayCalculator` for
   `annual_c` and `Rational` throughout, so there is no float drift. Rounding happens once per component.
3. **Monthly gross** = Σ rounded components, so the file's components always add up to its gross.
4. **Unpaid leave** = `round_half_up( gross_annual(as-of) / 12 / D × days )`, where *as-of* is the last employed day in
   the month. Days ≤ days employed is enforced when the deduction is entered.
5. **Other deductions** = Σ amounts for the month.
6. **Net salary** (before tax) = monthly gross − unpaid leave − other deductions. A negative net is allowed in the file
   but is **flagged** in the summary.

Worked example: a raise from ₹12,00,000 to ₹13,20,000 effective 16 Sep (*D* = 30).
Basic = 12,00,000 × 15/360 + 13,20,000 × 15/360 = 50,000 + 55,000 = **₹1,05,000**. Allowances are prorated the same way.

Variable pay is **not** part of monthly pay, and overtime pay is not computed (no hours are recorded).

### 7.3 Backdated revisions (no arrears)

Arrears are **not supported** for now. A revision backdated to an earlier month changes pay only from the month it is
first included in: the month's pay splits at effective dates *within* that month (§7.2), and earlier months are never
recalculated, so nothing is paid or recovered for them. The employee's salary history marks the revision *Backdated*,
and recording one says that earlier months' payroll isn't recalculated. HR settles such differences with the payroll
provider outside the app.

### 7.4 Deductions

| Rule | Detail |
|---|---|
| Kinds | **Unpaid leave**: days in half-day steps (stored as `unpaid_half_days`), one entry per employee per month. **Other**: amount + description, as many as needed. |
| Month | Must be a month in which the employee was employed (any day). |
| Open months | Deductions can be added, edited or deleted only for **last month, the current month and next month**, so HR can make late adjustments and enter known ones early. Older and later months are read-only (the model refuses changes; the UI shows them as text). |
| Exited employees | Deductions **can** be added for a leaver's employed months even after they have exited, as long as the month is open. This is the one exception to "exited is read-only", because final-month recoveries are often entered late. |
| Editing | Deductions are monthly inputs, not history. Within the open months they can be edited or deleted with `lock_version` (409 on conflict), and they record `created_by` / `updated_by`. A change made after a month was exported (usually last month) shows up only if that month is exported again; the summary warns that the data changed and the new checksum makes the difference visible. |
| Entry points | Employee page → **Deductions** tab (by month). **Deductions** page for a country + month: a table of the roster with an unpaid-days input per row and "add other deduction" per row, so a month's leave can be entered in one sitting. |

### 7.5 CSV columns (one row per employee, in this order)

| Column | Value |
|---|---|
| `employee_id` | `ACME-00042` |
| `employee_name` | Current full name |
| `gross_salary` | The month's gross: basic + allowances, prorated by calendar days (§7.2) |
| `deductions` | Unpaid leave + other deductions for the month (§7.2, §7.4) |
| `net_salary` | `gross_salary − deductions` (may be negative; flagged in the summary) |

### 7.6 File format and flow

- UTF-8 **with BOM** (so Excel detects the encoding), comma-separated, CRLF line endings, a header row, and quoting by Ruby's `CSV`.
- Numbers are plain whole units (`105000`, no thousands separators); negative numbers stay numbers.
- **CSV-injection safe:** any text cell beginning with `=`, `+`, `-`, `@`, tab or CR is prefixed with `'`, so a name
  can't run as a formula in Excel.
- The file contains **employees only**. HR accounts, active or deactivated, never appear in it.
- File name: `acme-payroll-india-2026-09.csv`.

1. `GET /payroll_exports/new?country_id=…&month=2026-09` renders the **summary**: headcount, joiners, leavers, pay
   changes, and totals of gross salary, deductions and net salary. It also shows **warnings**, with links to
   the employees concerned: rows with negative net pay, and data changed since this month was last exported.
2. `POST /payroll_exports` generates the file, records a `PayrollExport` (row count, SHA-256, user) and responds with
   `send_data` (`disposition: attachment`). The form uses `data-turbo="false"` so the browser handles the download.
3. Months can be chosen from the organization's earliest hire date up to **next month** (so scheduled changes can be
   previewed). The page repeats the known limitation: *past months use today's policy percentages, role and department.*

## 8. Testing strategy (test-first, RSpec)

**Gems** (`group :development, :test`): `rspec-rails`, `factory_bot_rails`, `faker`, `shoulda-matchers`,
`capybara`, `selenium-webdriver`.

> FactoryGirl was renamed **FactoryBot** in 2017. `factory_girl` is unmaintained, so we use `factory_bot_rails`: same
> DSL, current name.

**Layout**

```
spec/
  services/     pay_calculator_spec.rb, salary_stats_spec.rb, allowance_name_guard_spec.rb,
                insights/country_report_spec.rb, onboarding/wizard_spec.rb, team/invite_user_spec.rb,
                salary_revisions/{record,void,correct}_spec.rb, employment/{end,undo_end}_spec.rb,
                payroll/{month,monthly_pay,run,csv_export}_spec.rb
  models/       organization_spec.rb, user_spec.rb, employee_spec.rb, salary_revision_spec.rb, pay_structure_spec.rb, …
  queries/      employee_search_spec.rb
  requests/     employees_spec.rb, salary_revisions_spec.rb, employment_ends_spec.rb, payroll_exports_spec.rb, payroll_deductions_spec.rb,
                pay_structures_spec.rb, country_allowances_spec.rb, insights_spec.rb,
                onboarding_spec.rb, settings/users_spec.rb, authentication_spec.rb
  system/       sign_in_and_setup_spec.rb, employee_management_spec.rb, salary_revision_spec.rb,
                end_of_employment_spec.rb, payroll_export_spec.rb, edit_conflict_spec.rb, insights_spec.rb
  factories/    one file per model
  support/      factory_bot.rb, shoulda_matchers.rb, capybara.rb, devise.rb (Devise::Test::IntegrationHelpers),
                shared_examples/tenant_isolated.rb, csv_helpers.rb
```

Date-dependent specs freeze time with `travel_to` (Rails' `ActiveSupport::Testing::TimeHelpers`), so "today", status and
default months are deterministic.

| Level | What |
|---|---|
| Service specs | `PayCalculator` (rounding, no allowances, country + role combination, variable pay on gross including 0%, total = gross + variable, overtime with the organization's hours). `SalaryStats` (median for odd/even counts, empty set). `AllowanceNameGuard` (conflicts in both directions, case-insensitive, scoped to the organization). `Onboarding::Wizard` (next step, completion rules). `Team::InviteUser` (user created in the right organization, email sent). **`SalaryRevisions::*`**: record before hire date / after last working day / on an exited employee refused; same-date duplicate refused; backdated and scheduled flagged; void needs a reason, double void → conflict, hire revision can't be voided alone; correct is atomic (a failed replacement leaves the original in force). **`Employment::*`**: end refused with later scheduled revisions; end date before hire refused; undo refused when the email is taken by a current employee. **`Payroll::Roster`**: joiners, leavers, joined-and-left, notice-period employees, recorded-in-error excluded. **`Payroll::MonthlyPay`**: full month = annual ÷ 12; joiner and leaver proration by calendar days; mid-month revision segments (worked example in §7.2); 28/29/30/31-day months; components add up to gross; unpaid leave at the daily gross rate incl. half days; other deductions summed; negative net allowed and flagged. **`CsvExport`**: the five columns in order, net = gross − deductions, BOM, CRLF, plain numbers, formula-injection escaping, no HR accounts in the file. **`Team::InviteUser`** (deactivated account in the same org → reactivated; email of a deactivated account in another org → new account; active email anywhere → refused). |
| Query specs | `EmployeeSearch`: matches name, email and employee ID (partial, case-insensitive); each filter alone (country, department, job role, status) and in combination; default status is current (Active + Leaving); search + filters together; basic column reflects revisions (scheduled not yet, backdated yes); `%` and `_` in the search treated literally; unknown sort column falls back to default; blank params return current employees; never returns another organization's employees. |
| Model specs | Employee ID assigned on create in sequence, read-only afterwards, never reused (including for rehires), unique per organization. Hire revision created with the employee; exactly one in force. Country read-only. Status derivation (active / leaving on last day / exited next day). Email unique among employees without an exit, reusable after one. Revisions refuse edits other than voiding. `PayrollDeduction`: kind-specific fields, half-day steps, days ≤ days employed, one unpaid-leave entry per month, month must be within employment (allowed for exited employees). `User`: deactivated can't authenticate or reset a password, and their email can be reused by a new active account. Validations and associations (with `shoulda-matchers`), cross-organization reference rejection, email normalisation, `restrict_with_error` deletes, the composite FK, `lock_version` conflicts. |
| Request specs | Every page redirects to sign-in when signed out, and to the wizard while setup is incomplete. CRUD happy paths, 422 on invalid input, 409 on stale `lock_version` and on double void, no destroy route for employees, exited employees can't be edited, the export responds with `text/csv` + attachment and writes a log row, deductions CRUD with 409 on stale `lock_version`, a deactivated user is signed out on their next request and can't sign in. Paging, filtering and sorting. **`it_behaves_like "tenant isolated"` for every resource, including nested revisions and exports.** Lockout after 5 failed sign-ins. |
| System specs (Capybara, headless Chrome) | Sign in → complete setup → create a pay structure → add an employee with basic-pay pre-fill and the live breakdown. Record a backdated raise, see it in the history and the export summary. Correct a revision. End employment → status *Leaving* → travel past the date → *Exited*, read-only → undo. Enter unpaid leave and an advance recovery on the Deductions page, then download the payroll CSV and check gross salary, deductions and net salary for a few rows. Remove a colleague → they can't sign in → re-add them → the account is reactivated. Two users editing the same employee (the conflict shows who changed it). Insights drill-down. |

**Factories**

```ruby
FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    employee_code_prefix { "ACME" }
    standard_hours_per_week { 40 }
    setup_completed_at { Time.current }
    trait(:pending_setup) { setup_completed_at { nil } }
  end

  factory :user do
    organization
    full_name { Faker::Name.name }
    sequence(:email) { |n| "hr#{n}@example.test" }
    password  { "correct-horse-battery" }
  end

  factory :country do
    sequence(:name) { |n| "#{Faker::Address.country} #{n}" }
    currency_code { Faker::Currency.code }
    trait(:india) { name { "India" }; currency_code { "INR" } }
  end

  factory :job_role do
    organization
    sequence(:name) { |n| "#{Faker::Job.title} #{n}" }
  end

  factory :department do
    organization
    sequence(:name) { |n| "#{Faker::Commerce.department(max: 1)} #{n}" }
  end

  factory :pay_structure do
    organization
    job_role { association :job_role, organization: }
    country
    default_basic_pay       { Faker::Number.between(from: 30_000, to: 200_000) }
    variable_pay_percent_bp { 1_000 }
    overtime_percent_bp     { 15_000 }
    after(:build) { |ps| ps.organization.countries << ps.country unless ps.organization.countries.include?(ps.country) }
  end

  factory :employee do
    pay_structure                                   # keeps organization, country and role consistent
    organization { pay_structure.organization }
    country      { pay_structure.country }
    job_role     { pay_structure.job_role }
    department   { association :department, organization: }
    full_name       { Faker::Name.name }
    sequence(:email) { |n| "employee#{n}@acme.test" }
    employment_type { "full_time" }
    hire_date       { Faker::Date.backward(days: 3650) }
    initial_basic_pay { pay_structure.default_basic_pay }   # becomes the hire revision

    trait :leaving do
      employment_end_date { 1.month.from_now.to_date }
      exit_reason { "resignation" }
    end
    trait :exited do
      employment_end_date { 1.month.ago.to_date }
      exit_reason { "resignation" }
    end
  end

  factory :salary_revision do
    employee
    organization { employee.organization }
    created_by   { association :user, organization: }
    effective_on { employee.hire_date + 1.year }
    basic_pay    { 100_000 }
    reason       { "appraisal" }
  end

  factory :payroll_deduction do
    employee
    organization { employee.organization }
    created_by   { association :user, organization: }
    period_start { Date.current.beginning_of_month }
    kind { "other" }
    amount { 5_000 }
    description { "Salary advance recovery" }

    trait :unpaid_leave do
      kind { "unpaid_leave" }
      unpaid_half_days { 2 }   # 1 day
      amount { nil }
      description { nil }
    end
  end
end
```

Conventions:
- Names use `sequence`s so uniqueness validations never flake.
- `Faker::Config.random` is seeded from RSpec's `--seed`, so a failing run can be reproduced exactly.
- **Faker is for incidental data only.** Specs that assert numbers or dates (pay calculation, insights, revisions,
  export) set them explicitly, e.g. `create(:employee, initial_basic_pay: 1_000_000, hire_date: Date.new(2024, 4, 1))`,
  so the expected values are visible in the spec.
- Prefer `build` / `build_stubbed` over `create` in specs that don't need the database, to keep the suite fast.
- Request and system specs sign in with `sign_in create(:user)` (Devise test helpers).

## 9. Seed and demo data

**Seed (`db/seeds.rb`)** is idempotent (`find_or_create_by!`), so it can be re-run safely. It creates:

1. The global **countries** (8, with currencies).
2. The **ACME organization** with **setup left pending** (`setup_completed_at: nil`), so the first login walks through
   the setup wizard.
3. The first **HR user** in ACME: `hr@acme.test`. The password comes from `ENV["SEED_HR_PASSWORD"]`; if that is unset,
   a random password is generated and **printed once** to the console. No password is committed to the repository.

**Demo data (`bin/rails demo:populate`)** fills an organization at scale for demos and performance checks. It is kept
separate from the seed so the seed stays minimal and the wizard stays demonstrable.

```
bin/rails demo:populate ORG="ACME" EMPLOYEES=10000
```

- If the organization's setup is still pending, it applies standard defaults (all 8 countries, HRA 40% in India, about
  8 departments, about 15 roles) and marks setup complete. Otherwise it uses what the HR user configured.
- It creates a pay structure for every operating country + role with realistic local-currency defaults and variable pay
  (e.g. 10% for most roles, 30–50% for sales roles), only where one doesn't exist yet.
- **Employees:** 10,000, with hire dates spread over the last 6 years. It reserves a block of employee numbers from the
  organization's counter up front, so demo IDs continue the same sequence as those created in the UI. Names come from
  Faker, and each starting basic is spread ±25% around the structure's default.
- **Salary history:** a hire revision for everyone, plus a yearly **appraisal** every 1 April after hire (+3–12%),
  about 5% **promotions** (+15–25%), a handful of **backdated** entries in the current month, and some **scheduled** raises
  for next April. That is roughly 35–40k revision rows.
- **Leavers:** about 12% exited over the period (weighted towards resignation), about 1% *Leaving* with end dates in the
  next 60 days, and a few *recorded in error*.
- **Deductions** for the current and previous month: about 8% of employees with 0.5–3 unpaid days, and a handful of
  "salary advance recovery" deductions. The last six months also get **payroll export log entries**, one per country.
- Everything is inserted with `insert_all` in batches (it runs in seconds) and is deterministic
  (`Faker::Config.random = Random.new(42)`), so every demo shows the same numbers.

## 10. Running locally

```
bin/setup                                   # bundle install, db:prepare, db:seed (prints the HR login)
bin/dev                                     # Rails server + Tailwind watcher, http://localhost:3000
bin/rails demo:populate ORG="ACME"          # optional: 10k employees with history
bundle exec rspec                           # all specs
bundle exec rspec spec/system               # browser flows only
```

Password-reset and invite emails can be read at http://localhost:3000/letter_opener in development.

