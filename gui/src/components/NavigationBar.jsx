import React, { useEffect, useRef, useState, useContext } from "react";
import { Navbar, Container, Form, FormControl, Button } from "react-bootstrap";
import axios from "axios";
import { useNavigate } from "react-router-dom";
import { ApiContext } from "../context/apiContext";
export default function NavigationBar() {
  const form_value = useRef("");
  const [value, setValue] = useState("");
  const navigate = useNavigate();
  const [accName, setAccName] = useState("");
  const [isAccountFound, setIsAccountFound] = useState(null);
  const { setUser_profile_data, user_profile_data } = useContext(ApiContext);

  useEffect(() => {
    if (value !== "") {
      axios({
        method: "post",
        url: "https://api.hive.blog",
        data: {
          jsonrpc: "2.0",
          method: "condenser_api.get_accounts",
          params: [[value]],
          id: 1,
        },
      })
        .then((res) => setAccName(res.data.result[0].name))
        .catch((err) =>
          err ? setIsAccountFound(false) : setIsAccountFound(true)
        );
    }

    if (value === accName && value !== "") {
      axios({
        method: "post",
        url: "https://api.hive.blog",
        data: {
          jsonrpc: "2.0",
          method: "account_history_api.get_account_history",
          params: {
            account: accName,
            start: -1,
          },
          id: 1,
        },
      }).then((res) => setUser_profile_data(res.data.result.history));

      navigate(`user/${accName}`);
    }
  }, [value, accName]);

  function handleSubmit(e) {
    e.preventDefault();
    let val = form_value.current.value;
    setValue(val);
    form_value.current.value = "";
  }
  // console.log(!user_profile_data);
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
      {isAccountFound === false && <p>No Account Found</p>}
    </>
  );
}
