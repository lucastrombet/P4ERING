class CreateTrafficGenerators < ActiveRecord::Migration[8.1]
  def change
    create_table :traffic_generators do |t|
      t.string  :name,             null: false
      t.text    :description
      t.string  :protocol,         null: false, default: 'TCP'
      t.integer :duration,         null: false, default: 10
      t.integer :port,             null: false, default: 5201
      t.string  :bandwidth
      t.integer :parallel_streams,             default: 1
      t.string  :packet_length
      t.integer :interval,                     default: 1
      t.boolean :reverse,          null: false, default: false
      t.string  :tos

      t.timestamps
    end
  end
end
