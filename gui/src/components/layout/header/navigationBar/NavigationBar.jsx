import React, { useEffect, useState, useContext } from "react";
import { Form, Button, Container, Nav, Navbar } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import { BlockContext } from "../../../../contexts/blockContext";
import { UserProfileContext } from "../../../../contexts/userProfileContext";
import { TranasctionContext } from "../../../../contexts/transactionContext";
import axios from "axios";
import styles from "./navigationBar.module.css";
import { TextField } from "@mui/material";
import { StyledAutocomplete } from "./StyledAutocomplete";

export default function NavigationBar() {
  const navigate = useNavigate();
  const [value, setValue] = useState("");
  const { setBlockNumber } = useContext(BlockContext);
  const { setUserProfile } = useContext(UserProfileContext);
  const { setTransactionId } = useContext(TranasctionContext);
  const [check_input, set_check_input] = useState("");
  const [nameSuggestions, setNameSuggestions] = useState([]);

  function handleSubmit(e) {
    e.preventDefault();
    if (check_input.input_value === value) {
      switch (check_input.input_type) {
        case "block_num":
          setBlockNumber(value);
          navigate(`/block/${value}`);
          break;
        case "account_name":
          setUserProfile(value);
          navigate(`/user/${value}`);
          break;
        case "transaction_hash":
          setTransactionId(value);
          navigate(`/transaction/${value}`);
          break;
        case "block_hash":
          setBlockNumber(check_input.input_value);
          navigate(`/block/${check_input.input_value}`);
          break;
        default:
          navigate("/error");
      }
    }
    setValue("");
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

  useEffect(() => {
    if (check_input.input_type === "account_name_array") {
      setNameSuggestions(check_input.input_value);
    }
  }, [check_input]);

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
                <p className={styles.navLink}>Blocks</p>
              </Nav.Link>
              <Nav.Link href="/witnesses" target="_blank">
                <p className={styles.linkWitnesses}>Witnesses</p>
              </Nav.Link>
            </Nav>

            <Form className="d-flex" onSubmit={handleSubmit}>
              <StyledAutocomplete
                className={styles.searchBox}
                inputValue={value || ""}
                onInputChange={(e) => setValue(e.target.value)}
                onChange={(e, value) => setValue(value)}
                clearIcon={false}
                freeSolo
                options={nameSuggestions}
                renderInput={(params) => (
                  <TextField
                    {...params}
                    label="Search user, block, transaction"
                  />
                )}
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
