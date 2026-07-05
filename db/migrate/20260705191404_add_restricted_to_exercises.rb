class AddRestrictedToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :restricted, :boolean, null: false, default: false
    add_index  :exercises, :restricted
  end
end
