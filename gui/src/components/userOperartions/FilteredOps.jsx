import React from "react";
import { Row, Col, Card } from "react-bootstrap";

export default function FilteredOps({ user_profile_data, active_op_filters }) {
  return (
    <div>
      {user_profile_data?.map((d, i) => {
        const op = d[1].op;
        const filtered_op = active_op_filters?.filter((o) => o == op.type);
        const newOp = filtered_op[0] === op.type && op;
        const userDataJson = JSON.stringify(newOp, null, 2);
        if (newOp === false) {
          return "";
        } else {
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
        }
      })}
    </div>
  );
}
