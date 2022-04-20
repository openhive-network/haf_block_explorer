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
      {isDataLoading ? (
        "Data loading"
      ) : (
        <>
          <Header />
          <Content />
          <Footer />
        </>
      )}
    </div>
  );
}

export default App;
