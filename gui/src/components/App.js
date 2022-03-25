import { useContext, useState } from "react";
import "bootstrap/dist/css/bootstrap.min.css";
import MainPage from "../pages/MainPage";
import BlockPage from "../pages/BlockPage";
import UserPage from "../pages/UserPage";
import TransactionPage from "../pages/TransactionPage";
import WitnessesPage from "../pages/WitnessesPage";
import { Routes, Route } from "react-router-dom";
import { ApiContext } from "../context/apiContext";
import NavigationBar from "./NavigationBar";

function App() {
  const { setUserProfile, setBlockNumber, setTransactionId, blockNumber } =
    useContext(ApiContext);

  const user = window.location.href.split("/user/").pop();
  const block = Number(window.location.href.split("/block/").pop());
  const transaction = window.location.href.split("/transaction/").pop();

  setUserProfile(user);
  setBlockNumber(block);
  setTransactionId(transaction);

  return (
    <div className="App">
      <NavigationBar />
      <Routes>
        <Route exact path="/" element={<MainPage />} />
        <Route
          path={`block/${block}`}
          element={
            <BlockPage setBlockNumber={setBlockNumber} block_nr={block} />
          }
        />
        <Route path={`user/${user}`} element={<UserPage user={user} />} />
        <Route
          path={`transaction/${transaction}`}
          element={<TransactionPage transaction={transaction} />}
        />
        <Route path="witnesses" element={<WitnessesPage />} />
      </Routes>
    </div>
  );
}

export default App;
