# An HR user who signs in. Employees are a separate table and never sign in.
class User < ApplicationRecord
  # No :registerable (no public sign-up). No :rememberable: it would bypass the 30-minute inactivity timeout.
  # No :validatable, whose email uniqueness check is global: email only has to be unique among active accounts,
  # so a deactivated account releases it.
  devise :database_authenticatable, :recoverable, :lockable, :timeoutable

  belongs_to :organization
  belongs_to :deactivated_by, class_name: "User", optional: true

  scope :active, -> { where(deactivated_at: nil) }

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :full_name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { conditions: -> { active } }, if: :active?
  validates :password, presence: true, confirmation: true, length: { within: Devise.password_length },
                       if: :password_required?

  def active? = deactivated_at.nil?

  # Deactivated → can't sign in, and an open session ends on its next request.
  def active_for_authentication? = super && active?

  def inactive_message = active? ? super : :deactivated

  # Sign-in and password-reset lookups only ever see active accounts.
  def self.find_first_by_auth_conditions(tainted_conditions, opts = {})
    active.find_by(devise_parameter_filter.filter(tainted_conditions).merge(opts))
  end

  private

  def password_required? = !persisted? || !password.nil? || !password_confirmation.nil?
end
