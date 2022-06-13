import React from "react";
import { Row, Col, Card } from "react-bootstrap";
import { Link } from "react-router-dom";

export default function UserInfoTable({ user_info }) {
  const keys = user_info && Object.keys(user_info);

  return (
    <div style={{ marginTop: "25px" }}>
      {keys?.map((key, index) => {
        const render_key = () => {
          if (
            ["recovery_account", "reset_account", "owner", "url"].includes(key)
          ) {
            return <Link to={`/user/${user_info[key]}`}>{user_info[key]}</Link>;
          } else return user_info[key];
        };

        return (
          <Card
            key={index}
            style={{
              borderRadius: "0",
              background: "#2C3136",
              border: "1px solid #fff",
              color: "#fff",
            }}
          >
            <Card.Body style={{ padding: "5px" }}>
              <Row>
                <Col>{key}</Col>
                <Col
                  style={{ wordBreak: "break-word", textAlign: "end" }}
                  className=" d-flex justify-content-end "
                >
                  {typeof user_info?.[key] != "string"
                    ? JSON.stringify(user_info?.[key])
                    : render_key()}
                </Col>
              </Row>
            </Card.Body>
          </Card>
        );
      })}
    </div>
  );
}
