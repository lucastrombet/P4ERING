namespace :p4ering do
  desc "Create an admin user"
  task create_admin: :environment do
    puts "Creating admin user..."
    admin = User.new(
      email: 'admin@p4ering.com',
      password: 'admin123',
      password_confirmation: 'admin123',
      name: 'System Administrator',
      admin: true
    )
    
    if admin.save
      puts "✓ Admin user created successfully!"
      puts "  Email: admin@p4ering.com"
      puts "  Password: admin123"
    else
      puts "✗ Failed to create admin user:"
      puts admin.errors.full_messages
    end
  end
end
