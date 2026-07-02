class LocalesController < ApplicationController
  skip_before_action :authenticate_user!

  def update
    if I18n.available_locales.map(&:to_s).include?(params[:locale])
      session[:locale] = params[:locale]
    end

    redirect_back fallback_location: root_path
  end
end
