module ApplicationHelper
  LOCALE_FLAG_COUNTRY = {
    "en"    => "gb",
    "pt-BR" => "br"
  }.freeze

  def locale_flag_class(locale)
    "fi fi-#{LOCALE_FLAG_COUNTRY.fetch(locale.to_s, 'xx')}"
  end
end
