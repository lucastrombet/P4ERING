class AddHostMappingToExerciseTrafficGenerators < ActiveRecord::Migration[8.1]
  def change
    # Which topology hosts this generator runs between, for this exercise —
    # the same generator profile can be reused across exercises with
    # different host pairs. No pre-existing rows in any environment, so the
    # columns can be strict from the start.
    add_column :exercise_traffic_generators, :from_host, :string, null: false
    add_column :exercise_traffic_generators, :to_host,   :string, null: false
    add_column :exercise_traffic_generators, :position,  :integer, null: false, default: 0
  end
end
