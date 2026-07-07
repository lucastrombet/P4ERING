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

ActiveRecord::Schema[8.1].define(version: 2026_07_07_015738) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "classroom_enrollments", force: :cascade do |t|
    t.bigint "classroom_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["classroom_id", "user_id"], name: "index_classroom_enrollments_on_classroom_id_and_user_id", unique: true
    t.index ["classroom_id"], name: "index_classroom_enrollments_on_classroom_id"
    t.index ["user_id"], name: "index_classroom_enrollments_on_user_id"
  end

  create_table "classroom_exercises", force: :cascade do |t|
    t.bigint "classroom_id", null: false
    t.datetime "created_at", null: false
    t.date "end_date", null: false
    t.bigint "exercise_id", null: false
    t.date "start_date", null: false
    t.datetime "updated_at", null: false
    t.index ["classroom_id", "exercise_id"], name: "index_classroom_exercises_on_classroom_id_and_exercise_id", unique: true
    t.index ["classroom_id"], name: "index_classroom_exercises_on_classroom_id"
    t.index ["exercise_id"], name: "index_classroom_exercises_on_exercise_id"
  end

  create_table "classrooms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.date "end_date", null: false
    t.string "name", null: false
    t.bigint "professor_id", null: false
    t.date "start_date", null: false
    t.datetime "updated_at", null: false
    t.index ["professor_id"], name: "index_classrooms_on_professor_id"
  end

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
    t.text "evaluation_criteria"
    t.string "language"
    t.boolean "restricted", default: false, null: false
    t.text "starter_code"
    t.string "title"
    t.text "topology_config"
    t.datetime "updated_at", null: false
    t.index ["restricted"], name: "index_exercises_on_restricted"
  end

  create_table "game_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.text "error"
    t.datetime "last_seen_at"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status"], name: "index_game_sessions_on_status"
    t.index ["user_id"], name: "index_game_sessions_on_user_id"
  end

  create_table "submissions", force: :cascade do |t|
    t.text "code"
    t.datetime "created_at", null: false
    t.text "evaluation_result"
    t.bigint "exercise_id", null: false
    t.text "feedback"
    t.text "packet_captures"
    t.boolean "passed"
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
    t.boolean "professor", default: false, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "classroom_enrollments", "classrooms"
  add_foreign_key "classroom_enrollments", "users"
  add_foreign_key "classroom_exercises", "classrooms"
  add_foreign_key "classroom_exercises", "exercises"
  add_foreign_key "classrooms", "users", column: "professor_id"
  add_foreign_key "exercise_traffic_generators", "exercises"
  add_foreign_key "exercise_traffic_generators", "traffic_generators"
  add_foreign_key "game_sessions", "users"
  add_foreign_key "submissions", "exercises"
  add_foreign_key "submissions", "users"
end
