import React, { useState } from "react";
import Paper from "@mui/material/Paper";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import TableHead from "@mui/material/TableHead";
import TablePagination from "@mui/material/TablePagination";
import TableRow from "@mui/material/TableRow";
import Button from "@mui/material/Button";
import { ApiContext } from "../context/apiContext";
// import Pop from "../components/userOperartions/Pop";
import { Row, Col, Offcanvas } from "react-bootstrap";
// import { Button, Offcanvas } from "react-bootstrap";

export default function TrxData({
  next,
  prev,
  first,
  last,
  active_op_filters,
  acc_history_limit,
}) {
  const [page, setPage] = React.useState(0);
  const [rowsPerPage, setRowsPerPage] = React.useState(acc_history_limit);
  const { user_profile_data } = React.useContext(ApiContext);
  const [show, setShow] = useState(false);

  // const handleClose = () => setShow(false);
  const handleShow = () => setShow(!show);

  const columns = [
    { id: "name", label: "Op Number", minWidth: 170 },
    // { id: "code", label: "Op Block", minWidth: 170 },
    {
      id: "op_type",
      label: "Op Type",
      minWidth: 170,
      align: "left",
    },
    {
      id: "op_value",
      label: "Op Value",
      minWidth: 170,
      align: "left",
    },
    {
      id: "op_details",
      label: "More Details",
      minWidth: 170,
      align: "left",
    },
  ];

  function createData(name, op_type, op_value, op_details) {
    return { name, op_type, op_value, op_details };
  }

  const op_number = user_profile_data?.map((history) => history[0]);
  const op_block = user_profile_data?.map((history) => history[1].block);
  const op_type = user_profile_data?.map((history) => history[1].op.type);
  const op_value = user_profile_data?.map((history) => history[1].op.value.id);
  const more_details = <Button onClick={handleShow}>show</Button>;
  const rows = [];
  for (let i = 0; i < user_profile_data?.length; i++) {
    if (user_profile_data.length !== 0) {
      rows.push(
        createData(op_number[i], op_type[i], op_value[i], more_details)
      );
    }
  }

  const handleChangePage = (event, newPage) => {
    setPage(newPage);
  };

  const handleChangeRowsPerPage = (event) => {
    setRowsPerPage(+event.target.value);
    setPage(0);
  };

  return (
    <Row className="mt-5">
      <Col>
        <Paper>
          <TableContainer>
            <Table stickyHeader aria-label="sticky table">
              <TableHead>
                <TableRow>
                  {columns.map((column) => (
                    <TableCell
                      key={column.id}
                      align={column.align}
                      style={{ minWidth: column.minWidth }}
                    >
                      {column.label}
                    </TableCell>
                  ))}
                </TableRow>
              </TableHead>
              <TableBody>
                {rows
                  .slice(page * rowsPerPage, page * rowsPerPage + rowsPerPage)
                  .map((row, i) => {
                    const filtered_op = active_op_filters?.filter(
                      (o) => o == row.op_type
                    );
                    const newOp = filtered_op[0] === row.op_type;

                    return (
                      <TableRow
                        hidden={
                          newOp === false && active_op_filters.length !== 0
                        }
                        hover
                        role="checkbox"
                        key={row.op_number}
                      >
                        {columns.map((column, i) => {
                          const value = row[column.id];
                          return (
                            <TableCell key={i} align={column.align}>
                              {value}
                            </TableCell>
                          );
                        })}
                      </TableRow>
                    );
                  })}
              </TableBody>
            </Table>
          </TableContainer>

          <div style={{ display: "flex", justifyContent: "space-around" }}>
            <TablePagination
              rowsPerPageOptions={acc_history_limit}
              component="div"
              count={rows.length}
              rowsPerPage={acc_history_limit}
              page={page}
              onPageChange={handleChangePage}
              onRowsPerPageChange={handleChangeRowsPerPage}
            />
            <div style={{ display: "flex" }}>
              <Button onClick={first}>First</Button>
              <Button onClick={prev}>Prev</Button>
              <Button onClick={next}>Next</Button>
              <Button onClick={last}>Last</Button>
            </div>
          </div>
        </Paper>
      </Col>
      <div className="userpage__offcanvas" hidden={!show}>
        More Detailed Info about current transaction
      </div>
    </Row>
  );
}
