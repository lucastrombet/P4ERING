# Ephemeral "Testar Código" runs — see TestRun. No Submission row is ever
# created: the run lives in the cache under a UUID for TestRun::TTL, the
# page at /test_runs/:uuid works (including reloads) until it expires, and
# then the whole thing evaporates.
class TestRunsController < ApplicationController
  before_action :authenticate_user!

  def create
    exercise = Exercise.find(params[:exercise_id])
    code = params.require(:submission).permit(:code)[:code]

    if code.blank?
      return redirect_to exercise, alert: t('test_runs.flash.code_required')
    end

    test_run = TestRun.create!(user: current_user, exercise: exercise, code: code)

    P4execClient.execute(
      job_id:       "p4test_#{test_run.uuid}",
      callback_url: P4execClient.callback_url,
      code:         code,
      topology:     exercise.topology_for_execution
    )

    redirect_to test_run_path(test_run.uuid), notice: t('test_runs.flash.started')
  rescue P4execClient::Error, Errno::ECONNREFUSED, Net::OpenTimeout => e
    Rails.logger.error("[p4test] failed to start: #{e.message}")
    redirect_to exercise, alert: t('test_runs.flash.service_unavailable')
  end

  def show
    @test_run = TestRun.find(params[:uuid])

    if @test_run.nil?
      return redirect_to exercises_path, alert: t('test_runs.flash.expired')
    end

    unless @test_run.viewable_by?(current_user)
      return redirect_to exercises_path, alert: t('test_runs.flash.not_yours')
    end

    @submission = @test_run.to_submission
  end
end
