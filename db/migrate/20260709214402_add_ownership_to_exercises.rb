class AddOwnershipToExercises < ActiveRecord::Migration[8.1]
  def up
    add_reference :exercises, :user, foreign_key: true
    add_column :exercises, :visible_by_other_professors, :boolean, default: true, null: false

    # Pre-existing exercises were created before ownership existed — hand
    # them to the first admin (they stay shared via the column default).
    execute <<~SQL
      UPDATE exercises
      SET user_id = (SELECT id FROM users WHERE admin = TRUE ORDER BY id LIMIT 1)
    SQL
  end

  def down
    remove_reference :exercises, :user
    remove_column :exercises, :visible_by_other_professors
  end
end
