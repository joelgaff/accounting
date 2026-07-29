class Reports::BaseController < ApplicationController
  before_action :require_login

  protected

  def parse_range(default_from:)
    from = parse_date(:from, default: default_from)
    to   = parse_date(:to,   default: Date.current)
    [from, to]
  end

  def parse_date(key, default:)
    return default if params[key].blank?
    Date.parse(params[key])
  rescue ArgumentError
    default
  end
end
