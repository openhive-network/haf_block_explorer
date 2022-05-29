import { useContext } from "react";
import { HeadBlockContext } from "../contexts/headBlockContext";
import { UserProfileContext } from "../contexts/userProfileContext";
import { BlockContext } from "../contexts/blockContext";
import { WitnessContext } from "../contexts/witnessContext";
// import OperationCard from "../components/OperationCard";
import { Link } from "react-router-dom";
import { Container, Col, Row, ListGroup } from "react-bootstrap";
// import TrxTableMain from "../components/tables/TrxTableMain";
// import GetOperations from "../operations";
import OpCard from "../components/OpCard";

export default function Main_Page({ setTitle }) {
  // setTitle((document.title = "HAF Blocks"));
  const { witnessData } = useContext(WitnessContext);
  const { setBlockNumber } = useContext(BlockContext);
  const { head_block, head_block_data } = useContext(HeadBlockContext);
  const { setUserProfile } = useContext(UserProfileContext);
  const current_head_block = head_block.head_block_number;
  // const transaction = head_block_data?.transactions;
  // const transactions_of_block = transaction?.map(
  //   (trans) => trans.operations[0]
  // );

  const operations_count_per_block = head_block_data?.length;
  // const transactions_ids = head_block_data?.transaction_ids;

  // const is_data_loading =
  //   transactions_of_block === undefined || transactions_of_block.length === 0;
  // console.log(head_block_data.op);

  return (
    <>
      {operations_count_per_block === 0 ? (
        <h1>Loading...</h1>
      ) : (
        <Container fluid className="main">
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
                <Link to={`/user/${head_block?.current_witness}`}>
                  <p
                    onClick={() => setUserProfile(head_block?.current_witness)}
                  >
                    {/* <img
                  src={`https://images.hive.blog/u/${head_block.current_witness}/avatar`}
                  style={{
                    width: "40px",
                    height: "40px",
                    margin: "5px",
                    borderRadius: "50%",
                  }}
                />{" "} */}
                    {head_block.current_witness}
                  </p>
                </Link>
              </h4>
              <h4>
                <Link to="/witnesses">Top Wintesses</Link>
              </h4>
            </Col>
          </Row>
          <Row className="justify-content-center">
            <h3>Last Transactions (3 sec)</h3>

            <Col xs={12} sm={8}>
              {head_block_data?.map((block, index) => {
                return <OpCard block={block} index={index} full_trx={block} />;
              })}
            </Col>
            {/* <Col sm={1} /> */}
            <Col
              xs={12}
              sm={4}
              className="main__top-witness"
              // style={{ border: "2px solid blue", height: "100vh" }}
            >
              <div className="top-witness__list d-flex flex-column text-center ">
                <h3>Top Witnesses</h3>
                {witnessData?.map((w, i) => (
                  <ListGroup key={i}>
                    <ListGroup.Item
                      style={{ width: "400px" }}
                      action
                      href={`/user/${w.owner}`}
                    >
                      {/* <img
                    src={`https://images.hive.blog/u/${w.owner}/avatar`}
                    style={{
                      width: "40px",
                      height: "40px",
                      margin: "5px",
                      borderRadius: "50%",
                    }}
                  /> */}
                      {w.owner}
                    </ListGroup.Item>
                  </ListGroup>
                ))}
                <Link to="/witnesses">More details</Link>
              </div>
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
