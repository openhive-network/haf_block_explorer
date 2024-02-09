import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const BlockContext = createContext();

export const BlockContextProvider = ({ children }) => {
  const [block_data, setBlock_data] = useState(null);
  const [blockNumber, setBlockNumber] = useState("");
  const [block_op_types, set_block_op_types] = useState(null);
  const [block_op_filters, set_block_op_filters] = useState([]);

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
  // 192.168.5.118 -steem7
  // // 192.168.4.250 -steem10
  // 192.168.5.126 shed14
  // getBlockData
  // console.log(block_data);
  useEffect(() => {
    if (blockNumber !== "") {
      axios({
        method: "post",
        url: "http://192.168.5.126:3002/rpc/get_block_op_types",
        headers: { "Content-Type": "application/json" },
        data: {
          _block_num: blockNumber,
        },
      }).then((res) => set_block_op_types(res.data));
    }
  }, [blockNumber, set_block_op_types]);

  useEffect(() => {
    if (blockNumber !== "") {
      axios({
        method: "post",
        url: "http://192.168.5.126:3002/rpc/get_ops_by_block_paging",
        headers: { "Content-Type": "application/json" },
        data: {
          _block_num: blockNumber,
          _filter: block_op_filters,
        },
      }).then((res) => setBlock_data(res?.data.reverse()));
    }
  }, [blockNumber, block_op_filters, setBlock_data]);

  return (
    <BlockContext.Provider
      value={{
        block_data: block_data,
        blockNumber: blockNumber,
        setBlockNumber: setBlockNumber,
        block_op_types: block_op_types,
        set_block_op_types: set_block_op_types,
        block_op_filters: block_op_filters,
        set_block_op_filters: set_block_op_filters,
      }}
    >
      {children}
    </BlockContext.Provider>
  );
};
