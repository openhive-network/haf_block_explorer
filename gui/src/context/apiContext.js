import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const ApiContext = createContext();

export const ApiContextProvider = ({ children }) => {
  const [head_block, setHead_block] = useState([]);
  const [head_block_data, setHead_block_data] = useState([]);
  const [block_data, setBlock_data] = useState("");
  const [user_profile_data, setUser_profile_data] = useState([]);
  const [userProfile, setUserProfile] = useState(""); // used in user Data api call , value changes when clicked on some user and navigates to user profile page
  const [transData, setTransData] = useState("");
  const [witnessData, setWitnessData] = useState("");

  const username = window.location.href.split("/user/").pop();
  const block = localStorage.getItem("block");
  const transaction = localStorage.getItem("transaction");

  //  Acc data from last transaction
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "account_history_api.get_account_history",
        params: {
          account: username,
          start: -1,
          // limit: 10,
        },
        id: 1,
      },
    }).then((res) => setUser_profile_data(res?.data.result.history));
  }, [username]);
  // console.log(user_profile_data);
  ///////

  // axios({
  //   method: "post",
  //   url: "http://localhost:3000/rpc/get_account_history",
  //   data: {
  //     account: "enotom",
  //     start: -1,
  //   },
  // }).then((res) => setAcc(res));
  // }
  // console.log(acc);

  // get head block
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "database_api.get_dynamic_global_properties",
        id: 1,
      },
    }).then((res) => setHead_block(res?.data.result));
  }, []);
  const current_head_block = head_block.head_block_number;

  //get head block data
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
    }).then((res) => setHead_block_data(res?.data.result.block));
  }, [current_head_block]);

  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "block_api.get_block",
        params: { block_num: block },
        id: 1,
      },
    }).then((res) => setBlock_data(res?.data?.result?.block));
  }, [block]);
  /// Transaction Data
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "condenser_api.get_transaction",
        params: [transaction],
        id: 1,
      },
    }).then((res) => setTransData(res?.data.result));
  }, [transaction]);

  // Witnesses data

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
        head_block: head_block,
        head_block_data: head_block_data,
        setUserProfile: setUserProfile,
        setUser_profile_data: setUser_profile_data,
        userProfile: userProfile,
        user_profile_data: user_profile_data,
        block_data: block_data,
        transData: transData,
        witnessData: witnessData,
      }}
    >
      {children}
    </ApiContext.Provider>
  );
};
