export const sortNumber = (object_key, count, witnessData) => {
  if (count % 2 === 0) {
    return witnessData?.sort(
      (a, b) => parseInt(b[object_key]) - parseInt(a[object_key])
    );
  } else {
    return witnessData?.sort(
      (a, b) => parseInt(a[object_key]) - parseInt(b[object_key])
    );
  }
};
export const sortString = (object_key, count, witnessData) => {
  if (count % 2 === 0) {
    witnessData?.sort((a, b) => (a[object_key] < b[object_key] ? 1 : -1));
  } else {
    witnessData?.sort((a, b) => (a[object_key] > b[object_key] ? 1 : -1));
  }
};
export const sortNestedObj = (object_key, count, witnessData) => {
  if (count % 2 === 0) {
    return witnessData?.sort(
      (a, b) => Number(b.props[object_key]) - Number(a.props[object_key])
    );
  } else {
    return witnessData?.sort(
      (a, b) => Number(a.props[object_key]) - Number(b.props[object_key])
    );
  }
};

export const sort = (name, count, witnessData) => {
  switch (name) {
    case "Name":
      sortString("owner", count, witnessData);
      break;
    case "Votes (M)":
      sortNumber("votes", count, witnessData);
      break;
    case "Missed":
      sortNumber("total_missed", count, witnessData);
      break;
    case "Last_block":
      sortNumber("last_confirmed_block_num", count, witnessData);
      break;
    case "Feed_age":
      sortNumber("last_hbd_exchange_update", count, witnessData);
      break;
    case "Price_feed":
      if (count % 2 === 0) {
        return witnessData?.sort(
          (a, b) =>
            Number(b.hbd_exchange_rate.base.split("HBD")[0]) -
            Number(a.hbd_exchange_rate.base.split("HBD")[0])
        );
      } else {
        return witnessData?.sort(
          (a, b) =>
            Number(a.hbd_exchange_rate.base.split("HBD")[0]) -
            Number(b.hbd_exchange_rate.base.split("HBD")[0])
        );
      }
    case "Ac_budget":
      sortNestedObj("account_subsidy_budget", count, witnessData);
      break;
    case "Ac_decay":
      sortNestedObj("account_subsidy_decay", count, witnessData);

      break;
    case "Block_size":
      sortNestedObj("maximum_block_size", count, witnessData);
      break;
    case "Version":
      sortNumber("hardfork_version_vote", count, witnessData);
      break;
    default:
  }
};
