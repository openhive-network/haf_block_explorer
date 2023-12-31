import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const WitnessContext = createContext();

export const WitnessContextProvider = ({ children }) => {
  const [witnessData, setWitnessData] = useState(null);

  // Get witnesses data
  useEffect(() => {
    axios({
      method: "post",
      url: "https://api.hive.blog",
      data: {
        jsonrpc: "2.0",
        method: "condenser_api.get_witnesses_by_vote",
        params: [null, 100],
        id: 1,
      },
    }).then((res) => setWitnessData(res?.data?.result));
  }, []);
  return (
    <WitnessContext.Provider
      value={{ witnessData: witnessData, setWitnessData: setWitnessData }}
    >
      {children}
    </WitnessContext.Provider>
  );
};
