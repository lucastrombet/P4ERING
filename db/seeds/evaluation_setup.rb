# Reproducible seed: two evaluator professor accounts, one classroom each
# with the full existing exercise catalog attached, and a demo student
# self-enrolled in both classrooms (used to produce example submissions).
#
#   bin/rails runner db/seeds/evaluation_setup.rb
#
# Idempotent: safe to re-run. Existing users keep their password (only set
# at creation time, so re-running never resets access); newly generated
# passwords are printed once, only when the account is first created.

CORE_EXERCISE_TITLES = [
  "Forwarding Básico",
  "Tunneling Básico",
  "Source Routing",
  "Packet Spoofing",
  "Redirecionamento de Endereço MAC",
].freeze

PROFESSORS = [
  { name: "João Henrique", email: "joao@p4ering.net.br",
    classroom: "Avaliação P4ering — Prof. João Henrique" },
  { name: "Denise Goya",   email: "denise@p4ering.net.br",
    classroom: "Avaliação P4ering — Prof. Denise Goya" },
].freeze

def find_or_create_user(name:, email:, professor: false)
  user = User.find_by(email: email)
  return user if user

  password = SecureRandom.base58(12)
  user = User.create!(name: name, email: email, password: password, professor: professor)
  puts "Created #{email} — password: #{password}"
  user
end

exercises = CORE_EXERCISE_TITLES.map { |title| Exercise.find_by!(title: title) }
demo_student = find_or_create_user(name: "Aluno Demo", email: "aluno.demo@p4ering.net.br")

PROFESSORS.each do |data|
  professor = find_or_create_user(name: data[:name], email: data[:email], professor: true)

  classroom = Classroom.find_or_initialize_by(name: data[:classroom])
  classroom.assign_attributes(
    professor:       professor,
    description:     "Turma de avaliação da plataforma P4ering para o TG — inclui todos os " \
                      "exercícios atualmente disponíveis.",
    start_date:      Date.current,
    end_date:        Date.current + 2.weeks,
    self_enrollment: true,
    date_enrollment: Date.current + 2.weeks,
  )
  classroom.save!

  exercises.each do |ex|
    next if classroom.classroom_exercises.exists?(exercise_id: ex.id)
    classroom.classroom_exercises.create!(
      exercise: ex, start_date: classroom.start_date, end_date: classroom.end_date
    )
  end

  unless classroom.classroom_enrollments.exists?(user_id: demo_student.id)
    classroom.classroom_enrollments.create!(user: demo_student)
  end

  puts "Classroom '#{classroom.name}' — professor=#{professor.email}, " \
       "#{classroom.classroom_exercises.count} exercises, demo student enrolled"
end
