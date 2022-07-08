import { useContext } from "react";
import { HeadBlockContext } from "../../contexts/headBlockContext";
import { WitnessContext } from "../../contexts/witnessContext";
import { Link } from "react-router-dom";
import { Container, Col, Row } from "react-bootstrap";
import OpCard from "../../components/operations/operationCard/OpCard";
import Loader from "../../components/loader/Loader";
import styles from "./mainPage.module.css";
import HeadBlockCard from "../../components/block/HeadBlockCard";

export default function Main_Page() {
  document.title = "HAF | Block explorer";
  const { witnessData } = useContext(WitnessContext);
  const { head_block_data } = useContext(HeadBlockContext);
  const operations_count_per_block = head_block_data?.length;

  const profile_picture = (user) => {
    return `https://images.hive.blog/u/${user}/avatar`;
  };
  const trim_witness_array = witnessData?.slice(0, 20);

  return (
    <>
      {operations_count_per_block === 0 ? (
        <Loader />
      ) : (
        <Container fluid>
          <Row className="d-flex justify-content-center">
            <HeadBlockCard profile_picture={profile_picture} />
            <Col md={12} lg={6}>
              <p className={styles.text}>Last transactions (3 sec)</p>
              {head_block_data?.map((block, index) => (
                <div key={index}>
                  <OpCard block={block} full_trx={block} />
                </div>
              ))}
            </Col>

            <Col md={12} lg={3}>
              <div className={styles.topWitnessesList}>
                <h3>Top Witnesses</h3>
                <ol className={styles.topWitnessOl}>
                  {trim_witness_array?.map((w) => (
                    <div key={w.id}>
                      <li className={styles.topWitnessLi}>
                        <img
                          src={profile_picture(w.owner)}
                          alt="witness profile avatar"
                        />
                        <Link className={styles.link} to={`/user/${w.owner}`}>
                          {w.owner}
                        </Link>
                      </li>
                    </div>
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
