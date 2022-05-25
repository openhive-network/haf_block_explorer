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
  // console.log(head_block_data);
  return (
    <>
      {/* {head_block_data === null ? (
        <h1>Loading...</h1>
      ) : ( */}
      <Container fluid className="main">
        {/* {is_data_loading ? (
        "Data Loading ... "
      ) : ( */}
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
          {/* {transactions_of_block?.map((single, index) => (
                <OperationCard
                  key={index}
                  transaction={single}
                  k={index}
                  tr_id={transactions_ids}
                />
              ))} */}

          <h3>Last Transactions (3 sec)</h3>

          {/* <TrxTableMain
                block_trans={transactions_of_block}
                tr_id={transactions_ids}
              /> */}
          <Col xs={12} sm={8}>
            {head_block_data?.map((block, index) => {
              // const type = block.operations.type.replaceAll("_", " ");
              // const link_to_trx = (
              //   <Link
              //     style={{ color: "#000", textDecoration: "none" }}
              //     to={`/transaction/${block.trx_id}`}
              //   >
              //     {block.trx_id}
              //   </Link>
              // );
              // const link_to_block = (
              //   <Link
              //     style={{
              //       color: "#000",
              //       textDecoration: "none",
              //     }}
              //     to={`/block/${block.block}`}
              //   >
              //     {block.block}
              //   </Link>
              // );
              return (
                // <Toast
                //   className="d-inline-block m-1 w-100"
                //   style={{ backgroundColor: "#091B4B" }}
                //   key={index}
                // >
                //   <Toast.Header
                //     style={{ color: "#091B4B" }}
                //     closeButton={false}
                //   >
                //     <img
                //       src="holder.js/20x20?text=%20"
                //       className="rounded me-2"
                //       alt=""
                //     />
                //     <strong className="me-auto">
                //       <p style={{ margin: "0" }}>
                //         ID {block.trx_id !== null ? link_to_trx : "no id"}
                //       </p>
                //       <p style={{ margin: "0" }}>Block {link_to_block}</p>
                //     </strong>
                //     <strong className="me-auto">
                //       <p
                //         style={{
                //           fontSize: "20px",
                //           textTransform: "capitalize",
                //         }}
                //       >
                //         {type}
                //       </p>
                //     </strong>

                //     <small>{block.timestamp} </small>
                //   </Toast.Header>
                //   <Toast.Body className="text-white">
                //     <GetOperations
                //       value={block?.operations?.type}
                //       type={block.operations}
                //     />
                //     {/* <HighlightedJSON json={single} /> */}
                //   </Toast.Body>
                // </Toast>
                <OpCard block={block} index={index} full_trx={block} />
              );
            })}
          </Col>
          <Col sm={1} />
          <Col
            xs={12}
            sm={3}
            className="main__top-witness"
            // style={{ border: "2px solid blue", height: "100vh" }}
          >
            <div className="top-witness__list">
              <h3>Top Witnesses</h3>
              {witnessData?.map((w, i) => (
                <ListGroup key={i}>
                  <ListGroup.Item
                    style={{ width: "100%" }}
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
        {/* </Col>
      </Row> */}
        {/* )} */}
      </Container>
      {/* )} */}
    </>
  );
}
