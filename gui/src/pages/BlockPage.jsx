import React, { useContext, useState } from "react";
import { ApiContext } from "../context/apiContext";
import { Card, Row, Col } from "react-bootstrap";

export default function Block_Page({ block_nr, setTitle }) {
  const { block_data } = useContext(ApiContext);
  const trx = block_data?.transactions;
  setTitle(`HAF | Block | ${block_nr}`);
  //TO DO block counter

  // const [count, setCount] = useState(block_nr);
  // const handleNextBlock = () => {
    // setCount(count + 1);
    // setBlockNumber(block_nr + 1);
  // };
  // const handlePreviousBlock = () => {
  //   // setCount(count - 1);
  //   setBlockNumber(block_nr - 1);
  // };
console.log(block_data);
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
            <Row key={single.signatures} className="justify-content-center">
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
