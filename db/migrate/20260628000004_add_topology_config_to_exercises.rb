class AddTopologyConfigToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :topology_config, :text
  end
end
