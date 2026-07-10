# Hand-rolled per-field model translations over jsonb columns — the
# deliberate alternative to a gem like Mobility for a platform with two
# locales and (currently) one translated model. See Exercise.
#
#   translates :title, :description
#
# expects a `<field>_translations` jsonb column ({ "en" => "...", ... })
# and gives you:
#
#   exercise.title            -> current I18n.locale, falling back through
#                                FALLBACK_ORDER, then the legacy column
#   exercise.title_in(:en)    -> that locale only (nil if missing)
#   exercise.translation_missing?(:title, :en)
#
# The legacy column keeps working as the canonical plain value: it's
# synced before validation to the best available translation, so existing
# presence validations, `order(:title)` and SQL queries stay untouched.
# Records written before multi-language support (or via code paths that
# only set the legacy column) still render through the final fallback.
#
# Adding a new locale requires NO change here: the fallback order derives
# from I18n config, and forms should loop I18n.available_locales.
module Translatable
  extend ActiveSupport::Concern

  # Preference order when the current locale has no translation: the
  # app's default language first, then the remaining configured locales.
  def self.fallback_order
    @fallback_order ||= [I18n.default_locale, *I18n.available_locales].uniq.map(&:to_s)
  end

  class_methods do
    def translates(*fields)
      before_validation do
        fields.each do |field|
          best = best_translation(field)
          self[field] = best if best.present?
        end
      end

      fields.each do |field|
        define_method(field) do
          translations = public_send("#{field}_translations") || {}
          translations[I18n.locale.to_s].presence ||
            best_translation(field) ||
            read_attribute(field)
        end

        define_method("#{field}_in") do |locale|
          (public_send("#{field}_translations") || {})[locale.to_s].presence
        end
      end
    end
  end

  def translation_missing?(field, locale)
    public_send("#{field}_in", locale).blank?
  end

  private

  def best_translation(field)
    translations = public_send("#{field}_translations") || {}
    Translatable.fallback_order.filter_map { |l| translations[l].presence }.first ||
      translations.values.find(&:presence)
  end
end
