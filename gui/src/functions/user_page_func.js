export const handleNextPage = (
  set_pagination,
  get_last_trx_on_page,
  get_first_trx_on_page,
  setPrevNextPage,
  setPageCount,
  pageCount
) => {
  set_pagination(get_last_trx_on_page);
  setPrevNextPage((prev) => [...prev, get_first_trx_on_page]);
  setPageCount((pageCount += 1));
};

export const handlePrevPage = (
  set_pagination,
  prevNextPage,
  setPrevNextPage,
  setPageCount,
  pageCount
) => {
  setPrevNextPage(prevNextPage.slice(0, -1));
  set_pagination(prevNextPage.pop());
  setPageCount((pageCount -= 1));
};

export const clearFilters = (
  setEndDateState,
  setStartDateState,
  set_op_filters,
  setPagination,
  setPageCount
) => {
  setEndDateState(null);
  setStartDateState(null);
  set_op_filters([]);
  setPagination(-1);
  setPageCount(1);
};
