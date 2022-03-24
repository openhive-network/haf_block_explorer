import React from "react";
import ReactDOM from "react-dom";
import App from "./components/App";
import { ApiContextProvider } from "./context/apiContext";
import { BrowserRouter } from "react-router-dom";

ReactDOM.render(
  <React.StrictMode>
    <ApiContextProvider>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </ApiContextProvider>
  </React.StrictMode>,
  document.getElementById("root")
);
