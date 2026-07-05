class Admin::TrafficGeneratorsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action :set_traffic_generator, only: [:edit, :update, :destroy]

  def index
    @traffic_generators = TrafficGenerator.all.order(:name)
  end

  def new
    @traffic_generator = TrafficGenerator.new(protocol: 'TCP', duration: 10, port: 5201,
                                              parallel_streams: 1, interval: 1)
  end

  def create
    @traffic_generator = TrafficGenerator.new(traffic_generator_params)
    if @traffic_generator.save
      redirect_to admin_traffic_generators_path, notice: 'Generator created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @traffic_generator.update(traffic_generator_params)
      redirect_to admin_traffic_generators_path, notice: 'Generator updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @traffic_generator.destroy
    redirect_to admin_traffic_generators_path, notice: 'Generator removed successfully.'
  end

  private

  def set_traffic_generator
    @traffic_generator = TrafficGenerator.find(params[:id])
  end

  def traffic_generator_params
    params.require(:traffic_generator).permit(
      :name, :description, :protocol, :duration, :port,
      :bandwidth, :parallel_streams, :packet_length, :interval, :reverse, :tos
    )
  end

  def require_admin
    redirect_to root_path, alert: 'Access denied.' unless current_user.staff?
  end
end
