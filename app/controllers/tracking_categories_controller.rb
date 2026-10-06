# Settings → Tracking: the two dimensions the books can be sliced by, with
# their options managed inline.
class TrackingCategoriesController < ApplicationController
  before_action :load_category, only: %i[edit update destroy]

  def index
    @categories = Current.organization.tracking_categories.ordered.includes(:options)
  end

  def new
    @category = Current.organization.tracking_categories.build(active: true)
    @category.options.build(active: true)
  end

  def create
    @category = Current.organization.tracking_categories.build(category_params)
    @category.position = (Current.organization.tracking_categories.maximum(:position) || 0) + 1
    if @category.save
      redirect_to tracking_categories_path, notice: "Tracking category added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @category.update(category_params)
      redirect_to tracking_categories_path, notice: "Tracking category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @category.selections.exists?
      redirect_to tracking_categories_path, alert: "“#{@category.name}” is in use on lines; deactivate it instead."
    else
      @category.destroy
      redirect_to tracking_categories_path, notice: "Tracking category removed."
    end
  end

  private

  def load_category
    @category = Current.organization.tracking_categories.find(params[:id])
  end

  def category_params
    params.require(:tracking_category).permit(:name, :active, options_attributes: %i[id name active position _destroy])
  end
end
