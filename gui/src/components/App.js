import "bootstrap/dist/css/bootstrap.min.css";

import { useContext, useState, useEffect } from "react";
import Header from "./layout/Header";
import Content from "./layout/Content";
// import Footer from "./layout/Footer";
import "../styles/App.css";

function App() {
  return (
    <div className="App">
      {isDataLoading ? (
        "Data loading"
      ) : (
        <>
          <Header />
          <Content />
          {/* <Footer /> */}
        </>
      )}
    </div>
  );
}

export default App;
