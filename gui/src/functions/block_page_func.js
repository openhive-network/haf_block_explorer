export const handleNextBlock = (navigate, setBlockNumber, blockNumber) => {
  navigate(`/block/${blockNumber + 1}`);
  setBlockNumber(blockNumber + 1);
};
export const handlePreviousBlock = (navigate, setBlockNumber, blockNumber) => {
  navigate(`/block/${blockNumber - 1}`);
  setBlockNumber(blockNumber - 1);
};

export const handleFilters = (set_show_modal, show_modal) =>
  set_show_modal(!show_modal);
