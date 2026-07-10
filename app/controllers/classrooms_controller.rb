# Student-facing classrooms: the public list of self-enrollment classrooms
# plus the ones the student is already in. Professors manage their own
# classrooms in Professor::ClassroomsController — this one only ever
# creates an enrollment for current_user, never touches other users.
class ClassroomsController < ApplicationController
  before_action :authenticate_user!

  def index
    @enrolled = current_user.classrooms.includes(:professor).order(:start_date)
    @open = Classroom.open_for_enrollment
                     .where.not(id: @enrolled.map(&:id))
                     .includes(:professor)
                     .order(:date_enrollment)
  end

  def enroll
    classroom = Classroom.find(params[:id])

    unless classroom.enrollable_by?(current_user)
      return redirect_to classrooms_path, alert: t('classrooms.index.not_enrollable')
    end

    ClassroomEnrollment.create!(classroom: classroom, user: current_user)
    redirect_to classrooms_path, notice: t('classrooms.index.enrolled', name: classroom.name)
  end
end
