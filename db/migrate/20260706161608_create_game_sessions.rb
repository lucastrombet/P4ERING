class CreateGameSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :game_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :status,       null: false, default: 'pending'
      t.datetime :started_at
      t.datetime :last_seen_at
      t.datetime :ended_at
      t.text     :error
      t.timestamps
    end

    add_index :game_sessions, :status
  end
end
