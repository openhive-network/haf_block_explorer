import React, { useContext, useState } from "react";
import { BlockContext } from "../contexts/blockContext";
import { Card, Row, Col, Button, Toast } from "react-bootstrap";
import { useNavigate, Link } from "react-router-dom";
import GetOperations from "../operations";
import HighlightedJSON from "../components/HighlightedJSON";

export default function Block_Page({ block_nr, setTitle }) {
  const { block_data, setBlockNumber, blockNumber } = useContext(BlockContext);
  const trx = block_data;
  // setTitle(`HAF | Block | ${block_nr}`);
  console.log(trx);
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
    <>
      {trx === null ? (
        <h1>Loading...</h1>
      ) : (
        <div>
          <Button onClick={handlePreviousBlock}>{"<"}</Button>
          <Button onClick={handleNextBlock}>{">"}</Button>
          <p>Block number : {block_nr} </p>
          <p> Block transactions count : {trx?.length}</p>

          {trx?.length === 0 ? (
            <h1>No transactions for this block</h1>
          ) : (
            trx?.map((single, i) => {
              const trxToJson = JSON.stringify(single, null, 2);
              const type = single.operations.type.replaceAll("_", " ");
              const link_to_trx = (
                <Link
                  style={{ color: "#000", textDecoration: "none" }}
                  to={`/transaction/${single.trx_id}`}
                >
                  {single.trx_id}
                </Link>
              );
              const link_to_block = (
                <Link
                  style={{
                    color: "#000",
                    textDecoration: "none",
                  }}
                  to={`/block/${single.block}`}
                >
                  {single.block}
                </Link>
              );
              return (
                <Row key={single.signatures} className="justify-content-center">
                  <Col sm={8}>
                    <Toast
                      className="d-inline-block m-1 w-100"
                      style={{ backgroundColor: "#091B4B" }}
                      key={i}
                    >
                      <Toast.Header
                        style={{ color: "#091B4B" }}
                        closeButton={false}
                      >
                        <img
                          src="holder.js/20x20?text=%20"
                          className="rounded me-2"
                          alt=""
                        />
                        <strong className="me-auto">
                          <p style={{ margin: "0" }}>
                            ID {single.trx_id !== null ? link_to_trx : "none"}
                          </p>
                          <p style={{ margin: "0" }}>Block {link_to_block}</p>
                        </strong>
                        <strong className="me-auto">
                          <p
                            style={{
                              fontSize: "20px",
                              textTransform: "capitalize",
                            }}
                          >
                            {type}
                          </p>
                        </strong>

                        <small>{single.timestamp} </small>
                      </Toast.Header>
                      <Toast.Body className="text-white">
                        <GetOperations
                          value={single.operations.type}
                          type={single.operations}
                        />
                        <HighlightedJSON json={single} />
                      </Toast.Body>
                    </Toast>
                  </Col>
                </Row>
              );
            })
          )}
        </div>
      )}
    </>
  );
}
