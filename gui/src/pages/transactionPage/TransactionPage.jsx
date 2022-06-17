import React, { useContext, useEffect } from "react";
import { Row, Col } from "react-bootstrap";
import { TranasctionContext } from "../../contexts/transactionContext";
import { BlockContext } from "../../contexts/blockContext";
import OpCard from "../../components/operations/operationCard/OpCard";
import Loader from "../../components/loader/Loader";
import { tidyNumber } from "../../functions/calculations";
import styles from "./transactionPage.module.css";

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

  return (
    <>
      {!transData ||
      transData === null ||
      block_data === null ||
      block_data.length === 0 ? (
        <Loader />
      ) : (
        <div className={styles.container}>
          <p className={styles.text}>
            Transaction <span className={styles.number}>{transaction}</span>{" "}
            <br></br>
            Included in block{" "}
            <span className={styles.number}>
              {tidyNumber(transData?.block_num)}{" "}
            </span>
            at <span className={styles.number}>{block_time} UTC</span>
          </p>

          <Row className="mt-5 justify-content-center">
            <Col md={6}>
              {transData?.operations?.map((op, i) => (
                <div key={i}>
                  <OpCard
                    block={op}
                    full_trx={transData}
                    trx_id={transaction}
                  />
                </div>
              ))}
            </Col>
          </Row>
        </div>
      )}
    </>
  );
}
