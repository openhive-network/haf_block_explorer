import React from "react";
import { Link } from "react-router-dom";

export default function ErrorPage({ setTitle }) {
  // setTitle("HAF | Error");
  return (
    <div>
      No data found. Please go to <Link to="/">home page</Link>
    </div>
  );
}
