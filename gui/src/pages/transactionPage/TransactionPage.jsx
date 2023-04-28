import React, { useContext, useEffect } from "react";
import { Container, Row, Col, Card } from "react-bootstrap";
import { Typography } from "@mui/material";
import { TranasctionContext } from "../../contexts/transactionContext";
import { BlockContext } from "../../contexts/blockContext";
import OpCard from "../../components/operations/operationCard/OpCard";
import Loader from "../../components/loader/Loader";
import { tidyNumber } from "../../functions/calculations";
import styles from "./transactionPage.module.css";
import HighlightedJSON from "../../components/customJson/HighlightedJSON";

export default function Transaction_Page({ transaction }) {
  document.title = `HAF | Transaction ${transaction}`;
  const { transData } = useContext(TranasctionContext);
  const { block_data, setBlockNumber } = useContext(BlockContext);
  useEffect(() => {
    if (transData || transData !== null) {
      setBlockNumber(transData?.block_num);
    }
  }, [transData, setBlockNumber]);
  const block_time = block_data?.[0]?.timestamp;

  const keys = transData && Object.keys(transData);

  const renderOperations = (operations) => {
    if (operations) {
      return operations?.map((operation) => (
        <Row
          style={{
            textAlign: "start",
            margin: "20px 0",
          }}
        >
          <Typography variant="h5" align="center" sx={{ color: "#ffac33" }}>
            {operation.type}
          </Typography>
          <HighlightedJSON json={operation.value} />
        </Row>
      ));
    }
  };

  const renderRawTransaction = (k) => {
    const renderKey = (data) => {
      return data;
    };
    if (k !== "operations") {
      if (typeof transData?.[k] != "string") {
        return JSON.stringify(transData?.[k]);
      } else {
        return renderKey(transData[k]);
      }
    }
  };
  return (
    <>
      {!transData ||
      transData === null ||
      block_data === null ||
      block_data.length === 0 ? (
        <Loader />
      ) : (
        <Container className={styles.container}>
          <Typography className={styles.text}>
            Transaction <span className={styles.number}>{transaction}</span>{" "}
            <br></br>
            Included in block{" "}
            <span className={styles.number}>
              {tidyNumber(transData?.block_num)}{" "}
            </span>
            at <span className={styles.number}>{block_time} UTC</span>
          </Typography>

          <Row className={styles.operationsContainer}>
            <Col>
              {transData?.operations?.map((op, i) => (
                <Row key={i}>
                  <OpCard
                    block={op}
                    full_trx={transData}
                    trx_id={transaction}
                  />
                </Row>
              ))}
            </Col>
          </Row>

          <Row className={styles.rawTransactionContainer}>
            <Typography variant="h4"> Raw transaction </Typography>
            <Row className={styles.infoContainer}>
              {keys?.map((key, index) => (
                <Card key={index} className={styles.infoCard}>
                  <Card.Body className={styles.cardBody}>
                    <Row>
                      <Col className={styles.cardKeyCol}>{key}</Col>
                      <Col className={styles.cardValueCol}>
                        {key === "operations"
                          ? renderOperations(transData?.operations)
                          : renderRawTransaction(key)}
                      </Col>
                    </Row>
                  </Card.Body>
                </Card>
              ))}
            </Row>
          </Row>
        </Container>
      )}
    </>
  );
}
