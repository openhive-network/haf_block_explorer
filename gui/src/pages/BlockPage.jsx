import React, { useContext, useState } from "react";
import { BlockContext } from "../contexts/blockContext";
import { Card, Row, Col, Button } from "react-bootstrap";
import { useNavigate } from "react-router-dom";

export default function Block_Page({ block_nr, setTitle }) {
  const { block_data, setBlockNumber, blockNumber } = useContext(BlockContext);
  const trx = block_data?.transactions;
  // setTitle(`HAF | Block | ${block_nr}`);
  //Block counter
  const navigate = useNavigate();

  const handleNextBlock = () => {
    navigate(`/block/${blockNumber + 1}`);
    setBlockNumber(blockNumber + 1);
  };
  const handlePreviousBlock = () => {
    navigate(`/block/${blockNumber - 1}`);
    setBlockNumber(blockNumber - 1);
  };
  return (
    <div>
      <Button onClick={handlePreviousBlock}>{"<"}</Button>
      <Button onClick={handleNextBlock}>{">"}</Button>
      <p>Block number : {block_nr} </p>
      <p> Block transactions count : {trx?.length}</p>
      <p>Time : {block_data?.timestamp}</p>
      <p>Witness : {block_data?.witness}</p>
      {trx?.length === 0 ? (
        <h1>No transactions for this block</h1>
      ) : (
        trx?.map((single, i) => {
          const trxToJson = JSON.stringify(single, null, 2);

          return (
            <Row key={single.signatures} className="justify-content-center">
              <Col xs={6}>
                <Card>
                  <p>ID : {block_data.transaction_ids[i]}</p>
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
