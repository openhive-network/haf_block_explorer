import { useContext } from "react";
import { ApiContext } from "../context/apiContext";
import OperationCard from "../components/OperationCard";
import { Link } from "react-router-dom";
import { Container, Col, Row, ListGroup } from "react-bootstrap";
import TrxTableMain from "../components/TrxTableMain";

export default function Main_Page({ setTitle }) {
  setTitle((document.title = "HAF Blocks"));
  const {
    head_block,
    head_block_data,
    setBlockNumber,
    setUserProfile,
    witnessData,
  } = useContext(ApiContext);
  const current_head_block = head_block.head_block_number;
  const transaction = head_block_data?.transactions;
  const transactions_of_block = transaction?.map(
    (trans) => trans.operations[0]
  );

  const operations_count_per_block = transaction?.length;
  const transactions_ids = head_block_data.transaction_ids;

  const is_data_loading =
    transactions_of_block === undefined || transactions_of_block.length === 0;
  return (
    <Container fluid className="main">
      {is_data_loading ? (
        "Data Loading ... "
      ) : (
        <Row>
          <Col>
            <h1>
              Head Block :
              <Link
                onClick={() => setBlockNumber(current_head_block)}
                to={`/block/${current_head_block}`}
              >
                {current_head_block}
              </Link>
            </h1>
            <h4>
              Operations per block :
              {operations_count_per_block !== 0 && operations_count_per_block}
            </h4>
            <h4>
              Current witness :
              <Link to={`/user/${head_block.current_witness}`}>
                <p onClick={() => setUserProfile(head_block.current_witness)}>
                  {head_block.current_witness}
                </p>
              </Link>
            </h4>
            <h4>
              <Link to="/witnesses">Top Wintesses</Link>
            </h4>
            <Row className="justify-content-center">
              <Col xs={8}>
                {/* {transactions_of_block?.map((single, index) => (
                <OperationCard
                  key={index}
                  transaction={single}
                  k={index}
                  tr_id={transactions_ids}
                />
              ))} */}
                <h3>Last Transactions (3 sec)</h3>

                <TrxTableMain
                  block_trans={transactions_of_block}
                  tr_id={transactions_ids}
                />
              </Col>
              <Col xs={1} />
              <Col
                xs={2}
                className="main__top-witness"
                // style={{ border: "2px solid blue", height: "100vh" }}
              >
                <div className="top-witness__list">
                  <h3>Top Witnesses</h3>
                  {witnessData &&
                    witnessData.map((w, i) => (
                      <ListGroup key={i}>
                        <ListGroup.Item
                          style={{ width: "100%" }}
                          action
                          href={`/user/${w.owner}`}
                        >
                          {w.owner}
                        </ListGroup.Item>
                      </ListGroup>
                    ))}
                  <Link to="/witnesses">More details</Link>
                </div>
              </Col>
            </Row>
          </Col>
        </Row>
      )}
    </Container>
  );
}
