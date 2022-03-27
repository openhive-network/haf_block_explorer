import axios from "axios";
import { useEffect, useState } from "react";

//API CALLS

// Get accounts
export const getAccounts = (value, setAccName, setIsAccountFound) => {
  axios({
    method: "post",
    url: "https://api.hive.blog",
    data: {
      jsonrpc: "2.0",
      method: "condenser_api.get_accounts",
      params: [[value]],
      id: 1,
    },
  })
    .then((res) => setAccName(res.data.result[0].name))
    .catch(() => setIsAccountFound(false));
};

// Get account history
export const getAccountHistory = (
  accName,
  setUser_profile_data,
  setIsAccountFound
) => {
  axios({
    method: "post",
    url: "https://api.hive.blog",
    data: {
      jsonrpc: "2.0",
      method: "account_history_api.get_account_history",
      params: {
        account: accName,
        start: -1,
      },
      id: 1,
    },
  }).then((res) => setUser_profile_data(res.data.result.history));
  setIsAccountFound(true);
};
//Get blog
export const getBlog = (value, setBlock_data) => {
  axios({
    method: "post",
    url: "https://api.hive.blog",
    data: {
      jsonrpc: "2.0",
      method: "block_api.get_block",
      params: { block_num: value },
      id: 1,
    },
  }).then((res) => setBlock_data(res?.data?.result?.block));
};

//Get transaction

export const getTransaction = (transactionId, setTransData) => {
  axios({
    method: "post",
    url: "https://api.hive.blog",
    data: {
      jsonrpc: "2.0",
      method: "condenser_api.get_transaction",
      params: [transactionId],
      id: 1,
    },
  }).then((res) => setTransData(res?.data?.result));
};
