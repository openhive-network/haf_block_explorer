export const handleNextPage = (
  set_pagination,
  get_last_trx_on_page,
  setPage,
  get_first_trx_on_page
) => {
  set_pagination(get_last_trx_on_page);
  setPage((prev) => [...prev, get_first_trx_on_page]);
};

export const handlePrevPage = (setPage, page, set_pagination) => {
  setPage(page.slice(0, -1));
  set_pagination(page.pop());
};

export const clearFilters = (
  setEndDateState,
  setStartDateState,
  set_op_filters
) => {
  setEndDateState(null);
  setStartDateState(null);
  set_op_filters([]);
};
