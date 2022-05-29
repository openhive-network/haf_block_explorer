import React from "react";
import { Link } from "react-router-dom";
import { Toast } from "react-bootstrap";
import GetOperations from "../operations";

export default function OpCard({ block, index, full_trx }) {
  const type =
    block?.operations?.type === undefined
      ? block.type.replaceAll("_", " ")
      : block.operations.type.replaceAll("_", " ");
  const link_to_trx = (
    <Link
      style={{ color: "#000", textDecoration: "none" }}
      to={`/transaction/${block.trx_id}`}
    >
      {block.trx_id}
    </Link>
  );
  const link_to_block = (
    <Link
      style={{
        color: "#000",
        textDecoration: "none",
      }}
      to={`/block/${block.block}`}
    >
      {block.block}
    </Link>
  );
  return (
    <>
      {" "}
      <Toast
        className="d-inline-block m-1 w-100"
        style={{ backgroundColor: "#2C3136" }}
        key={index}
      >
        <Toast.Header style={{ color: "#2C3136" }} closeButton={false}>
          {/* <img src="holder.js/20x20?text=%20" className="rounded me-2" alt="" /> */}
          <strong className="me-auto">
            <p style={{ margin: "0" }}>
              ID {block.trx_id !== null ? link_to_trx : "no id"}
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

          <small>{block.timestamp} </small>
        </Toast.Header>
        <Toast.Body className="text-white">
          <GetOperations
            value={
              block?.operations?.type === undefined
                ? block.type
                : block.operations.type
            }
            type={block?.operations === undefined ? block : block?.operations}
            full_trx={full_trx}
          />
          {/* <HighlightedJSON json={single} /> */}
        </Toast.Body>
      </Toast>
    </>
  );
}
