class CreateClassroomExercises < ActiveRecord::Migration[8.1]
  def change
    create_table :classroom_exercises do |t|
      t.references :classroom, null: false, foreign_key: true
      t.references :exercise,  null: false, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date,   null: false
      t.timestamps
    end
    add_index :classroom_exercises, [:classroom_id, :exercise_id], unique: true
  end
end
