import React from "react";
import { Popover, OverlayTrigger, Button } from "react-bootstrap";

export default function Pop({ userData }) {
  const popov = (
    <Popover style={{ width: "600px" }} id="popover-basic">
      <Popover.Header as="h3">Operation type</Popover.Header>
      <Popover.Body>{userData}</Popover.Body>
    </Popover>
  );

  return (
    <OverlayTrigger trigger="click" placement="right" overlay={popov}>
      <Button variant="success">Show more</Button>
    </OverlayTrigger>
  );
}
