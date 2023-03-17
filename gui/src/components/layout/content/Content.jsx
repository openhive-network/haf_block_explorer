import React, { useContext, useEffect } from "react";
import MainPage from "../../../pages/mainPage/MainPage";
import BlockPage from "../../../pages/blockPage/BlockPage";
import UserPage from "../../../pages/userPage/UserPage";
import TransactionPage from "../../../pages/transactionPage/TransactionPage";
import WitnessesPage from "../../../pages/witnessPage/WitnessesPage";
import CommentsPage from "../../../pages/commentsPage/CommentsPage";
import { Routes, Route } from "react-router-dom";
import ErrorPage from "../../../pages/ErrorPage";
import { UserProfileContext } from "../../../contexts/userProfileContext";
import { BlockContext } from "../../../contexts/blockContext";
import { TranasctionContext } from "../../../contexts/transactionContext";
import { useLocation } from "react-router-dom";
import styles from "./content.module.css";
export default function Content() {
  const { userProfile, setUserProfile } = useContext(UserProfileContext);
  const { blockNumber, setBlockNumber } = useContext(BlockContext);
  const { transactionId, setTransactionId } = useContext(TranasctionContext);

  let location = useLocation();
  const user = location.pathname.split("/user/").pop();
  const block = Number(location.pathname.split("/block/").pop());
  const transaction = location.pathname.split("/transaction/").pop();
  useEffect(() => {
    if ((user && transaction) !== "/" && block !== "NaN") {
      if (location.pathname.includes("user")) {
        setUserProfile(user);
      }
      if (location.pathname.includes("block")) {
        setBlockNumber(block);
      }
      if (location.pathname.includes("transaction")) {
        setTransactionId(transaction);
      }
    }
  }, [
    user,
    block,
    location,
    transaction,
    setUserProfile,
    setBlockNumber,
    setTransactionId,
  ]);

  return (
    <div className={styles.content}>
      <Routes>
        <Route exact path="/" element={<MainPage />} />
        <Route
          path={blockNumber && `block/${blockNumber}`}
          element={
            <BlockPage setBlockNumber={setBlockNumber} block_nr={blockNumber} />
          }
        />
        <Route
          path={userProfile && `user/${userProfile}`}
          element={<UserPage user={userProfile} />}
        />
        <Route
          path={transactionId && `transaction/${transactionId}`}
          element={<TransactionPage transaction={transactionId} />}
        />
        <Route path="/comments" element={<CommentsPage />} />
        <Route path="witnesses" element={<WitnessesPage />} />
        <Route path="error" element={<ErrorPage />} />
      </Routes>
    </div>
  );
}
