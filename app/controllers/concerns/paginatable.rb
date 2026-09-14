# Offset pagination with no gem: `paginate(scope)` returns one page and sets
# @page / @has_more for shared/_pagination.
module Paginatable
  extend ActiveSupport::Concern

  PER_PAGE = 50

  private

  def paginate(scope, per: PER_PAGE)
    @page = [ params[:page].to_i, 1 ].max
    @per  = per
    offset  = (@page - 1) * per
    records = scope.is_a?(Array) ? scope.drop(offset).first(per + 1) : scope.limit(per + 1).offset(offset).to_a
    @has_more = records.size > per
    records.first(per)
  end
end
