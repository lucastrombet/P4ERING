module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      # Devise stores users under the :user Warden scope, not the default :default scope.
      self.current_user = env['warden'].user(:user) || reject_unauthorized_connection
    end
  end
end
