import { useContext } from "react";
import { Row, Col, Card } from "react-bootstrap";
import { ApiContext } from "../context/apiContext";
import { Link } from "react-router-dom";

export default function OperationCard({ transaction, k, tr_id }) {
  const user =
    (transaction.value?.required_auths?.length === 0
      ? transaction.value?.required_posting_auths
      : transaction.value?.required_auths) ||
    transaction.value.from ||
    transaction.value.voter ||
    transaction.value.delegator ||
    transaction.value.account ||
    transaction.value.author ||
    transaction.value.owner ||
    transaction.value.creator ||
    transaction.value.publisher;

  const { setUserProfile, setTransactionId } = useContext(ApiContext);
  const operationInfoJson = JSON.stringify(transaction.value, null, 2);
  const id = tr_id.filter((single_id, index) => index === k && single_id);

  return (
    <div key={k}>
      <Row className="m-3 justify-content-center">
        <Col xs={8}>
          <Card className="text-left">
            <Card.Header
              onClick={() =>
                setUserProfile(typeof user === "object" ? user[0] : user)
              }
            >
              <Link to={`user/${user}`}>{user}</Link>
            </Card.Header>
            <Card.Body>
              <Card.Title>
                Transaction type : <br /> {transaction.type}
              </Card.Title>
              <pre>{operationInfoJson}</pre>
              <Card.Footer>
                Transaction ID{" "}
                <Link to={`/transaction/${id}`}>
                  <p onClick={() => setTransactionId(id)}>{id}</p>
                </Link>
              </Card.Footer>
            </Card.Body>
          </Card>
        </Col>
      </Row>
    </div>
  );
}
