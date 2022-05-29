import React, { useContext, useState } from "react";
import { BlockContext } from "../contexts/blockContext";
import { Row, Col, Button } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
// import GetOperations from "../operations";
// import HighlightedJSON from "../components/HighlightedJSON";
import OpCard from "../components/OpCard";
import BlockOpsFilters from "../components/BlockOpsFilters";

export default function Block_Page({ block_nr, setTitle }) {
  const { block_data, setBlockNumber, blockNumber, block_op_types } =
    useContext(BlockContext);
  const [show_modal, set_show_modal] = useState(false);
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
  // console.log(block_op_types);
  const handleFilters = () => set_show_modal(!show_modal);
  // console.log(block_op_types);
  return (
    <>
      {block_op_types === null ? (
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
              <Button onClick={handleFilters}>Filters</Button>
            </Col>

            <BlockOpsFilters
              show_modal={show_modal}
              set_show_modal={set_show_modal}
            />
          </Row>
          {block_data?.map((single, i) => {
            return (
              <Row key={i} className="justify-content-center">
                <Col sm={8}>
                  <OpCard block={single} index={i} full_trx={single} />
                </Col>
              </Row>
            );
          })}
        </div>
      )}
    </>
  );
}
