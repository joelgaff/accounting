# Settings → People (local mode): who can sign in. In Launchpad mode the hub
# owns that, so this page points there.
class PeopleController < ApplicationController
  before_action :local_mode_only

  def index
    @people = Current.organization.users.local.order(:name, :email_address)
    @person = Current.organization.users.build
  end

  def create
    @person = Current.organization.users.build(person_params)
    if @person.save
      LoginMailer.welcome(@person, added_by: Current.user).deliver_later
      redirect_to people_path, notice: "#{@person.name} added; a welcome email is on its way."
    else
      @people = Current.organization.users.local.order(:name, :email_address)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    person = Current.organization.users.local.find(params[:id])
    return redirect_to people_path, alert: "You can't remove yourself." if person == Current.user
    person.destroy
    redirect_to people_path, notice: "#{person.name} removed."
  end

  private

  def local_mode_only
    redirect_to settings_path, alert: "People are managed in Launchpad." if Auth.launchpad?
  end

  def person_params
    params.require(:user).permit(:name, :email_address)
  end
end
