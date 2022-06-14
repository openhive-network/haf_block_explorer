import React, { useContext, useEffect } from "react";
import { Row, Col } from "react-bootstrap";
import { TranasctionContext } from "../contexts/transactionContext";
import { BlockContext } from "../contexts/blockContext";
import OpCard from "../components/operations/OpCard";
import Loader from "../components/loader/Loader";
import { tidyNumber } from "../functions/calculations";

export default function Transaction_Page({ transaction, setTitle }) {
  // setTitle(`HAF | Transaction`);
  const { transData } = useContext(TranasctionContext);
  const { block_data, setBlockNumber } = useContext(BlockContext);
  // const trnasToJson = JSON.stringify(transData, null, 2);

  // const [seconds, setSeconds] = useState(60);

  // const timeout = setTimeout(() => {
  //   setSeconds(seconds - 1);
  // }, 1000);

  // if (seconds <= 0) {
  //   clearTimeout(timeout);
  //   window.location.reload();
  // }

  /* {transData === null ? (
    <p>
      Note : New transactions need time to show up. <br></br>Transaction
      will be shown in : {seconds}{" "}
    </p>
  ) : ( */
  useEffect(() => {
    if (transData || transData !== null) {
      setBlockNumber(transData?.block_num);
    }
  }, [transData]);
  const block_time = block_data?.[0]?.timestamp;
  // <>
  const details_style = {
    color: "#ada9a9dc",
    fontSize: "20px",
  };
  const style = { color: "#160855", fontWeight: "bold" };

  return (
    <>
      {!transData ||
      transData === null ||
      block_data === null ||
      block_data.length === 0 ? (
        <Loader />
      ) : (
        <div
          style={{
            textAlign: "center",
            display: "flex",
            flexDirection: "column",
          }}
        >
          <p style={details_style}>
            Transaction <span style={style}>{transaction}</span> <br></br>
            Included in block{" "}
            <span style={style}>
              {tidyNumber(transData?.block_num)}{" "}
            </span>at <span style={style}>{block_time} UTC</span>
          </p>

          <Row className="mt-5 justify-content-center">
            <Col md={6}>
              {transData?.operations?.map((op, i) => (
                <OpCard
                  block={op}
                  index={i}
                  full_trx={transData}
                  trx_id={transaction}
                />
              ))}
            </Col>
          </Row>
        </div>
      )}
    </>
  );
}
