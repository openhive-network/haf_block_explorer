import React from "react";
import ReactDOM from "react-dom";
import App from "./components/App";
import { UserProfileContextProvider } from "./contexts/userProfileContext";
import { HeadBlockContextProvider } from "./contexts/headBlockContext";
import { BlockContextProvider } from "./contexts/blockContext";
import { TranasctionContextProvider } from "./contexts/transactionContext";
import { WitnessContextProvider } from "./contexts/witnessContext";
import { BrowserRouter } from "react-router-dom";
import ErrorBoundary from "./components/ErrorBoundary";

ReactDOM.render(
  <React.StrictMode>
    <ErrorBoundary>
      <HeadBlockContextProvider>
        <UserProfileContextProvider>
          <BlockContextProvider>
            <TranasctionContextProvider>
              <WitnessContextProvider>
                <BrowserRouter>
                  <App />
                </BrowserRouter>
              </WitnessContextProvider>
            </TranasctionContextProvider>
          </BlockContextProvider>
        </UserProfileContextProvider>
      </HeadBlockContextProvider>
    </ErrorBoundary>
  </React.StrictMode>,
  document.getElementById("root")
);
