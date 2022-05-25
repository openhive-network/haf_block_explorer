import React, { useContext } from "react";
import { BlockContext } from "../contexts/blockContext";
import { Row, Col, Button } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
// import GetOperations from "../operations";
// import HighlightedJSON from "../components/HighlightedJSON";
import OpCard from "../components/OpCard";

export default function Block_Page({ block_nr, setTitle }) {
  const { block_data, setBlockNumber, blockNumber } = useContext(BlockContext);

  // setTitle(`HAF | Block | ${block_nr}`);
  //Block counter
  const navigate = useNavigate();

  const handleNextBlock = () => {
    navigate(`/block/${blockNumber + 1}`);
    setBlockNumber(blockNumber + 1);
  };
  const handlePreviousBlock = () => {
    navigate(`/block/${blockNumber - 1}`);
    setBlockNumber(blockNumber - 1);
  };

  return (
    <>
      {block_data === null ? (
        <h1>Loading...</h1>
      ) : (
        <div>
          <Row>
            <Col className="d-flex flex-column justify-content-center align-items-center">
              <h1>Block {block_nr} </h1>
              <div>
                <Button className="m-3" onClick={handlePreviousBlock}>
                  Next Block
                </Button>
                <Button onClick={handleNextBlock}>Prev Block</Button>
              </div>

              <p> Transactions in block : {block_data?.length}</p>
            </Col>
          </Row>

          {block_data?.length === 0 ? (
            <h1>No transactions for this block</h1>
          ) : (
            block_data?.map((single, i) => {
              return (
                <Row key={i} className="justify-content-center">
                  <Col sm={8}>
                    <OpCard block={single} index={i} full_trx={single} />
                  </Col>
                </Row>
              );
            })
          )}
        </div>
      )}
    </>
  );
}
