class CreateClassrooms < ActiveRecord::Migration[8.1]
  def change
    create_table :classrooms do |t|
      t.references :professor, null: false, foreign_key: { to_table: :users }
      t.string  :name,        null: false
      t.text    :description, null: false
      t.date    :start_date,  null: false
      t.date    :end_date,    null: false
      t.timestamps
    end
  end
end
