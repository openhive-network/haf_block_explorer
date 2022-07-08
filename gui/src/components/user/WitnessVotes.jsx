import React from "react";
import styles from "./userStyles.module.css";

export default function WitnessVotes({ user_info }) {
  return (
    <>
      {user_info?.witness_votes?.length !== 0 ? (
        <div className={styles.grayContainer}>
          <h3>Witness Votes</h3>
          <ul>
            {user_info?.witness_votes?.map((w, i) => (
              <li key={i}>
                {i + 1}. <a href={`/user/${w}`}>{w}</a>
              </li>
            ))}
          </ul>
        </div>
      ) : (
        ""
      )}
    </>
  );
}
