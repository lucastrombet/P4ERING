# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_30_070800) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "exercise_traffic_generators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exercise_id", null: false
    t.bigint "traffic_generator_id", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_id", "traffic_generator_id"], name: "index_exercise_traffic_generators_unique", unique: true
    t.index ["exercise_id"], name: "index_exercise_traffic_generators_on_exercise_id"
    t.index ["traffic_generator_id"], name: "index_exercise_traffic_generators_on_traffic_generator_id"
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "difficulty"
    t.string "language"
    t.text "starter_code"
    t.string "title"
    t.text "topology_config"
    t.datetime "updated_at", null: false
  end

  create_table "submissions", force: :cascade do |t|
    t.text "code"
    t.datetime "created_at", null: false
    t.bigint "exercise_id", null: false
    t.text "feedback"
    t.text "packet_captures"
    t.string "status"
    t.boolean "test_run", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["exercise_id"], name: "index_submissions_on_exercise_id"
    t.index ["user_id"], name: "index_submissions_on_user_id"
  end

  create_table "traffic_generators", force: :cascade do |t|
    t.string "bandwidth"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration", default: 10, null: false
    t.integer "interval", default: 1
    t.string "name", null: false
    t.string "packet_length"
    t.integer "parallel_streams", default: 1
    t.integer "port", default: 5201, null: false
    t.string "protocol", default: "TCP", null: false
    t.boolean "reverse", default: false, null: false
    t.string "tos"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "exercise_traffic_generators", "exercises"
  add_foreign_key "exercise_traffic_generators", "traffic_generators"
  add_foreign_key "submissions", "exercises"
  add_foreign_key "submissions", "users"
end
