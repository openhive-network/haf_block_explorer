import axios from "axios";

//User profile history pagination #2

export const userPagination = (
  userProfile,
  startPagintation,
  setUser_profile_data,
  limit,
  filter
) => {
  if (userProfile !== "") {
    axios({
      method: "post",
      url: "http://192.168.5.118:3002/rpc/get_ops_by_account",
      headers: { "Content-Type": "application/json" },
      data: {
        _account: userProfile,
        _start: startPagintation,
        _limit: limit,
        _filter: filter,
      },
    }).then((res) => setUser_profile_data(res.data));
  }
};

export const calculate_hive_hbd = (value) => {
  const res = Number(value) / 1000;
  return res.toFixed(2);
};

export const calculate_vests = (value) => {
  const res = Number(value) / 1000000;
  return res.toFixed(2);
};

export const calculateHivePower = (
  account_vests,
  vesting_fund,
  vesting_shares
) => {
  const vest_sum = vesting_fund * (Number(account_vests) / vesting_shares);
  const hive_power = vest_sum / 1000;
  return hive_power.toFixed(2);
};
