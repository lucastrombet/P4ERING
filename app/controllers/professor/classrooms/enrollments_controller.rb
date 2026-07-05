class Professor::Classrooms::EnrollmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_professor
  before_action :set_classroom

  def create
    student = User.find(params[:enrollment][:user_id])
    @classroom.students << student
    redirect_to professor_classroom_path(@classroom), notice: "#{student.name} added to classroom."
  rescue ActiveRecord::RecordNotUnique
    redirect_to professor_classroom_path(@classroom), alert: 'Student is already enrolled.'
  end

  def destroy
    enrollment = @classroom.classroom_enrollments.find(params[:id])
    student    = enrollment.user
    enrollment.destroy
    redirect_to professor_classroom_path(@classroom), notice: "#{student.name} removed from classroom."
  end

  private

  def set_classroom
    @classroom = current_user.classrooms_as_professor.find(params[:classroom_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to professor_classrooms_path, alert: 'Classroom not found.'
  end

  def require_professor
    redirect_to root_path, alert: 'Access denied.' unless current_user.staff?
  end
end
