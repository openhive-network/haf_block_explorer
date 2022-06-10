import React from "react";
import "./loader.css";

export default function Loader() {
  return (
    <div className="gooey">
      <span className="dot"></span>
      <div className="dots">
        <span className="x1"></span>
        <span className="x1"></span>
        <span className="x1"></span>
      </div>
    </div>
  );
}
