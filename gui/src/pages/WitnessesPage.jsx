import React, { useContext, useState } from "react";
import { styled } from "@mui/material/styles";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell, { tableCellClasses } from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Paper from "@mui/material/Paper";
import { tidyNumber } from "../functions/calculations";
import { Container, Row, Col } from "react-bootstrap";
import { WitnessContext } from "../contexts/witnessContext";
import moment from "moment";
import Button from "@mui/material/Button";
import { Link } from "react-router-dom";
import Loader from "../components/loader/Loader";
import { sort } from "../functions/witness_page_func";
export default function DataTable() {
  document.title = "HAF | Witnesses";
  const { witnessData } = useContext(WitnessContext);
  const cell_names = [
    "Name",
    "Votes (M)",
    "Voters",
    "Missed",
    "Last_block",
    "APR",
    "Price_feed",
    "Bias",
    "Price_hive",
    "Price_hbd",
    "Feed_age",
    "Ac_fee",
    "Ac_avail",
    "Ac_budget",
    "Ac_decay",
    "Block_size",
    "Version",
  ];
  const [count, setCount] = useState(1);

  const StyledTableCell = styled(TableCell)(({ theme }) => ({
    [`&.${tableCellClasses.head}`]: {
      backgroundColor: theme.palette.common.black,
      color: theme.palette.common.white,
    },
    [`&.${tableCellClasses.body}`]: {
      fontSize: 14,
    },
  }));

  const StyledTableRow = styled(TableRow)(({ theme }) => ({
    "&:nth-of-type(odd)": {
      backgroundColor: theme.palette.action.hover,
    },
    // hide last border
    "&:last-child td, &:last-child th": {
      border: 0,
    },
  }));

  const click = (name) => {
    setCount(count + 1);
    sort(name, count, witnessData);
  };
  return (
    <>
      {witnessData === null ? (
        <Loader />
      ) : (
        <Container>
          <Row>
            <Col>
              <TableContainer style={{ height: "800px" }} component={Paper}>
                <Table
                  stickyHeader
                  style={{ maxWidth: "100vw" }}
                  sx={{ minWidth: 700 }}
                  aria-label="customized table"
                >
                  <TableHead>
                    <TableRow>
                      {cell_names.map((name, i) => (
                        <StyledTableCell key={i}>
                          <Button onClick={() => click(name)}>{name}</Button>
                        </StyledTableCell>
                      ))}
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {witnessData.map((witness, i) => {
                      return (
                        <StyledTableRow key={i}>
                          <StyledTableCell component="th" scope="witness">
                            <Link to={`/user/${witness.owner}`}>
                              {witness.owner}
                            </Link>
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="votes">
                            {tidyNumber(
                              Math.round(witness.votes / 1000000 / 1000000)
                            )}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="voters">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="missed">
                            {tidyNumber(witness.total_missed)}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="last_block">
                            {tidyNumber(witness.last_confirmed_block_num)}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="apr">
                            {Number(witness.props.hbd_interest_rate) / 100}%
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="price_feed">
                            {witness.hbd_exchange_rate.base.split("HBD")[0]}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="bias">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="price_hive">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="price_hbd">
                            ???
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="feed_age">
                            {moment(witness.last_hbd_exchange_update).fromNow()}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="ac_fee">
                            {witness.props.account_creation_fee}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="ac_avail">
                            {Math.round(
                              witness?.available_witness_account_subsidies /
                                10000
                            )}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="ac_budget">
                            {tidyNumber(witness.props.account_subsidy_budget)}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="ac_decay">
                            {tidyNumber(witness.props.account_subsidy_decay)}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="block_size">
                            {tidyNumber(witness.props.maximum_block_size)}
                          </StyledTableCell>
                          <StyledTableCell component="th" scope="version">
                            {witness.hardfork_version_vote}
                          </StyledTableCell>
                        </StyledTableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </TableContainer>
            </Col>
          </Row>
        </Container>
      )}
    </>
  );
}
