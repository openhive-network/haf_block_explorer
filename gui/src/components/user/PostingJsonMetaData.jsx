import React from "react";
import HighlightedJSON from "../customJson/HighlightedJSON";
import styles from "./userStyles.module.css";

export default function PostingJsonMetaData({ user_info }) {
  return (
    <>
      {user_info?.posting_json_metadata ? (
        <div className={styles.grayContainer}>
          <h3>Posting JSON metadata</h3>
          <pre className={styles.jsonMetaData}>
            <HighlightedJSON json={user_info?.posting_json_metadata} />
          </pre>
        </div>
      ) : (
        ""
      )}
    </>
  );
}
