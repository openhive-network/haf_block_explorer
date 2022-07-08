import React from "react";
import styles from "./customJson.module.css";

export default function HighlightedJSON({ json }) {
  const highlightedJSON = (jsonObj) => {
    return Object.keys(jsonObj).map((key, i) => {
      const value = jsonObj[key];
      let valueType = typeof value;
      const isSimpleValue =
        ["string", "number", "boolean"].includes(valueType) || !value;
      if (isSimpleValue && valueType === "object") {
        valueType = "null";
      }
      return (
        <div key={key} className={styles.line}>
          <span className={styles.key}>{key === "json" ? "" : key}:</span>
          {isSimpleValue ? (
            <span className={styles[`${valueType}`]}>{value}</span>
          ) : (
            highlightedJSON(value)
          )}
        </div>
      );
    });
  };

  return <div>{highlightedJSON(json)}</div>;
}
