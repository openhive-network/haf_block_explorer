import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const BlockContext = createContext();

export const BlockContextProvider = ({ children }) => {
  const [block_data, setBlock_data] = useState(null);
  const [blockNumber, setBlockNumber] = useState("");
  const [block_op_types, set_block_op_types] = useState(null);
  const [block_op_filters, set_block_op_filters] = useState([]);

  useEffect(() => {
    if (blockNumber) {
      axios({
        method: "post",
        url: `http://192.168.4.250:3000/rpc/get_block_op_types`,
        headers: { "Content-Type": "application/json" },
        data: {
          _block_num: blockNumber,
        },
      }).then((res) => set_block_op_types(res.data));
    }
    return () => set_block_op_types(null);
  }, [blockNumber]);

  useEffect(() => {
    if (blockNumber) {
      axios({
        method: "post",
        url: `http://192.168.4.250:3000/rpc/get_ops_by_block`,
        headers: { "Content-Type": "application/json" },
        data: {
          _block_num: blockNumber,
          _filter: block_op_filters,
        },
      }).then((res) => setBlock_data(res?.data.reverse()));
    }
    return setBlock_data(null);
  }, [blockNumber, block_op_filters]);

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
