class AddTestRunToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :submissions, :test_run, :boolean, null: false, default: false
  end
end
