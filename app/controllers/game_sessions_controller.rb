class GameSessionsController < ApplicationController
  before_action :set_game_session, only: [:show, :destroy]

  MAX_CONCURRENT_SESSIONS = ENV.fetch('MAX_GAME_SESSIONS', 4).to_i

  def create
    existing = current_user.game_sessions.active.first
    return redirect_to existing if existing

    if GameSession.active.count >= MAX_CONCURRENT_SESSIONS
      return redirect_to new_game_session_path, alert: 'Sandbox is busy right now — please try again shortly.'
    end

    game_session = current_user.game_sessions.create!(status: 'pending')
    redirect_to game_session
  end

  def new
    existing = current_user.game_sessions.active.first
    return redirect_to existing if existing
  end

  def show
    unless @game_session.user == current_user
      return redirect_to new_game_session_path, alert: 'Not authorized.'
    end
  end

  def destroy
    unless @game_session.user == current_user
      return redirect_to new_game_session_path, alert: 'Not authorized.'
    end

    @game_session.end_on_exec_service!
    @game_session.update(status: 'ended', ended_at: Time.current)
    redirect_to new_game_session_path, notice: 'Sandbox ended.'
  end

  private

  def set_game_session
    @game_session = GameSession.find(params[:id])
  end
end
