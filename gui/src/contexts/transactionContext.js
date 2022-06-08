import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const TranasctionContext = createContext();

export const TranasctionContextProvider = ({ children }) => {
  const [transData, setTransData] = useState(null);
  const [transactionId, setTransactionId] = useState("");
  // 192.168.5.118 -steem7
  // 192.168.4.250 -steem10
  /// Get transaction Data
  useEffect(() => {
    if (transactionId !== "") {
      axios({
        method: "post",
        url: "http://192.168.4.250:3002/rpc/get_transaction",
        headers: { "Content-Type": "application/json" },
        data: { _trx_hash: transactionId },
      }).then((res) => setTransData(res?.data));
    }
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
