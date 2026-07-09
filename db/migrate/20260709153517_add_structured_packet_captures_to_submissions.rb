class AddStructuredPacketCapturesToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :submissions, :structured_packet_captures, :text
  end
end
