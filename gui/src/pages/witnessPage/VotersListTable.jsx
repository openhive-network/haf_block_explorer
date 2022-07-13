import React from "react";
import { votersDummy } from "../../witness_voters";
import styles from "./witnessTable.module.css";

const CELLS = ["Name", "Vests", "Account", "Proxied"];

export default function VotersListTable({
  isVotersListTable,
  setIsVotersListTable,
}) {
  return (
    <div
      onClick={() => setIsVotersListTable(false)}
      hidden={!isVotersListTable}
      className={styles.modal}
    >
      <div className={styles["modal-content"]}>
        <div className={styles["modal-header"]}>
          <h2>Voters list</h2>
          <span>
            <button
              style={{ background: "inherit", border: "none" }}
              onClick={() => setIsVotersListTable(false)}
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
