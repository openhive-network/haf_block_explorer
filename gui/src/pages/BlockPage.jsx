import React, { useContext, useState } from "react";
import { BlockContext } from "../contexts/blockContext";
import { Row, Col, Button } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import OpCard from "../components/OpCard";
import BlockOpsFilters from "../components/BlockOpsFilters";

export default function Block_Page({ block_nr, setTitle }) {
  const { block_data, setBlockNumber, blockNumber, block_op_types } =
    useContext(BlockContext);
  const [show_modal, set_show_modal] = useState(false);
  const [vfilters, set_v_filters] = useState("");

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
      {block_data === null || block_data.length === 0 ? (
        <h1>Loading...</h1>
      ) : (
        <div>
          <Row>
            <Col className="d-flex flex-column justify-content-center align-items-center">
              <h1>Block {block_nr} </h1>
              <div>
                <Button className="m-3" onClick={handlePreviousBlock}>
                  Prev Block
                </Button>
                <Button onClick={handleNextBlock}>Next Block</Button>
              </div>

              <p> Transactions in block : {block_data?.length}</p>
              <Button onClick={handleFilters}>Filters</Button>
            </Col>

            <BlockOpsFilters
              vfilters={vfilters}
              set_v_filters={set_v_filters}
              show_modal={show_modal}
              set_show_modal={set_show_modal}
            />
          </Row>
          <Row hidden={vfilters === "Virtual" ? true : false}>
            <Col>
              {block_data?.map((single, i) => {
                if (single.virtual_op === false) {
                  return (
                    <Row key={i} className="justify-content-center">
                      <Col sm={8}>
                        <OpCard block={single} index={i} full_trx={single} />
                      </Col>
                    </Row>
                  );
                }
              })}
            </Col>
          </Row>
          <Row
            // style={{ borderTop: "20px solid red" }}
            hidden={vfilters === "Not-Virtual" ? true : false}
          >
            <Col className="text-center">
              <h1
                style={{
                  background: "#000",
                  color: "#fff",
                  padding: "10px",
                  margin: "25px 0 25px 0",
                }}
              >
                Virtual Operations
              </h1>
              {block_data?.map((single, i) => {
                if (single.virtual_op === true) {
                  return (
                    <Row key={i} className="justify-content-center">
                      <Col sm={8}>
                        <OpCard block={single} index={i} full_trx={single} />
                      </Col>
                    </Row>
                  );
                }
              })}
            </Col>
          </Row>
        </div>
      )}
    </>
  );
}
