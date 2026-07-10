class AddTranslationsToExercises < ActiveRecord::Migration[8.1]
  def up
    # One jsonb per translatable field: { "en" => "...", "pt-BR" => "..." }.
    # Adding a future locale is just a new key — no migration needed.
    add_column :exercises, :title_translations,       :jsonb, default: {}, null: false
    add_column :exercises, :description_translations, :jsonb, default: {}, null: false

    # Backfill: existing content (written before multi-language support,
    # some in English, some in Portuguese) is copied into BOTH locales so
    # nothing changes visually — professors refine each language later.
    execute <<~SQL
      UPDATE exercises SET
        title_translations       = jsonb_build_object('en', title, 'pt-BR', title),
        description_translations = jsonb_build_object('en', description, 'pt-BR', description)
      WHERE title IS NOT NULL
    SQL
  end

  def down
    remove_column :exercises, :title_translations
    remove_column :exercises, :description_translations
  end
end
