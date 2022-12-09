import React, { useEffect, useRef, useState, useContext } from "react";
import {
  Form,
  FormControl,
  Button,
  Container,
  Nav,
  Navbar,
} from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import { BlockContext } from "../../../../contexts/blockContext";
import { UserProfileContext } from "../../../../contexts/userProfileContext";
import { TranasctionContext } from "../../../../contexts/transactionContext";
import axios from "axios";
import styles from "./navigationBar.module.css";

export default function NavigationBar() {
  const navigate = useNavigate();
  const form_value = useRef("");
  const [value, setValue] = useState("");
  const { setBlockNumber } = useContext(BlockContext);
  const { setUserProfile } = useContext(UserProfileContext);
  const { setTransactionId } = useContext(TranasctionContext);
  const [check_input, set_check_input] = useState("");

  function handleSubmit(e) {
    e.preventDefault();
    let val = form_value.current.value;
    setValue(val);
    form_value.current.value = "";
  }

  //Get input type
  useEffect(() => {
    if (value !== "") {
      axios({
        method: "post",
        url: `http://192.168.4.250:3000/rpc/get_input_type`,
        headers: { "Content-Type": "application/json" },
        data: { _input: value },
      })
        .then((res) => set_check_input(res.data))
        .catch((err) => set_check_input("No data"));
    }
  }, [value]);

  // Navigate to correct page
  useEffect(() => {
    if (check_input.input_type === "block_num") {
      setBlockNumber(value);
      navigate(`/block/${value}`);
    }
    if (check_input.input_type === "account_name") {
      setUserProfile(value);
      navigate(`/user/${value}`);
    }

    if (check_input.input_type === "transaction_hash") {
      setTransactionId(value);
      navigate(`/transaction/${value}`);
    }
    if (check_input.input_type === "block_hash") {
      setBlockNumber(check_input.input_value);
      navigate(`/block/${check_input.input_value}`);
    }
    if (check_input === "No data") {
      navigate("/error");
    }
  }, [check_input, value, setBlockNumber, setTransactionId, setUserProfile]);

  return (
    <>
      <Navbar className={styles.navbar} bg="dark" expand="xl">
        <Container fluid>
          <Navbar.Brand href="/">
            <div className={styles.navbarBrand}>
              <img
                alt="hive-logo"
                className={styles.navbarLogo}
                src="https://hive.blog/images/favicons/favicon-196x196.png"
              />
            </div>
          </Navbar.Brand>
          <Navbar.Toggle aria-controls="navbarScroll" />
          <Navbar.Collapse id="navbarScroll">
            <Nav className={`me-auto my-2 my-lg-0 `} navbarScroll>
              <Nav.Link href="/">
                <p className={styles.navLink}>HAF Blocks</p>
              </Nav.Link>
              <Nav.Link href="/witnesses" target="_blank">
                <p className={styles.linkWitnesses}>HAF Witnesses</p>
              </Nav.Link>
            </Nav>
            <Form className="d-flex" onSubmit={handleSubmit}>
              <FormControl
                ref={form_value}
                onChange={(e) => e.target.value}
                type="search"
                placeholder="Search user, block, transaction"
                className="me-2"
                aria-label="Search"
              />
              <Button onClick={handleSubmit} variant="outline-danger">
                Search
              </Button>
            </Form>
          </Navbar.Collapse>
        </Container>
      </Navbar>
    </>
  );
}
