class AddEvaluationSupport < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :evaluation_criteria, :text
    add_column :submissions, :passed, :boolean
    add_column :submissions, :evaluation_result, :text
  end
end
