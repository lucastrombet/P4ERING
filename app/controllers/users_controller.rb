# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action :set_user, only: [:edit, :update, :destroy]  # UNCOMMENT THIS
  
  def index
    @users = User.all.order(created_at: :desc)
  end
  
  def new
    @user = User.new
  end
  
  def create
    puts "!!!!!!!!!!!!!!!!"
    puts "Entered create action"
    puts "!!!!!!!!!!!!!!!!"
    
    @user = User.new(user_params)
    
    # Set a default password
    @user.password = 'password123'
    @user.password_confirmation = 'password123'
    
    puts "User params: #{user_params.inspect}"
    puts "User object: #{@user.inspect}"
    puts "User valid? #{@user.valid?}"
    puts "User errors: #{@user.errors.full_messages}" if @user.invalid?
    puts "!!!!!!!!!!!!!!!!"
    
    if @user.save
      redirect_to users_path, notice: 'User was successfully created. Default password: password123'
    else
      # This will show errors in your view
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    # @user is set by set_user callback
  end
  
  def update
    # @user is set by set_user callback
    if @user.update(user_params)
      redirect_to users_path, notice: 'User was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    # @user is set by set_user callback
    @user.destroy
    redirect_to users_path, notice: 'User was successfully deleted.'
  end
  
  private
  
  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to users_path, alert: 'User not found.'
  end
  
  def user_params
    params.require(:user).permit(:email, :name, :admin, :professor)
  end
  
  def require_admin
    redirect_to root_path, alert: 'Access denied' unless current_user.admin?
  end
end
