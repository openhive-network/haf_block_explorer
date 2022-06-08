import { useContext } from "react";
import { HeadBlockContext } from "../contexts/headBlockContext";
import { UserProfileContext } from "../contexts/userProfileContext";
import { BlockContext } from "../contexts/blockContext";
import { WitnessContext } from "../contexts/witnessContext";
import { Link } from "react-router-dom";
import { Container, Col, Row } from "react-bootstrap";
import OpCard from "../components/OpCard";

export default function Main_Page({ setTitle }) {
  // setTitle((document.title = "HAF Blocks"));
  const { witnessData } = useContext(WitnessContext);
  const { setBlockNumber } = useContext(BlockContext);
  const { head_block, head_block_data } = useContext(HeadBlockContext);
  const { setUserProfile } = useContext(UserProfileContext);
  const current_head_block = head_block.head_block_number;
  const operations_count_per_block = head_block_data?.length;

  const profile_picture = (user) => {
    return `https://images.hive.blog/u/${user}/avatar`;
  };
  const trim_witness_array = witnessData?.slice(0, 20);
  return (
    <>
      {operations_count_per_block === 0 ? (
        <h1>Loading...</h1>
      ) : (
        <Container fluid className="main">
          <Row className="d-flex justify-content-center">
            <Col>
              <div className="head_block_properties">
                <h3>
                  Head Block :{" "}
                  <Link
                    onClick={() => setBlockNumber(current_head_block)}
                    to={`/block/${current_head_block}`}
                  >
                    {current_head_block}
                  </Link>
                </h3>
                <p>
                  Operations per block :{" "}
                  {operations_count_per_block !== 0 &&
                    operations_count_per_block}
                </p>
                <p>
                  Current witness :
                  <Link to={`/user/${head_block?.current_witness}`}>
                    <p
                      onClick={() =>
                        setUserProfile(head_block?.current_witness)
                      }
                    >
                      <img
                        src={`https://images.hive.blog/u/${head_block.current_witness}/avatar`}
                        style={{
                          width: "40px",
                          height: "40px",
                          margin: "5px",
                          borderRadius: "50%",
                        }}
                      />{" "}
                      {head_block.current_witness}
                    </p>
                  </Link>
                </p>
                <p style={{ fontSize: "20px", color: "#e5ff00 " }}>
                  Properties{" "}
                </p>
                <ul style={{ listStyle: "none", padding: "0" }}>
                  <li>Blockchain time : {head_block?.time}</li>
                </ul>
              </div>
            </Col>
            <Col xs={12} sm={7}>
              <p>Last Transactions (3 sec)</p>
              {head_block_data?.map((block, index) => (
                <OpCard block={block} index={index} full_trx={block} />
              ))}
            </Col>

            <Col
              // xs={12}
              // sm={2}
              className="main__top-witness"
            >
              <div className="top-witness__list">
                <h3>Top Witnesses</h3>
                <ol style={{ textAlign: "left" }}>
                  {trim_witness_array?.map((w, i) => (
                    <li style={{ margin: "10px" }}>
                      <img
                        style={{
                          width: "40px",
                          borderRadius: "50%",
                          margin: "5px",
                        }}
                        src={profile_picture(w.owner)}
                      />
                      <Link to={`/user/${w.owner}`}>{w.owner}</Link>
                    </li>
                  ))}
                </ol>

                <Link to="/witnesses">More details</Link>
              </div>
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
