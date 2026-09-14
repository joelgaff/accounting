class Imports::BankController < ApplicationController
  before_action :load_accounts

  def new
  end

  # CSV, or an OFX/QFX download from the bank. An OFX file names its account,
  # so the bank account is picked by last four digits when not chosen.
  def create
    file = params[:file]
    if file.blank?
      flash.now[:alert] = "Choose a statement file."
      return render :new, status: :unprocessable_entity
    end

    content = file.read
    if ofx?(file, content)
      statement    = Imports::OfxParser.parse(content)
      bank_account = chosen_account || account_for(statement)
      unless bank_account
        flash.now[:alert] = "Couldn't tell which bank account this is (the file says …#{statement.account_id.to_s.last(4)}). Pick one, or set that account's last four digits under Banking."
        return render :new, status: :unprocessable_entity
      end
      result = Imports::BankStatementService.new(statement.rows, bank_account: bank_account, organization: Current.organization).call
      bank_account.update!(statement_balance: statement.ledger_balance, statement_balance_at: statement.balance_at) if statement.ledger_balance
      extra = statement.ledger_balance ? " Statement balance #{helpers.money(statement.ledger_balance)} as at #{statement.balance_at}." : ""
    else
      bank_account = chosen_account
      unless bank_account
        flash.now[:alert] = "Choose a bank account for a CSV import."
        return render :new, status: :unprocessable_entity
      end
      result = Imports::BankStatementService.new(content, bank_account: bank_account, organization: Current.organization).call
      extra  = ""
    end

    msg = "Imported #{result.imported}, duplicates skipped #{result.duplicates}."
    msg += " #{result.rules_applied} categorized by rules." if result.rules_applied.positive?
    msg += " #{result.rules_suggested} with a rule suggestion." if result.rules_suggested.positive?
    msg += extra
    msg += " Errors: #{result.errors.first(5).join('; ')}" if result.errors.any?
    redirect_to bank_transactions_path(bank_account_id: bank_account.id), notice: msg
  rescue Imports::OfxParser::ParseError => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  private

  def load_accounts
    @bank_accounts = Current.organization.bank_accounts.active.ordered.to_a
  end

  def chosen_account
    @bank_accounts.find { |a| a.id.to_s == params[:bank_account_id].to_s }
  end

  def ofx?(file, content)
    name = file.respond_to?(:original_filename) ? file.original_filename.to_s : ""
    name.match?(/\.(ofx|qfx)\z/i) || content[0, 4000].match?(/<OFX>|OFXHEADER/i)
  end

  def account_for(statement)
    suffix = statement.account_id.to_s.last(4)
    return nil if suffix.blank?
    matches = @bank_accounts.select { |b| b.last_four.present? && suffix == b.last_four }
    matches.one? ? matches.first : nil
  end
end
