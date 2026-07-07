class Users::RegistrationsController < Devise::RegistrationsController
  # Self-service sign-up is restricted to these institutional email domains.
  # Doesn't apply to accounts created via the admin Users panel — that's a
  # staff-only path, not the public sign-up form this guards.
  ALLOWED_EMAIL_DOMAINS = %w[uscsonline.com.br online.uscs.edu.br p4ering.net.br].freeze

  # Any subdomain is accepted too (e.g. aluno.ufabc.edu.br), unlike the
  # exact-match domains above.
  ALLOWED_EMAIL_DOMAIN_SUFFIXES = %w[ufabc.edu.br].freeze

  def create
    unless allowed_domain?(params.dig(:user, :email))
      build_resource(sign_up_params)
      resource.errors.add(:email, :domain_not_allowed)
      respond_with_navigational(resource) { render :new, status: :unprocessable_entity }
      return
    end

    super
  end

  private

  def allowed_domain?(email)
    domain = email.to_s.split('@').last.to_s.downcase
    return true if ALLOWED_EMAIL_DOMAINS.include?(domain)

    ALLOWED_EMAIL_DOMAIN_SUFFIXES.any? { |suffix| domain == suffix || domain.end_with?(".#{suffix}") }
  end
end
