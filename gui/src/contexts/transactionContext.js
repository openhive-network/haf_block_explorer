import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const TranasctionContext = createContext();

export const TranasctionContextProvider = ({ children }) => {
  const [transData, setTransData] = useState([]);
  const [transactionId, setTransactionId] = useState("");

  /// Get transaction Data
  useEffect(() => {
    // axios({
    //   method: "post",
    //   url: "https://api.hive.blog",
    //   data: {
    //     jsonrpc: "2.0",
    //     method: "account_history_api.get_transaction",
    //     params: { id: transactionId, include_reversible: true },
    //     id: 1,
    //   },
    axios({
      method: "post",
      url: "http://192.168.5.118:3002/rpc/get_transaction",
      headers: { "Content-Type": "application/json" },
      data: { _trx_hash: transactionId },
    }).then((res) => setTransData(res?.data));
  }, [transactionId]);

  return (
    <TranasctionContext.Provider
      value={{
        transData: transData,
        setTransData: setTransData,
        transactionId: transactionId,
        setTransactionId: setTransactionId,
      }}
    >
      {children}
    </TranasctionContext.Provider>
  );
};
