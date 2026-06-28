class AddStarterCodeToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :starter_code, :text
  end
end
