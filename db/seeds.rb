# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
#
#
admin = User.find_or_initialize_by(email: 'admin@p4ering.com')
if admin.new_record?
  admin.name = 'Administrator'
  admin.password = 'admin123'
  admin.password_confirmation = 'admin123'
  admin.admin = true
  admin.save!
  puts "Admin user created: admin@p4ering.com / admin123"
end

# Create sample exercises
exercises = [
  {
    title: "Hello World",
    description: "Write a program that prints 'Hello, World!' to the console.\n\nExample output:\nHello, World!",
    language: "Python",
    difficulty: 1
  },
  {
    title: "FizzBuzz Challenge",
    description: "Write a program that prints numbers from 1 to 100. For multiples of 3, print 'Fizz' instead of the number. For multiples of 5, print 'Buzz'. For numbers that are multiples of both 3 and 5, print 'FizzBuzz'.",
    language: "JavaScript",
    difficulty: 2
  },
  {
    title: "Fibonacci Sequence",
    description: "Write a function that returns the nth number in the Fibonacci sequence. The Fibonacci sequence starts with 0, 1, 1, 2, 3, 5, 8, ...",
    language: "Ruby",
    difficulty: 3
  },
  {
    title: "Palindrome Checker",
    description: "Write a function that checks if a given string is a palindrome (reads the same forwards and backwards). Ignore case and non-alphanumeric characters.\n\nExample:\n'racecar' -> true\n'hello' -> false",
    language: "Python",
    difficulty: 2
  },
  {
    title: "Binary Search Implementation",
    description: "Implement a binary search algorithm to find an element in a sorted array. Return the index of the element if found, otherwise return -1.",
    language: "Java",
    difficulty: 4
  },
  {
    title: "Reverse a String",
    description: "Write a function that reverses a string without using built-in reverse functions.\n\nExample:\nInput: 'hello'\nOutput: 'olleh'",
    language: "JavaScript",
    difficulty: 1
  },
  {
    title: "Factorial Calculator",
    description: "Write a recursive function to calculate the factorial of a number n (n!). Factorial of n is the product of all positive integers less than or equal to n.\n\nExample:\n5! = 5 * 4 * 3 * 2 * 1 = 120",
    language: "Ruby",
    difficulty: 2
  },
  {
    title: "Two Sum Problem",
    description: "Given an array of integers nums and an integer target, return indices of the two numbers that add up to target. You may assume that each input would have exactly one solution.",
    language: "Python",
    difficulty: 3
  }
]

exercises.each do |exercise|
  ex = Exercise.find_or_initialize_by(title: exercise[:title])
  if ex.new_record?
    ex.description = exercise[:description]
    ex.language = exercise[:language]
    ex.difficulty = exercise[:difficulty]
    ex.save!
    puts "Created exercise: #{exercise[:title]}"
  end
end

puts "Seed completed!"
