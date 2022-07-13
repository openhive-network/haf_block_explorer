import React from "react";
import { votersDummy } from "../../witness_voters";
import styles from "./witnessTable.module.css";

const CELLS = ["Date", "Name", "Vests", "Account", "Proxied"];

export default function VotesHistoryTable({
  isVotesHistoryTableOpen,
  setIsVotesHistoryTableOpen,
}) {
  return (
    <div
      onClick={() => setIsVotesHistoryTableOpen(false)}
      hidden={!isVotesHistoryTableOpen}
      className={styles.modal}
    >
      <div className={styles["modal-content"]}>
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
                <th key={i}>{cell}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {votersDummy.map((voter) => (
              <tr
                key={voter.voter_id}
                style={{ fontSize: "16px", fontWeight: "light" }}
              >
                <td>{new Date().toISOString().split("T")[0]}</td>
                <td>{voter.voter_id}</td>
                <td>{voter.vests}</td>
                <td>{voter.account_vests}</td>
                <td>{voter.proxied_vests}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
