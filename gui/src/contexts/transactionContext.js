import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const TranasctionContext = createContext();

export const TranasctionContextProvider = ({ children }) => {
  const [transData, setTransData] = useState([]);
  const [transactionId, setTransactionId] = useState("");

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
