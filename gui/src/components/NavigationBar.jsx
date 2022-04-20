import React, { useEffect, useRef, useState, useContext } from "react";
import { Navbar, Container, Form, FormControl, Col } from "react-bootstrap";
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
      <div className="nav-bar">
        <Col xs={4}>
          <Link to="/">HIVE LOGO</Link>
        </Col>
        <Col className="d-flex justify-content-center" xs={8}>
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
      </div>
      {/* </Navbar.Collapse>
        </Container>
      </Navbar> */}
    </>
  );
}
