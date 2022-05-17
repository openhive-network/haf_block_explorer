import React, { useContext, useEffect, useState } from "react";
import { Card, Row, Col, Toast } from "react-bootstrap";
import { Link } from "react-router-dom";
import HighlightedJSON from "../components/HighlightedJSON";
import { TranasctionContext } from "../contexts/transactionContext";
import GetOperations from "../operations";

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

  console.log(transData?.operations?.map((op) => op.type));
  // console.log(transData.operations);
  // const type = profile.operations.map((op) => op.type.replaceAll("_", " "));
  // const link_to_trx = (
  //   <Link
  //     style={{ color: "#000", textDecoration: "none" }}
  //     to={`/transaction/${transData.trx_id}`}
  //   >
  //     {transData.acc_operation_id}
  //   </Link>
  // );
  // const link_to_block = (
  //   <Link
  //     style={{
  //       color: "#000",
  //       textDecoration: "none",
  //     }}
  //     to={`/block/${transData.block}`}
  //   >
  //     {transData.block}
  //   </Link>
  // );
  return (
    <div>
      <h1>Transaction Page</h1> <h4>Transaction ID : {transaction}</h4>
      {/* {transData === undefined ? (
        <p>Transaction will be shown in : {seconds} </p>
      ) : ( */}
      <Row className="mt-5 justify-content-center">
        <Col sm={6}>
          {transData?.operations?.map((op, i) => {
            const type = op.type.replaceAll("_", " ");

            const link_to_trx = (
              <Link
                style={{ color: "#000", textDecoration: "none" }}
                to={`/transaction/${op.transaction_id}`}
              >
                {transData.transaction_id}
              </Link>
            );
            const link_to_block = (
              <Link
                style={{
                  color: "#000",
                  textDecoration: "none",
                }}
                to={`/block/${op.block_num}`}
              >
                {transData.block_num}
              </Link>
            );
            return (
              <Toast
                className="d-inline-block m-1 w-100"
                style={{ backgroundColor: "#091B4B" }}
                key={i}
              >
                <Toast.Header style={{ color: "#091B4B" }} closeButton={false}>
                  <img
                    src="holder.js/20x20?text=%20"
                    className="rounded me-2"
                    alt=""
                  />
                  <strong className="me-auto">
                    <p style={{ margin: "0" }}>ID {link_to_trx}</p>
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

                  <small>{op.timestamp} </small>
                </Toast.Header>
                <Toast.Body className="text-white">
                  <GetOperations value={op.type} type={op} />
                </Toast.Body>
              </Toast>
            );
          })}
        </Col>
      </Row>
      <Row className="mt-5 justify-content-center">
        {/* {transData?.operations?.map((op) => {
          // console.log(op.value);
          return <GetOperations value={op?.type} type={op} />;
        })} */}

        <Col sm={6}>
          {!transData ? (
            "No data"
          ) : (
            <div
              style={{
                // width: "50vw",
                height: "60vh",
                wordBreak: "break-word",
                whiteSpace: "pre-wrap",
                overflow: "auto",
                background: "#091B4B",
                borderRadius: "25px",
                padding: "20px",
              }}
              className="transaction__json"
            >
              {/* {transData?.operations.map((op) => (
               
              ))}
              <Toast
                className="d-inline-block m-1 w-100"
                style={{ backgroundColor: "#091B4B" }}
                key={i}
              >
                <Toast.Header style={{ color: "#091B4B" }} closeButton={false}>
                  <img
                    src="holder.js/20x20?text=%20"
                    className="rounded me-2"
                    alt=""
                  />
                  <strong className="me-auto">
                    <p style={{ margin: "0" }}>
                      ID {transData.trx_id !== null ? link_to_trx : "none"}
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

                  <small>{transData.timestamp} </small>
                </Toast.Header>
                <Toast.Body className="text-white">
                  <GetOperations value={single.operations.type} type={single} />
                  <HighlightedJSON json={single} />
                </Toast.Body>
              </Toast> */}

              <HighlightedJSON json={transData} />
            </div>
          )}
        </Col>
      </Row>
      {/* )} */}
    </div>
  );
}
