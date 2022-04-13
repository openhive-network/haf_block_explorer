import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const ApiContext = createContext();

export const ApiContextProvider = ({ children }) => {
  const [head_block, setHead_block] = useState([]);
  const [head_block_data, setHead_block_data] = useState([]);
  const [block_data, setBlock_data] = useState("");
  const [user_profile_data, setUser_profile_data] = useState([]);
  const [transData, setTransData] = useState("");
  const [witnessData, setWitnessData] = useState("");

  // Used in  api calls , values changes when clicked on some user/block/trnasaction values and navigates to user/block/transaction  page
  const [userProfile, setUserProfile] = useState("");
  const [blockNumber, setBlockNumber] = useState("");
  const [transactionId, setTransactionId] = useState("");
  const [dataLoaded, setDataLoaded] = useState(false);
  const [acc_history_limit, set_acc_history_limit] = useState(1000);
  //  Get user profile data
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "account_history_api.get_account_history",
        params: {
          account: userProfile,
          start: -1,
          limit: acc_history_limit,
        },
        id: 1,
      },
    }).then(
      (res) => setUser_profile_data(res?.data?.result?.history?.reverse()),
      setDataLoaded(true)
    );
  }, [userProfile, acc_history_limit]);

  // Get head block
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "database_api.get_dynamic_global_properties",
        id: 1,
      },
    }).then((res) => setHead_block(res?.data?.result));
  }, []);
  const current_head_block = head_block.head_block_number;

  //Get head block data
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "block_api.get_block",
        params: { block_num: current_head_block },
        id: 1,
      },
    }).then((res) => setHead_block_data(res?.data?.result?.block));
  }, [current_head_block]);

  // Get current block data
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "block_api.get_block",
        params: { block_num: blockNumber },
        id: 1,
      },
    }).then((res) => setBlock_data(res?.data?.result?.block));
  }, [blockNumber]);
  /// Get transaction Data
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "account_history_api.get_transaction",
        params: { id: transactionId, include_reversible: true },
        id: 1,
      },
    }).then((res) => setTransData(res?.data?.result));
  }, [transactionId]);

  // Get witnesses data

  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "condenser_api.get_witnesses_by_vote",
        params: [null, 21],
        id: 1,
      },
    }).then((res) => setWitnessData(res?.data?.result));
  }, []);

  return (
    <ApiContext.Provider
      value={{
        dataLoaded: dataLoaded,
        head_block: head_block,
        head_block_data: head_block_data,
        setUser_profile_data: setUser_profile_data,
        setBlock_data: setBlock_data,
        userProfile: userProfile,
        user_profile_data: user_profile_data,
        block_data: block_data,
        transData: transData,
        witnessData: witnessData,
        setUserProfile: setUserProfile,
        setBlockNumber: setBlockNumber,
        setTransactionId: setTransactionId,
        blockNumber: blockNumber,
        acc_history_limit: acc_history_limit,
        set_acc_history_limit: set_acc_history_limit,
      }}
    >
      {children}
    </ApiContext.Provider>
  );
};
