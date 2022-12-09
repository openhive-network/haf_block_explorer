import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const TranasctionContext = createContext();

export const TranasctionContextProvider = ({ children }) => {
  const [transData, setTransData] = useState(null);
  const [transactionId, setTransactionId] = useState("");

  useEffect(() => {
    if (transactionId) {
      axios({
        method: "post",
        url: `http://192.168.4.250:3000/rpc/get_transaction`,
        headers: { "Content-Type": "application/json" },
        data: { _trx_hash: transactionId },
      }).then((res) => setTransData(res?.data));
    }
    return () => setTransData(null);
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
