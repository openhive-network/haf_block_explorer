import "bootstrap/dist/css/bootstrap.min.css";
import { useContext, useState, useEffect, useDebugValue } from "react";
import Header from "./layout/Header";
import Content from "./layout/Content";
import Footer from "./layout/Footer";
import "../styles/App.css";
import { ApiContext } from "../context/apiContext";
function App() {
  const { head_block_data } = useContext(ApiContext);

  // For head block (main page) only
  const isDataLoading =
    head_block_data?.transaction_ids?.length === 0 ||
    head_block_data?.transaction_ids?.length == undefined;

  return (
    <div className="App">
      <NavigationBar />

      <Routes>
        <Route exact path="/" element={<MainPage setTitle={setTitle} />} />
        <Route
          path={`block/${block}`}
          element={
            <BlockPage
              setBlockNumber={setBlockNumber}
              setTitle={setTitle}
              block_nr={blockNumber}
            />
          }
        />
        <Route
          path={`user/${user}`}
          element={<UserPage setTitle={setTitle} user={user} />}
        />
        <Route
          path={`transaction/${transaction}`}
          element={
            <TransactionPage setTitle={setTitle} transaction={transaction} />
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

export default App;
