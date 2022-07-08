import styles from "./loader.module.css";

export default function Loader() {
  return (
    <div className={styles.loader}>
      <div className={styles.gooey}>
        <span className={styles.dot}></span>
        <div className={styles.dots}>
          <span className={styles.x1}></span>
          <span className={styles.x1}></span>
          <span className={styles.x1}></span>
        </div>
      </div>
    </div>
  );
}
