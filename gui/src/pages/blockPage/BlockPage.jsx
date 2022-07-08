import React, { useContext, useState } from "react";
import { BlockContext } from "../../contexts/blockContext";
import { Row, Col, Button } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import OpCard from "../../components/operations/operationCard/OpCard";
import BlockOpsFilters from "../../components/operations/filters/BlockOpsFilters";
import Loader from "../../components/loader/Loader";
import {
  handleNextBlock,
  handlePreviousBlock,
  handleFilters,
} from "../../functions/block_page_func";
import { tidyNumber } from "../../functions/calculations";
import styles from "./blockPage.module.css";

export default function Block_Page({ block_nr }) {
  document.title = `HAF | Block ${block_nr}`;
  const { block_data, setBlockNumber, blockNumber } = useContext(BlockContext);
  const [show_modal, set_show_modal] = useState(false);
  const [vfilters, set_v_filters] = useState("");

  const navigate = useNavigate();

  return (
    <>
      {block_data === null || block_data.length === 0 ? (
        <Loader />
      ) : (
        <div>
          <Row>
            <Col className="d-flex flex-column justify-content-center align-items-center">
              <h3 className={styles.text}>
                Block{" "}
                <span className={styles.number}>{tidyNumber(block_nr)}</span>
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

              <p className={styles.text}>
                <span className={styles.number}>{block_data?.length}</span>{" "}
                transactions produced in this block at{" "}
                <span className={styles.number}>
                  {block_data?.[0]?.timestamp} UTC
                </span>
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
                        <OpCard block={single} full_trx={single} />
                      </Col>
                    </Row>
                  );
                } else return "";
              })}
            </Col>
          </Row>
          <Row hidden={vfilters === "Not-Virtual" ? true : false}>
            <Col className="text-center">
              <h3 className={styles.text}>Virtual Operations</h3>
              {block_data?.map((single, i) => {
                if (single.virtual_op === true) {
                  return (
                    <Row key={i} className="justify-content-center">
                      <Col sm={8}>
                        <OpCard block={single} full_trx={single} />
                      </Col>
                    </Row>
                  );
                } else return "";
              })}
            </Col>
          </Row>
        </div>
      )}
    </>
  );
}
