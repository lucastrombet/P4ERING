class ExercisesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin, except: [:index, :show]
  before_action :set_exercise, only: [:show, :edit, :update, :destroy]
  before_action :require_editable, only: [:edit, :update, :destroy]

  def index
    @exercises = if current_user.staff?
                   Exercise.visible_to(current_user)
                 else
                   Exercise.where(restricted: false).not_in_any_classroom
                 end.order(difficulty: :asc, created_at: :desc)
  end

  def show
    # A professor can't open another professor's unshared exercise (admins
    # can — visible_to? is always true for them).
    if current_user.staff? && !@exercise.visible_to?(current_user)
      return redirect_to exercises_path, alert: t("exercises.show.restricted_access")
    end

    if @exercise.restricted? && !current_user.staff?
      enrolled_exercise_ids = Exercise.joins(:classroom_exercises => :classroom)
                                      .where(classrooms: { id: current_user.classroom_ids })
                                      .pluck(:id)
      unless enrolled_exercise_ids.include?(@exercise.id)
        redirect_to exercises_path, alert: t("exercises.show.restricted_access")
        return
      end
    end
    @submission = Submission.new
    @previous_submissions = current_user.submissions.where(exercise: @exercise, test_run: false).order(created_at: :desc)
  end
  
  def new
    @exercise = Exercise.new
  end
  
  def create
    @exercise = Exercise.new(exercise_params)
    @exercise.owner = current_user

    if @exercise.save
      redirect_to @exercise, notice: 'Exercise was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @exercise.update(exercise_params)
      redirect_to @exercise, notice: 'Exercise was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @exercise.destroy
    redirect_to exercises_path, notice: 'Exercise was successfully deleted.'
  end
  
  private
  
  def set_exercise
    @exercise = Exercise.find(params[:id])
  end

  # This controller's mutations are admin-only (require_admin above), but
  # the classroom lock binds admins too — see Exercise#editable_by?.
  def require_editable
    return if @exercise.editable_by?(current_user)

    reason = @exercise.in_use? ? :locked_in_classroom : :not_owner
    redirect_to exercises_path, alert: t("admin.exercises.flash.#{reason}")
  end

  def exercise_params
    params.require(:exercise).permit(:title, :description, :language, :difficulty, :starter_code)
  end
  
  def require_admin
    redirect_to root_path, alert: 'Access denied' unless current_user.admin?
  end
end
