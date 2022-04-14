import React from "react";
import { Row, Col, Card } from "react-bootstrap";
export default function Ops({ user_profile_data }) {
  return (
    <div>
      {user_profile_data?.map((d) => {
        const op = d[1].op;
        const userDataJson = JSON.stringify(op, null, 2);
        return (
          <Row key={d[0]} className="justify-content-center">
            <Col className="m-2">
              <Card style={{ overflow: "auto", height: "200px" }}>
                <p>id : {d[0]}</p>
                <pre>{userDataJson}</pre>
              </Card>
            </Col>
          </Row>
        );
      })}
    </div>
  );
}
