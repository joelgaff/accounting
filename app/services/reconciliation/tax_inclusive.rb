module Reconciliation
  # A bank line is a gross amount. Back the tax out so that net plus the tax
  # a LineItem would compute (rounded to the cent) lands exactly on the gross.
  module TaxInclusive
    def self.split(gross, rate)
      gross = BigDecimal(gross.to_s)
      return [ gross, BigDecimal("0") ] if rate.nil? || rate.to_d.zero?

      rate = rate.to_d
      base = (gross / (1 + rate)).round(2)
      net  = [ 0, -0.01, 0.01, -0.02, 0.02 ].map { |delta| base + BigDecimal(delta.to_s) }
                                           .find { |n| n + (n * rate).round(2) == gross } || base
      [ net, gross - net ]
    end
  end
end
