import React, { useEffect, useRef, useState, useContext } from "react";
import { Navbar, Container, Form, FormControl, Button } from "react-bootstrap";
// import axios from "axios";
import { useNavigate } from "react-router-dom";
import { ApiContext } from "../context/apiContext";
import {
  getAccounts,
  getAccountHistory,
  getBlog,
  getTransaction,
} from "../functions";

export default function NavigationBar() {
  const form_value = useRef("");
  const [value, setValue] = useState("");
  const navigate = useNavigate();
  const [accName, setAccName] = useState("");
  const [blockNr, setBlockNr] = useState("");
  const [isAccountFound, setIsAccountFound] = useState(null);
  const [isBlockFound, setIsBlockFound] = useState(null);
  const {
    setUser_profile_data,
    setBlock_data,
    block_data,
    // setTransData,
    // userProfile,
    // blockNumber,
    // transactionId,
  } = useContext(ApiContext);
  ///acounts
  useEffect(() => {
    if (value !== "") {
      getAccounts(value, setAccName, setIsAccountFound);
    }
    if (accName === value && value !== "") {
      getAccountHistory(accName, setUser_profile_data, setIsAccountFound);
      navigate(`user/${accName}`);
    }
  }, [value, isAccountFound, accName]);
  ///blocks
  useEffect(() => {
    if (isAccountFound === false) {
      getBlog(value, setBlock_data);
      setIsBlockFound(true);
      navigate(`block/${value}`);
      if (block_data === undefined || isAccountFound === true) {
        setIsBlockFound(false);
        // navigate("/error");
      }
    }
  }, [value, isAccountFound]);
  ///transactions

  // useEffect(() => {
  //   if (value === transactionId) {
  //     getTransaction(value, setTransData);
  //     navigate(`transaction/${value}`);
  //   }
  // }, [value, transactionId]);

  function handleSubmit(e) {
    e.preventDefault();
    let val = form_value.current.value;
    setValue(val);
    form_value.current.value = "";
  }

  return (
    <>
      <Navbar bg="light" expand="lg">
        <Container fluid>
          <Navbar.Brand href="/">Hive Block Explorer</Navbar.Brand>
          <Navbar.Toggle aria-controls="navbarScroll" />
          <Navbar.Collapse id="navbarScroll">
            <Form className="d-flex" onSubmit={handleSubmit}>
              <FormControl
                ref={form_value}
                onChange={(e) => e.target.accName}
                type="search"
                placeholder="Search"
                className="me-2"
                aria-label="Search"
              />
              <Button type="submit" variant="outline-success">
                Search
              </Button>
            </Form>
          </Navbar.Collapse>
        </Container>
      </Navbar>
      {/* {isAccountFound === false && <p>No Account Found</p>} */}
    </>
  );
}
