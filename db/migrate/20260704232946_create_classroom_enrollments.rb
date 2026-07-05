class CreateClassroomEnrollments < ActiveRecord::Migration[8.1]
  def change
    create_table :classroom_enrollments do |t|
      t.references :classroom, null: false, foreign_key: true
      t.references :user,      null: false, foreign_key: true
      t.timestamps
    end
    add_index :classroom_enrollments, [:classroom_id, :user_id], unique: true
  end
end
