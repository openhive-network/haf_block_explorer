import React from "react";
import ReactDOM from "react-dom";
import App from "./components/App";
import { ApiContextProvider } from "./context/apiContext";
import { BrowserRouter } from "react-router-dom";
import ErrorBoundary from "./components/ErrorBoundary";

ReactDOM.render(
  <ErrorBoundary>
    <ApiContextProvider>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </ApiContextProvider>
  </ErrorBoundary>,
  document.getElementById("root")
);
