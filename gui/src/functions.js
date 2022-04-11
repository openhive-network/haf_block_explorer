import axios from "axios";

///// API CALLS

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
    .then(() => setIsAccountFound(true))
    .catch(() => setIsAccountFound(false));
};

// Get blog
export const getBlog = (value, setBlockNr, setIsBlockFound) => {
  axios({
    method: "post",
    url: "https://api.hive.blog",
    data: {
      jsonrpc: "2.0",
      method: "account_history_api.get_ops_in_block",
      params: {
        block_num: value,
        only_virtual: false,
        include_reversible: true,
      },
      id: 1,
    },
  })
    .then((res) => setBlockNr(res.data.result.ops[0].block))
    .then(() => setIsBlockFound(true))
    .catch(() => setIsBlockFound(false));
};

// Get transaction

export const getTransaction = (value, setTransNr, setIsTransactionFound) => {
  axios({
    method: "post",
    url: "https://api.hive.blog",
    data: {
      jsonrpc: "2.0",
      method: "account_history_api.get_transaction",
      params: { id: value,include_reversible: true },
      id: 1,
    },
  })
    .then((res) => setTransNr(res.data.result.transaction_id))
    .then(() => setIsTransactionFound(true))
    .catch(() => setIsTransactionFound(false));
};
