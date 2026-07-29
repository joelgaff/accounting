class ContactsController < ApplicationController
  before_action :require_login
  before_action :load_contact, only: %i[show edit update destroy]

  def index
    @contacts = Current.organization.contacts.ordered
    @contacts = @contacts.where(kind: [params[:kind], "both"]) if Contact::KINDS.include?(params[:kind])
  end

  def show
  end

  def new
    @contact = Current.organization.contacts.build(kind: "customer")
  end

  def create
    @contact = Current.organization.contacts.build(contact_params)
    if @contact.save
      redirect_to contacts_path, notice: "Contact created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @contact.update(contact_params)
      redirect_to contacts_path, notice: "Contact updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.destroy
    redirect_to contacts_path, notice: "Contact removed."
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to contacts_path, alert: "Can't remove — this contact has invoices or expenses."
  end

  private

  def load_contact
    @contact = Current.organization.contacts.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:name, :kind, :email, :phone, :first_name, :last_name,
                                    :company_number, :tax_number, :address, :city, :region,
                                    :postal_code, :country, :notes)
  end
end
