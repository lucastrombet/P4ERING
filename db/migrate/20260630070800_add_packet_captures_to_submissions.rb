class AddPacketCapturesToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :submissions, :packet_captures, :text
  end
end
