import React, { useContext } from "react";
import { Row, Col } from "react-bootstrap";
import { TranasctionContext } from "../contexts/transactionContext";
import OpCard from "../components/OpCard";
import Loader from "../components/loader/Loader";

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

  /* {transData === null ? (
    <p>
      Note : New transactions need time to show up. <br></br>Transaction
      will be shown in : {seconds}{" "}
    </p>
  ) : ( */
  console.log(transData);
  // <>

  return (
    <>
      {!transData || transData === null ? (
        <Loader />
      ) : (
        <>
          <h1>Transaction Page</h1> <h4>Transaction ID : {transaction}</h4>
          <Row className="mt-5 justify-content-center">
            <Col sm={6}>
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
        </>
      )}
    </>
  );
}
