import React from "react";
import { Link } from "react-router-dom";
import { Toast, Row, Col } from "react-bootstrap";
import Operation from "../operation/Operation";
import styles from "./opCard.module.css";

export default function OpCard({ block, full_trx, trx_id }) {
  const is_trx_page = document.location.href.includes("transaction");

  const type =
    block?.operations?.type === undefined
      ? block.type.replaceAll("_", " ")
      : block.operations.type.replaceAll("_", " ");

  const link_to_trx = () => {
    if (block.trx_id !== null) {
      if (is_trx_page === false) {
        return (
          <>
            <Link className={styles.link} to={`/transaction/${block.trx_id}`}>
              {block.trx_id ? block.trx_id?.slice(0, 10) : trx_id.slice(0, 10)}
            </Link>
          </>
        );
      } else {
        return (
          <p>
            {block.trx_id ? block.trx_id?.slice(0, 10) : trx_id.slice(0, 10)}
          </p>
        );
      }
    } else {
      return <p>Virtual operation</p>;
    }
  };
  const opTimestampMessage = (op) => {
    return (
      <div className={styles.timestamp}>
        <p>Created at: {op?.timestamp.split("T").join(" ")}</p>
        <p>Age: {op?.age}</p>
      </div>
    );
  };

  const trxTimestampMessage = (trx) => {
    return (
      <div className={styles.timestamp}>
        <p>Expiration: {trx.expiration.split("T").join(" ")}</p>
        <p>Age: {trx.age}</p>
      </div>
    );
  };
  return (
    <>
      <Toast className={`d-inline-block m-1 w-100 ${styles.toast}`}>
        <Toast.Body className="text-white">
          <Row>
            <Col className="d-flex justify-content-between">
              {link_to_trx()}
              <span className={styles.operationType}>{type}</span>
              <small>
                {block?.timestamp
                  ? opTimestampMessage(block)
                  : trxTimestampMessage(full_trx)}
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
