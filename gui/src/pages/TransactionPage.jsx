import React, { useContext, useEffect, useState } from "react";
import { Card, Row, Col } from "react-bootstrap";
import HighlightedJSON from "../components/HighlightedJSON";
import { TranasctionContext } from "../contexts/transactionContext";

export default function Transaction_Page({ transaction, setTitle }) {
  // setTitle(`HAF | Transaction`);
  const { transData } = useContext(TranasctionContext);
  // const trnasToJson = JSON.stringify(transData, null, 2);

  // const [seconds, setSeconds] = useState(60);

  // const timeout = setTimeout(() => {
  //   setSeconds(seconds - 1);
  // }, 1000);

  // if (seconds <= 0) {
  //   clearTimeout(timeout);
  //   window.location.reload();
  // }

  return (
    <div>
      <h1>Transaction Page</h1> <h4>Transaction ID : {transaction}</h4>
      {/* {transData === undefined ? (
        <p>Transaction will be shown in : {seconds} </p>
      ) : ( */}
      <Row className="mt-5">
        <Col className="d-flex justify-content-center">
          {!transData ? (
            "No data"
          ) : (
            <div
              style={{
                width: "50vw",
                height: "60vh",
                wordBreak: "break-word",
                whiteSpace: "pre-wrap",
                overflow: "auto",
                background: "#dfdfdf",
                borderRadius: "25px",
                padding: "20px",
              }}
              className="transaction__json"
            >
              <HighlightedJSON json={transData} />
            </div>
          )}
        </Col>
      </Row>
      {/* )} */}
    </div>
  );
}
