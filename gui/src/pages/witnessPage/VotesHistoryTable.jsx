import React from "react";
import styles from "./witnessTable.module.css";
import Loader from "../../components/loader/Loader";
const CELLS = ["date", "name", "hp", "account hp", "proxied hp"];

export default function VotesHistoryTable({
  isVotesHistoryTableOpen,
  setIsVotesHistoryTableOpen,
  witnessVotersList,
  handleOrderBy,
  arrowPosition,
  linkToUserProfile,
  orderBy,
}) {
  const dateString = (date) => {
    return new Date(date).toDateString();
  };

  const isVoterrsHistoryLoaded =
    isVotesHistoryTableOpen && witnessVotersList && orderBy !== null;
  const stylesButtonInherit = {
    background: "inherit",
    border: "none",
    color: "#fff",
  };

  return (
    <div hidden={!isVotesHistoryTableOpen} className={styles.modal}>
      <div className={styles["modal-content"]}>
        {!isVoterrsHistoryLoaded ? (
          <Loader />
        ) : (
          <>
            <div className={styles["modal-header"]}>
              <h2>Votes History</h2>
              <span>
                <button
                  style={{ background: "inherit", border: "none" }}
                  onClick={() => setIsVotesHistoryTableOpen(false)}
                  className={styles.close}
                >
                  &times;
                </button>
              </span>
            </div>

            <table style={{ width: "100%" }}>
              <thead>
                <tr style={{ fontSize: "20px", fontWeight: "bold" }}>
                  {CELLS.map((cell, i) => (
                    <th key={i}>
                      {cell.toUpperCase()}
                      <button
                        onClick={() => handleOrderBy(cell)}
                        style={stylesButtonInherit}
                      >
                        {arrowPosition(cell)}
                      </button>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {witnessVotersList?.map((witness) => (
                  <tr
                    key={witness.account}
                    style={{ fontSize: "16px", fontWeight: "light" }}
                  >
                    <td>{dateString(witness.timestamp)}</td>
                    <td>{linkToUserProfile(witness.account)}</td>
                    <td>{witness.hive_power.toFixed(2)}</td>
                    <td>{witness.account_hive_power.toFixed(2)}</td>
                    <td>{witness.proxied_hive_power.toFixed(2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </div>
    </div>
  );
}
