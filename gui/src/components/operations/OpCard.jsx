import React from "react";
import { Link } from "react-router-dom";
import { Toast, Row, Col } from "react-bootstrap";
import Operation from "./Operation";
export default function OpCard({ block, index, full_trx, trx_id }) {
  const is_trx_page = document.location.href.includes("transaction");

  const type =
    block?.operations?.type === undefined
      ? block.type.replaceAll("_", " ")
      : block.operations.type.replaceAll("_", " ");

  const link_to_trx = () => {
    if (block.trx_id !== null) {
      if (is_trx_page === false) {
        return (
          <Link
            style={{ color: "#fff", textDecoration: "none" }}
            to={`/transaction/${block.trx_id}`}
          >
            <p>
              Trx{" "}
              <span style={{ color: "#6af5ff" }}>
                {block.trx_id
                  ? block.trx_id?.slice(0, 10)
                  : trx_id.slice(0, 10)}
              </span>
            </p>
          </Link>
        );
      } else {
        return (
          <p>
            Trx{" "}
            <span style={{ color: "#6af5ff" }}>
              {block.trx_id ? block.trx_id?.slice(0, 10) : trx_id.slice(0, 10)}
            </span>
          </p>
        );
      }
    } else {
      return <p>Virtual operation</p>;
    }
  };

  // const link_to_block = (
  //   <Link
  //     style={{
  //       color: "#000",
  //       textDecoration: "none",
  //     }}
  //     to={`/block/${block.block}`}
  //   >
  //     Block {block.block}
  //   </Link>
  // );

  return (
    <>
      <Toast
        className="d-inline-block m-1 w-100"
        style={{ backgroundColor: "#2C3136" }}
        key={index}
      >
        <Toast.Body className="text-white">
          <Row>
            <Col className="d-flex justify-content-between">
              {link_to_trx()}
              <span style={{ fontWeight: "bold", color: "#fff351" }}>
                {type}
              </span>
              <small>
                {block?.timestamp
                  ? block?.timestamp
                  : "Expiration : " + full_trx?.expiration.split("T").join(" ")}
              </small>
            </Col>
          </Row>
          <Row>
            <Col className="text-center">
              <Operation
                value={
                  block?.operations?.type === undefined
                    ? block.type
                    : block.operations.type
                }
                type={
                  block?.operations === undefined ? block : block?.operations
                }
                full_trx={full_trx}
              />
            </Col>
          </Row>
        </Toast.Body>
      </Toast>
    </>
  );
}
