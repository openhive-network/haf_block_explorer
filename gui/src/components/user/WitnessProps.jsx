import React from "react";
import styles from "./userStyles.module.css";
import UserInfoTable from "./userTable/UserInfoTable";

export default function WitnessProps({ user_witness, user_info }) {
  return (
    <>
      {user_info?.posting_json_metadata && user_witness?.length ? (
        <div className={styles.grayContainer}>
          <h3>Witness Properties</h3>
          <UserInfoTable user_info={user_witness?.[0]} />
        </div>
      ) : (
        ""
      )}
    </>
  );
}
