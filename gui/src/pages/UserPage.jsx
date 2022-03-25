import React, { useContext } from "react";
import { ApiContext } from "../context/apiContext";

import { Card, Col, Row } from "react-bootstrap";
export default function User_Page({ user }) {
  const { user_profile_data } = useContext(ApiContext);
  return (
    <div>
      <h1>This is personal page of {user}</h1>
      {user_profile_data.map((d) => {
        const userDataJson = JSON.stringify(d, null, 2);
        return (
          <Row key={d[0]} className="justify-content-center">
            <Col xs={6} className="m-2">
              <Card>
                <pre>{userDataJson}</pre>
              </Card>
            </Col>
          </Row>
        );
      })}
    </div>
  );
}
