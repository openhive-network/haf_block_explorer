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
  <ErrorBoundary>
    <HeadBlockContextProvider>
      <BlockContextProvider>
        <UserProfileContextProvider>
          <TranasctionContextProvider>
            <WitnessContextProvider>
              <BrowserRouter>
                <App />
              </BrowserRouter>
            </WitnessContextProvider>
          </TranasctionContextProvider>
        </UserProfileContextProvider>
      </BlockContextProvider>
    </HeadBlockContextProvider>
  </ErrorBoundary>,
  document.getElementById("root")
);
