class SettingsController < ApplicationController
  def show
    @settings        = Current.organization.settings
    load_accounts
  end

  def update
    @settings = Current.organization.settings
    if @settings.update(settings_params)
      redirect_to settings_path, notice: "Settings updated."
    else
      load_accounts
      render :show, status: :unprocessable_entity
    end
  end

  # The entity whose books these are; shown in the sidebar, status bar, mail and PDFs.
  def organization
    if Current.organization.update(params.require(:organization).permit(:name))
      redirect_to settings_path, notice: "Books renamed to #{Current.organization.name}."
    else
      redirect_to settings_path, alert: "The name can't be blank."
    end
  end

  # The name mail goes out under and where replies land. The address itself is the operator's.
  def emailing
    settings = Current.organization.settings
    if settings.update(params.require(:organization_settings).permit(:email_from_name, :email_reply_to))
      redirect_to settings_path, notice: "Email will go out as #{settings.email_sender_name}#{settings.email_reply_to ? ", replies to #{settings.email_reply_to}" : ''}."
    else
      redirect_to settings_path, alert: "Email settings not saved: #{settings.errors.full_messages.to_sentence.sub('Email reply to', 'reply-to')}."
    end
  end

  # Invoice prefix and next number. A blank next number means "follow the invoices".
  def invoicing
    settings = Current.organization.settings
    attrs    = params.require(:organization_settings).permit(:invoice_prefix, :invoice_next_number)
    attrs[:invoice_next_number] = attrs[:invoice_next_number].presence
    if settings.update(attrs)
      redirect_to settings_path, notice: "Invoices will be numbered from #{settings.next_invoice_number}."
    else
      redirect_to settings_path, alert: "Invoice numbering not saved: #{settings.errors.full_messages.to_sentence.sub('Invoice next number', 'the next number')}."
    end
  end

  # ── The "You" panel (local mode; Launchpad owns name and email otherwise) ──

  def profile
    return redirect_to settings_path, alert: "Your name comes from Launchpad." if Auth.launchpad?
    if Current.user.update(params.require(:user).permit(:name))
      redirect_to settings_path, notice: "Name saved."
    else
      redirect_to settings_path, alert: Current.user.errors.full_messages.to_sentence
    end
  end

  # A new address only takes over once a code sent to it comes back.
  def email
    return redirect_to settings_path, alert: "Your email comes from Launchpad." if Auth.launchpad?
    wanted = User.normalize_value_for(:email_address, params[:email])
    return redirect_to settings_path, alert: "That's already your email." if wanted == Current.user.email_address
    return redirect_to settings_path, alert: "That address is already in use." if User.local.where(email_address: wanted).where.not(id: Current.user.id).exists?
    code = Current.user.issue_email_change_code!(wanted)
    LoginMailer.code(Current.user, code, to: wanted).deliver_later
    redirect_to settings_path, notice: "A code is on its way to #{wanted}."
  rescue User::TooManyRequests
    redirect_to settings_path, alert: "Too many codes requested; try again in a few minutes."
  end

  def confirm_email
    user = Current.user
    return redirect_to settings_path if user.pending_email_address.blank?
    if user.email_change_code_valid?(params[:code])
      old = user.email_address
      user.update!(email_address: user.pending_email_address)
      user.cancel_email_change!
      LoginMailer.email_changed(user, old_address: old).deliver_later
      redirect_to settings_path, notice: "Email changed to #{user.email_address}."
    else
      redirect_to settings_path, alert: "That code isn't right or has expired."
    end
  end

  def cancel_email
    Current.user.cancel_email_change!
    redirect_to settings_path, notice: "Email change cancelled."
  end

  # Per-person, not per-organisation: the theme is saved on the user record
  # and follows them to any device. The page paints it before this returns.
  def appearance
    if Current.user.update(theme: params.require(:user)[:theme])
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to settings_path, notice: "Switched to the #{Current.user.theme} theme." }
      end
    else
      Current.user.reload
      redirect_to settings_path, alert: "That isn't one of the themes."
    end
  end

  private

  def load_accounts
    @bank_accounts      = Current.organization.bank_accounts.active.ordered
    @asset_accounts     = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
    @liability_accounts = Plutus::Liability.where(tenant: Current.organization).order(:code, :name)
  end

  def settings_params
    params.require(:organization_settings).permit(:bank_account_id, :receivable_account_id, :payable_account_id)
  end
end
