import React, { useEffect, useRef, useState, useContext } from "react";
import { Form, FormControl, Col, Row } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import { BlockContext } from "../contexts/blockContext";
import { UserProfileContext } from "../contexts/userProfileContext";
import { TranasctionContext } from "../contexts/transactionContext";
// import { getAccounts, getBlog, getTransaction } from "../functions";
import { Link } from "react-router-dom";
import axios from "axios";
// import { FaAdn } from "react-icons/fa";
// import IconButton from "@mui/material/IconButton";

export default function NavigationBar() {
  const navigate = useNavigate();
  const form_value = useRef("");
  const [value, setValue] = useState("");

  // const [accName, setAccName] = useState("");
  // const [blockNr, setBlockNr] = useState("");
  // const [transNr, setTransNr] = useState("");
  // const [isAccountFound, setIsAccountFound] = useState(null);
  // const [isBlockFound, setIsBlockFound] = useState(null);
  // const [isTransactionFound, setIsTransactionFound] = useState(null);

  // const { setUserProfile, setTransactionId } = useContext(ApiContext);
  const { setBlockNumber } = useContext(BlockContext);
  const { setUserProfile } = useContext(UserProfileContext);
  const { setTransactionId } = useContext(TranasctionContext);

  // Find what user typed into search input and navigate him to correct page
  // useEffect(() => {
  //   if (value !== "") {
  //     getAccounts(value, setAccName, setIsAccountFound);
  //     getBlog(value, setBlockNr, setIsBlockFound);
  //     getTransaction(value, setTransNr, setIsTransactionFound);
  //     if (isAccountFound === true) {
  //       setUserProfile(accName);
  //       navigate(`user/${accName}`);
  //     }
  //     if (isBlockFound === true) {
  //       setBlockNumber(blockNr);
  //       navigate(`block/${blockNr}`);
  //     }
  //     if (isTransactionFound === true) {
  //       setTransactionId(transNr);
  //       navigate(`transaction/${transNr}`);
  //     }
  //     if (
  //       isAccountFound === false &&
  //       isBlockFound === false &&
  //       isTransactionFound === false
  //     ) {
  //       navigate("/error");
  //     }
  //   }
  // }, [
  //   value,
  //   accName,
  //   blockNr,
  //   transNr,
  //   isAccountFound,
  //   isBlockFound,
  //   isTransactionFound,
  // ]);
  const [check_input, set_check_input] = useState("");
  function handleSubmit(e) {
    e.preventDefault();
    let val = form_value.current.value;
    setValue(val);
    form_value.current.value = "";
  }

  //Check data type
  useEffect(() => {
    axios({
      method: "post",
      url: "http://localhost:3000/rpc/get_input_type",
      headers: { "Content-Type": "application/json" },
      data: { _input: value },
    })
      .then((res) => set_check_input(res.data))
      .catch((err) => set_check_input("No data"));
  }, [value]);
  // Navigate to correct page
  useEffect(() => {
    if (check_input.input_type === "block_num") {
      setBlockNumber(value);
      navigate(`block/${value}`);
    }
    if (check_input.input_type === "account_name") {
      setUserProfile(value);
      navigate(`user/${value}`);
    }

    if (check_input.input_type === "transaction_id") {
      setTransactionId(value);
      navigate(`transaction/${value}`);
    }
    if (check_input.input_type === "block_hash") {
      setBlockNumber(check_input.input_value);
      navigate(`block/${check_input.input_value}`);
    }
    if (check_input === "No data") {
      navigate("/error");
    }
  }, [check_input, value]);

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
              onChange={(e) => e.target.value}
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
