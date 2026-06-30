class CreateExerciseTrafficGenerators < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_traffic_generators do |t|
      t.references :exercise,          null: false, foreign_key: true
      t.references :traffic_generator, null: false, foreign_key: true

      t.timestamps
    end

    add_index :exercise_traffic_generators,
              [:exercise_id, :traffic_generator_id],
              unique: true,
              name: 'index_exercise_traffic_generators_unique'
  end
end
