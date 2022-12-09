import { useState, createContext, useEffect } from "react";
import axios from "axios";

export const WitnessContext = createContext();

export const WitnessContextProvider = ({ children }) => {
  const [witnessData, setWitnessData] = useState(null);
  const [witnessTableOrderBy, setWitnessTableOrderBy] = useState("rank");
  const [witnessOrderDescending, witnessSetOrderDescending] = useState(false);
  const [witnessLimit, setWitnessLimit] = useState(0);

  const cellOrder = {
    rank: "rank",
    witness: "witness",
    votes: "votes",
    voters: "voters_num",
    block_size: "block_size",
    price_feed: "price_feed",
    bias: "bias",
    feed_age: "feed_age",
    version: "version",
  };

  const handleOrderBy = (cell) => {
    setWitnessTableOrderBy(cellOrder[cell]);
    witnessSetOrderDescending(cell && !witnessOrderDescending);
  };

  useEffect(() => {
    axios({
      method: "post",
      url: `http://192.168.4.250:3000/rpc/get_witnesses`,
      headers: { "Content-Type": "application/json" },
      data: {
        _limit: 100,
        _offset: witnessLimit,
        _order_by: witnessTableOrderBy,
        _order_is: witnessOrderDescending ? "desc" : "asc",
      },
    }).then((res) => setWitnessData(res?.data));
    return () => setWitnessData(null);
  }, [witnessLimit, witnessTableOrderBy, witnessOrderDescending]);

  return (
    <WitnessContext.Provider
      value={{
        witnessData: witnessData,
        setWitnessData: setWitnessData,
        handleOrderBy: handleOrderBy,
        witnessTableOrderBy: witnessTableOrderBy,
        witnessOrderDescending: witnessOrderDescending,
        cellOrder: cellOrder,
        setWitnessLimit: setWitnessLimit,
        witnessLimit: witnessLimit,
      }}
    >
      {children}
    </WitnessContext.Provider>
  );
};
