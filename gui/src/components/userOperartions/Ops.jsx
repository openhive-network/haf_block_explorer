import React from "react";
<<<<<<< HEAD
// import { Row, Col, Card } from "react-bootstrap";
import { Toast, ToastContainer } from "react-bootstrap";
import Pop from "./Pop";
import TimeAgo from "javascript-time-ago";
import en from "javascript-time-ago/locale/en.json";
import ReactTimeAgo from "react-time-ago";
export default function Ops({ user_profile_data, user }) {
  // TODO  ==== set time gtm
=======
import { Row, Col, Card } from "react-bootstrap";
export default function Ops({ user_profile_data }) {
>>>>>>> Add operation filters for user history
  return (
    <div>
      {user_profile_data?.map((d) => {
        const op = d[1].op;
        const userDataJson = JSON.stringify(op, null, 2);
        return (
<<<<<<< HEAD
          // <Row key={d[0]} className="justify-content-center">
          //   <Col className="m-2">
          //     <Card style={{ overflow: "auto", height: "200px" }}>
          //       <p>id : {d[0]}</p>
          //       <pre>{userDataJson}</pre>
          //     </Card>
          //   </Col>
          // </Row>
          <ToastContainer style={{ width: "100%" }} key={d[0]} className="p-3">
            <Toast style={{ width: "100%" }}>
              <Toast.Header closeButton={false}>
                <strong className="me-auto">{user}</strong>
                <small className="text-muted">
                  {" "}
                  <ReactTimeAgo
                    date={new Date(d[1].timestamp)}
                    locale="en-US"
                  />
                </small>
              </Toast.Header>
              <Toast.Body>
                <p>id : {d[0]}</p>
                <p>Operation Type : {op.type}</p>
                <Pop userData={userDataJson} />
                {/* <pre>{userDataJson}</pre> */}
              </Toast.Body>
            </Toast>
          </ToastContainer>
=======
          <Row key={d[0]} className="justify-content-center">
            <Col className="m-2">
              <Card style={{ overflow: "auto", height: "200px" }}>
                <p>id : {d[0]}</p>
                <pre>{userDataJson}</pre>
              </Card>
            </Col>
          </Row>
>>>>>>> Add operation filters for user history
        );
      })}
    </div>
  );
}
