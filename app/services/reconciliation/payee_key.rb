module Reconciliation
  # What makes two statement lines "the same payee": the bank's text with the
  # parts that change from one charge to the next taken out. Dates, store and
  # card numbers, invoice ids and punctuation go; words stay, lowercased.
  #   "AMZN Mktp US*2K3"        → "amzn mktp us"
  #   "GUSTO PAYROLL 09/26"     → "gusto payroll"
  module PayeeKey
    MIN_LENGTH = 4

    def self.for(text)
      key = text.to_s.downcase
                .gsub(%r{\b\d{1,2}/\d{1,2}(/\d{2,4})?\b}, " ")   # 10/02, 9/26/26
                .gsub(/[^a-z0-9 ]/, " ")                         # punctuation
                .gsub(/\b[a-z]*\d[a-z0-9]*\b/, " ")              # any token carrying a digit
                .squeeze(" ").strip
      key.length >= MIN_LENGTH ? key : nil
    end

    def self.for_line(txn) = self.for(txn.payee.presence || txn.description)
  end
end
