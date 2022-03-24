import React, { useContext } from "react";
import { ApiContext } from "../context/apiContext";
import { Card, Row, Col } from "react-bootstrap";

export default function Block_Page({ block_nr }) {
  const { block_data } = useContext(ApiContext);

  const trx = block_data.transactions;

  return (
    <div>
      <p>Block number : {block_nr} </p>
      <p> Block transactions count : {trx?.length}</p>
      {trx?.length === 0 ? (
        <h1>No transactions for this block</h1>
      ) : (
        trx?.map((single) => {
          const trxToJson = JSON.stringify(single, null, 2);
          return (
            <Row className="justify-content-center">
              <Col xs={6}>
                <Card>
                  <pre>{trxToJson}</pre>
                </Card>
              </Col>
            </Row>
          );
        })
      )}
    </div>
  );
}
