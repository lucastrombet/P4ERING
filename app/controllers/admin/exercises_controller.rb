# app/controllers/admin/exercises_controller.rb
class Admin::ExercisesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action :set_exercise, only: [:edit, :update, :destroy]
  before_action :require_editable, only: [:edit, :update, :destroy]

  def index
    @exercises = Exercise.visible_to(current_user).includes(:owner).order(created_at: :desc)
  end

  def new
    @exercise = Exercise.new
  end

  def create
    @exercise = Exercise.new(exercise_params)
    @exercise.owner = current_user

    if @exercise.save
      redirect_to admin_exercises_path, notice: 'Exercise was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @exercise.update(exercise_params)
      redirect_to admin_exercises_path, notice: 'Exercise was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @exercise.destroy
    redirect_to admin_exercises_path, notice: 'Exercise was successfully deleted.'
  end

  def duplicate
    source = Exercise.visible_to(current_user).find(params[:id])
    copy = source.duplicate_for(current_user)

    if copy.save
      redirect_to edit_admin_exercise_path(copy), notice: t('admin.exercises.flash.duplicated')
    else
      redirect_to admin_exercises_path, alert: copy.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_exercises_path, alert: 'Exercise not found.'
  end

  private

  def set_exercise
    @exercise = Exercise.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_exercises_path, alert: 'Exercise not found.'
  end

  # Owner-or-admin, and never while attached to a classroom (in_use?) —
  # duplicate instead. See Exercise#editable_by?.
  def require_editable
    return if @exercise.nil? || @exercise.editable_by?(current_user)

    reason = @exercise.in_use? ? :locked_in_classroom : :not_owner
    redirect_to admin_exercises_path, alert: t("admin.exercises.flash.#{reason}")
  end

  def exercise_params
    params.require(:exercise).permit(:title, :description, :language, :difficulty,
                                     :starter_code, :topology_config, :evaluation_criteria, :restricted,
                                     :visible_by_other_professors,
                                     title_translations: {}, description_translations: {},
                                     exercise_traffic_generators_attributes: [
                                       :id, :traffic_generator_id, :from_host, :to_host, :position, :_destroy
                                     ])
  end

  def require_admin
    unless current_user.staff?
      redirect_to root_path, alert: 'Access denied.'
    end
  end
end
