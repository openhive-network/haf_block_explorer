import React from "react";

export default function Footer() {
  const current_year = new Date().getFullYear();
  return (
    <div className="footer">
      <p>HIVE Blocks &copy; {current_year} </p>
    </div>
  );
}
