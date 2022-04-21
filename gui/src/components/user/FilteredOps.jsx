import React from "react";
import { Row, Col, Card } from "react-bootstrap";
import { Toast, ToastContainer } from "react-bootstrap";
import Pop from "./Pop";

export default function FilteredOps({
  user_profile_data,
  active_op_filters,
  user,
}) {
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
            <ToastContainer
              style={{ width: "100%" }}
              key={d[0]}
              className="p-3"
            >
              <Toast style={{ width: "100%" }}>
                <Toast.Header closeButton={false}>
                  <strong className="me-auto">{user}</strong>
                  <small className="text-muted">time ago</small>
                </Toast.Header>
                <Toast.Body>
                  <p>id : {d[0]}</p>
                  <p>Operation Type : {op.type}</p>
                  <Pop userData={userDataJson} />
                  {/* <pre>{userDataJson}</pre> */}
                </Toast.Body>
              </Toast>
            </ToastContainer>
          );
        }
      })}
    </div>
  );
}
