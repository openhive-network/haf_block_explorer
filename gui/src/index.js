import React from "react";
import ReactDOM from "react-dom";
import App from "./components/App";
import { ApiContextProvider } from "./context/apiContext";
import { BrowserRouter } from "react-router-dom";

ReactDOM.render(
  <ApiContextProvider>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </ApiContextProvider>,
  document.getElementById("root")
);
