import React, { useEffect, useRef, useState, useContext } from "react";
import {
  Navbar,
  Container,
  Form,
  FormControl,
  Col,
  Row,
} from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import { ApiContext } from "../context/apiContext";
import { getAccounts, getBlog, getTransaction } from "../functions";
import { Link } from "react-router-dom";

// import { FaAdn } from "react-icons/fa";
// import IconButton from "@mui/material/IconButton";

export default function NavigationBar() {
  const navigate = useNavigate();
  const form_value = useRef("");
  const [value, setValue] = useState("");
  const [accName, setAccName] = useState("");
  const [blockNr, setBlockNr] = useState("");
  const [transNr, setTransNr] = useState("");
  const [isAccountFound, setIsAccountFound] = useState(null);
  const [isBlockFound, setIsBlockFound] = useState(null);
  const [isTransactionFound, setIsTransactionFound] = useState(null);

  const { setBlockNumber, setUserProfile, setTransactionId } =
    useContext(ApiContext);

  // Find what user typed into search input and navigate him to correct page
  useEffect(() => {
    if (value !== "") {
      getAccounts(value, setAccName, setIsAccountFound);
      getBlog(value, setBlockNr, setIsBlockFound);
      getTransaction(value, setTransNr, setIsTransactionFound);
      if (isAccountFound === true) {
        setUserProfile(accName);
        navigate(`user/${accName}`);
      }
      if (isBlockFound === true) {
        setBlockNumber(blockNr);
        navigate(`block/${blockNr}`);
      }
      if (isTransactionFound === true) {
        setTransactionId(transNr);
        navigate(`transaction/${transNr}`);
      }
      if (
        isAccountFound === false &&
        isBlockFound === false &&
        isTransactionFound === false
      ) {
        navigate("/error");
      }
    }
  }, [
    value,
    accName,
    blockNr,
    transNr,
    isAccountFound,
    isBlockFound,
    isTransactionFound,
  ]);

  function handleSubmit(e) {
    e.preventDefault();
    let val = form_value.current.value;
    setValue(val);
  }
  return (
    <>
      {/* <Navbar bg="light" expand="lg">
        <Container fluid>
          <Navbar.Brand href="/">Hive Block Explorer</Navbar.Brand>
          <Navbar.Toggle aria-controls="navbarScroll" />
          <Navbar.Collapse id="navbarScroll"> */}
      <Row className="nav-bar">
        <Col
          style={{
            display: "flex",
            margin: "0 40px 0 50px",
            alignItems: "center",
          }}
          xs={4}
        >
          <Link to="/">
            <img
              style={{ width: "80px" }}
              src="https://hive.blog/images/favicons/favicon-196x196.png"
            />
          </Link>
          <Link style={{ textDecoration: "none" }} to="/">
            <h2
              style={{
                marginLeft: "10px",
                color: "#fff",
              }}
            >
              Haf Blocks
            </h2>
          </Link>
        </Col>
        <Col>
          <Form className="nav-bar__form" onSubmit={handleSubmit}>
            <FormControl
              ref={form_value}
              onChange={(e) => e.target.accName}
              type="search"
              placeholder="Search"
              className="me-2"
              aria-label="Search"
            />
          </Form>
        </Col>
      </Row>
      {/* </Navbar.Collapse>
        </Container>
      </Navbar> */}
    </>
  );
}
