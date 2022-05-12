import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const HeadBlockContext = createContext();
export const HeadBlockContextProvider = ({ children }) => {
  const [head_block, setHead_block] = useState("");
  const [head_block_data, setHead_block_data] = useState([]);
  //   Get head block number
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

  const current_head_block = head_block?.head_block_number;

  //Get head block data
  useEffect(() => {
    axios({
      method: "post",
      url: "http://192.168.5.118:3002/rpc/get_ops_by_block",
      headers: { "Content-Type": "application/json" },
      data: {
        _block_num: current_head_block,
        _filter: [],
      },
    }).then((res) => setHead_block_data(res?.data));
  }, [current_head_block]);

  return (
    <HeadBlockContext.Provider
      value={{
        head_block: head_block,
        head_block_data: head_block_data,
      }}
    >
      {children}
    </HeadBlockContext.Provider>
  );
};
