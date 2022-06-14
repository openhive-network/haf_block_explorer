import React, { useContext, useEffect, useState } from "react";
import MainPage from "../../../pages/MainPage";
import BlockPage from "../../../pages/BlockPage";
import UserPage from "../../../pages/UserPage";
import TransactionPage from "../../../pages/TransactionPage";
import WitnessesPage from "../../../pages/WitnessesPage";
import { Routes, Route } from "react-router-dom";
import ErrorPage from "../../../pages/ErrorPage";
import { UserProfileContext } from "../../../contexts/userProfileContext";
import { BlockContext } from "../../../contexts/blockContext";
import { TranasctionContext } from "../../../contexts/transactionContext";
import { useLocation } from "react-router-dom";
import "./content.css";
export default function Content() {
  const { userProfile, setUserProfile } = useContext(UserProfileContext);
  const { blockNumber, setBlockNumber } = useContext(BlockContext);
  const { transactionId, setTransactionId } = useContext(TranasctionContext);

  let location = useLocation();
  const user = location.pathname.split("/user/").pop();
  const block = Number(location.pathname.split("/block/").pop());
  const transaction = location.pathname.split("/transaction/").pop();
  // console.log(location);
  const [title, setTitle] = useState("");
  document.title = title;
  useEffect(() => {
    setUserProfile(user);
    setBlockNumber(block);
    setTransactionId(transaction);
  }, [user, block, transaction]);

  return (
    <div className="content">
      <Routes>
        <Route exact path="/" element={<MainPage setTitle={setTitle} />} />
        <Route
          path={`block/${blockNumber}`}
          element={
            <BlockPage
              setBlockNumber={setBlockNumber}
              setTitle={setTitle}
              block_nr={blockNumber}
            />
          }
        />
        <Route
          path={`user/${userProfile}`}
          element={<UserPage setTitle={setTitle} user={userProfile} />}
        />
        <Route
          path={`transaction/${transactionId}`}
          element={
            <TransactionPage setTitle={setTitle} transaction={transactionId} />
          }
        />
        <Route
          path="witnesses"
          element={<WitnessesPage setTitle={setTitle} />}
        />
        <Route path="error" element={<ErrorPage setTitle={setTitle} />} />
      </Routes>
    </div>
  );
}
