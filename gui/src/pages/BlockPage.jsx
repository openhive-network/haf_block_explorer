import React, { useContext, useState } from "react";
import { BlockContext } from "../contexts/blockContext";
import { Row, Col, Button } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import OpCard from "../components/operations/OpCard";
import BlockOpsFilters from "../components/operations/filters/BlockOpsFilters";
import Loader from "../components/loader/Loader";
import {
  handleNextBlock,
  handlePreviousBlock,
  handleFilters,
} from "../functions/block_page_func";
import { useEffect } from "react";

export default function Block_Page({ block_nr, setTitle }) {
  const { block_data, setBlockNumber, blockNumber } = useContext(BlockContext);
  const [show_modal, set_show_modal] = useState(false);
  const [vfilters, set_v_filters] = useState("");

  // setTitle(`HAF | Block | ${block_nr}`);
  const navigate = useNavigate();

  const details_style = {
    color: "#ada9a9dc",
    fontSize: "20px",
  };
  const style = { color: "#160855", fontWeight: "bold" };

  return (
    <>
      {block_data === null || block_data.length === 0 ? (
        <Loader />
      ) : (
        <div>
          <Row>
            <Col className="d-flex flex-column justify-content-center align-items-center">
              <h3 style={details_style}>
                Block <span style={style}>{block_nr}</span>
              </h3>
              <div>
                <Button
                  size="sm"
                  className="m-3"
                  onClick={() =>
                    handlePreviousBlock(navigate, setBlockNumber, blockNumber)
                  }
                >
                  Prev Block
                </Button>
                <Button
                  size="sm"
                  onClick={() =>
                    handleNextBlock(navigate, setBlockNumber, blockNumber)
                  }
                >
                  Next Block
                </Button>
              </div>

              <p style={details_style}>
                <span style={style}>{block_data?.length}</span> transactions
                produced in this block at{" "}
                <span style={style}>{block_data?.[0]?.timestamp} UTC</span>
              </p>
              <Button
                size="sm"
                onClick={() => handleFilters(set_show_modal, show_modal)}
              >
                Filters
              </Button>
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
              <h3
                style={details_style}
                // style={{
                //   background: "#000",
                //   color: "#fff",
                //   padding: "10px",
                //   margin: "25px 0 25px 0",
                // }}
              >
                Virtual Operations
              </h3>
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
