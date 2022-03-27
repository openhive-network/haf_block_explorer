import React, { useContext, useEffect, useState } from "react";
import { ApiContext } from "../context/apiContext";
import { Card, Row, Col } from "react-bootstrap";

export default function Transaction_Page({ transaction }) {
  const { transData } = useContext(ApiContext);
  const trnasToJson = JSON.stringify(transData, null, 2);

  const [seconds, setSeconds] = useState(60);

  const timeout = setTimeout(() => {
    setSeconds(seconds - 1);
  }, 1000);

  if (seconds <= 0) {
    clearTimeout(timeout);
    window.location.reload();
  }

  return (
    <div>
      <h1>Transaction Page</h1> <h4>Transaction ID : {transaction}</h4>
      {transData === undefined ? (
        <p>Transaction will be shown in : {seconds} </p>
      ) : (
        <Row className="justify-content-center mt-5">
          <Col xs={6}>
            <Card>
              <pre>{trnasToJson}</pre>
            </Card>
          </Col>
        </Row>
      )}
    </div>
  );
}
