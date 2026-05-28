class CreateExercises < ActiveRecord::Migration[8.1]
  def change
    create_table :exercises do |t|
      t.string :title
      t.text :description
      t.string :language
      t.integer :difficulty

      t.timestamps
    end
  end
end
