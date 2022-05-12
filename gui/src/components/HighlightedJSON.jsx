import React from "react";

export default function HighlightedJSON({ json, showJson }) {
  // const highlightedJSON = (jsonObj) =>
  //   Object.keys(jsonObj).map((key, i) => {
  //     const value = jsonObj[key];
  //     let valueType = typeof value;
  //     const isSimpleValue =
  //       ["string", "number", "boolean"].includes(valueType) || !value;
  //     if (isSimpleValue && valueType === "object") {
  //       valueType = "null";
  //     }
  //     return (
  //       <div key={key} className="line">
  //         <span className="key">{key === "json" ? "" : key}:</span>
  //         {isSimpleValue ? (
  //           <span className={valueType}>{value}</span>
  //         ) : (
  //           highlightedJSON(value)
  //         )}
  //       </div>
  //     );
  //   });

  // return <div className="json">{highlightedJSON(json)}</div>;
  const pretty_json = JSON.stringify(json, null, 2);
  return (
    <div hidden={showJson}>
      <pre style={{ color: "#fcf823" }}>{pretty_json}</pre>
    </div>
  );
}
