import React from "react";
import styles from "./footer.module.css";

export default function Footer() {
  const current_year = new Date().getFullYear();
  return (
    <div className={styles.footer}>
      <p>HIVE Blocks &copy; {current_year} </p>
    </div>
  );
}
