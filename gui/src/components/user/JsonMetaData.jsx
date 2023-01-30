import React from "react";
import styles from "./userStyles.module.css";
import HighlightedJSON from "../customJson/HighlightedJSON";

export default function JsonMetaData({ user_info }) {
  return (
    <>
      {user_info.length && user_info.json_metadata ? (
        <div className={styles.grayContainer}>
          <h3>JSON metadata</h3>
          <pre className={styles.jsonMetaData}>
            <HighlightedJSON json={user_info.json_metadata} />
          </pre>
        </div>
      ) : (
        ""
      )}
    </>
  );
}
