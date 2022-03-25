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
  const [blockNr, setBlockNr] = useState("");
  const [isAccountFound, setIsAccountFound] = useState(true);
  // const [isBlockFound, setIsBlockFound] = useState(true);
  const { setUser_profile_data, setBlock_data, block_data } =
    useContext(ApiContext);

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
        .catch((err) => err && setIsAccountFound(false));
    }
    if (accName === value && value !== "") {
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
      setIsAccountFound(true);
      navigate(`user/${accName}`);
    }
  }, [value, isAccountFound, accName]);

  useEffect(() => {
    if (isAccountFound === false) {
      // setBlockNr(value);
      axios({
        method: "post",
        url: "https://api.hive.blog",
        data: {
          jsonrpc: "2.0",
          method: "block_api.get_block",
          params: { block_num: value },
          id: 1,
        },
      }).then((res) => setBlock_data(res?.data?.result?.block));

      navigate(`block/${value}`);
    }
  }, [value, isAccountFound]);

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
