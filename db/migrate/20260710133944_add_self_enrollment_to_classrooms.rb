class AddSelfEnrollmentToClassrooms < ActiveRecord::Migration[8.1]
  def change
    # self_enrollment: false = private, only the professor enrolls students
    # (current behavior, kept as default); true = students can join
    # themselves through the public self-enrollment page.
    add_column :classrooms, :self_enrollment, :boolean, default: false, null: false

    # Deadline for self-enrollment: students can join up to (and including)
    # this date. Only meaningful when self_enrollment is on.
    add_column :classrooms, :date_enrollment, :date
  end
end
