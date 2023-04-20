import React from "react";
import { Link } from "react-router-dom";
import { Toast, Row, Col } from "react-bootstrap";
import Operation from "../operation/Operation";
import styles from "./opCard.module.css";
import { operationCardColors } from "./operationCardColors";

export default function OpCard({ block, full_trx, trx_id }) {
  const type =
    block?.operations?.type === undefined
      ? block.type.replaceAll("_", " ")
      : block.operations.type.replaceAll("_", " ");

  const linkToTrx = (() => {
    return (
      <Link
        className={styles.link}
        to={`/transaction/${block.trx_id || trx_id}`}
        target="_blank"
      >
        {block.trx_id ? block.trx_id?.slice(0, 10) : trx_id?.slice(0, 10)}
      </Link>
    );
  })();

  const linkToBlock = (() => {
    return (
      <Link
        className={styles.link}
        to={`/block/${block.block || full_trx.block_num}`}
        target="_blank"
      >
        {block.block || full_trx.block_num}
      </Link>
    );
  })();

  const links = (() => {
    if (block.trx_id !== null) {
      return (
        <div className={styles.links}>
          <p>Trx {linkToTrx}</p>
          <p>Block {linkToBlock}</p>
        </div>
      );
    } else {
      return (
        <div className={styles.links}>
          <p>Virtual operation</p>
          <p>Block {linkToBlock}</p>
        </div>
      );
    }
  })();

  const opTimestampMessage = (op) => {
    return (
      <div className={styles.timestamp}>
        <p> {op?.timestamp.split("T").join(" ")}</p>
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

  const operationValue = (() => {
    if (block?.operations?.type === undefined) {
      return block.type;
    } else {
      return block.operations.type;
    }
  })();

  const operationType = (() => {
    if (block?.operations === undefined) {
      return block;
    } else {
      return block.operations;
    }
  })();

  const cardBodyColor = operationCardColors[operationValue]?.bodyColor;
  const cardFontColor = operationCardColors[operationValue]?.fontColor;

  const isTransactionPage = document.location.href.includes("transaction");

  return (
    <>
      <Toast
        style={{ background: cardBodyColor, color: cardFontColor }}
        className={`d-inline-block m-1 w-100 ${
          isTransactionPage ? styles.trx_toast : styles.toast
        }`}
      >
        <Toast.Body className="text-white">
          <Row>
            <Col className="d-flex justify-content-between">
              {links}
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
                value={operationValue}
                type={operationType}
                full_trx={full_trx}
              />
            </Col>
          </Row>
        </Toast.Body>
      </Toast>
    </>
  );
}
