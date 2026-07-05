class AddProfessorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :professor, :boolean, null: false, default: false
  end
end
