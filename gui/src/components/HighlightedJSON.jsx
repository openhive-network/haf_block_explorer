import React from "react";
import JSONPretty from "react-json-pretty";
import "react-json-pretty/themes/monikai.css";

export default function HighlightedJSON({ json, showJson }) {
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
        <div key={key} className="line">
          <span className="key">{key === "json" ? "" : key}:</span>
          {isSimpleValue ? (
            <span className={valueType}>{value}</span>
          ) : (
            highlightedJSON(value)
          )}
        </div>
      );
    });
  };
  // return <div className="json">{highlightedJSON(json)}</div>;
  // const pretty_json = JSON?.stringify(json, 2, 2);

  // return <div>{highlightedJSON(json)}</div>;

  return <div>{highlightedJSON(json)}</div>;
}
