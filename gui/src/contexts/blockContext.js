import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const BlockContext = createContext();

export const BlockContextProvider = ({ children }) => {
  const [block_data, setBlock_data] = useState(null);
  const [blockNumber, setBlockNumber] = useState("");

  // Get current block data
  // useEffect(() => {
  //   axios({
  //     method: "post",
  //     url: "https://api.hive.blog",
  //     data: {
  //       jsonrpc: "2.0",
  //       method: "block_api.get_block",
  //       params: { block_num: blockNumber },
  //       id: 1,
  //     },
  //   }).then((res) => setBlock_data(res?.data?.result?.block));
  // }, [blockNumber]);

  // getBlockData 
  useEffect(() => {
    if (blockNumber !== "") {
      axios({
        method: "post",
        url: "http://192.168.5.118:3002/rpc/get_ops_by_block",
        headers: { "Content-Type": "application/json" },
        data: {
          _block_num: blockNumber,
          _filter: [],
        },
      }).then((res) => setBlock_data(res?.data.reverse()));
    }
  }, [blockNumber]);

  return (
    <BlockContext.Provider
      value={{
        block_data: block_data,
        blockNumber: blockNumber,
        setBlockNumber: setBlockNumber,
      }}
    >
      {children}
    </BlockContext.Provider>
  );
};
