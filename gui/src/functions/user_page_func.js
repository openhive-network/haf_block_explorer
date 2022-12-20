export const handleNextPage = (
  set_pagination,
  get_last_trx_on_page,
  get_first_trx_on_page,
  setPrevNextPage
) => {
  // setPage((page += 1));
  set_pagination(get_last_trx_on_page);
  setPrevNextPage((prev) => [...prev, get_first_trx_on_page]);
};

export const handlePrevPage = (
  set_pagination,
  prevNextPage,
  setPrevNextPage
) => {
  setPrevNextPage(prevNextPage.slice(0, -1));
  set_pagination(prevNextPage.pop());
};

export const clearFilters = (
  setEndDateState,
  setStartDateState,
  set_op_filters,
  setPage
) => {
  setEndDateState(null);
  setStartDateState(null);
  set_op_filters([]);
  setPage(1);
};
