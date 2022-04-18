import * as React from "react";
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
import Pop from "../components/userOperartions/Pop";
import { Row, Col } from "react-bootstrap";

export default function TrxData({ next, prev, first, last, rows_per_page }) {
  const [page, setPage] = React.useState(0);
  const [rowsPerPage, setRowsPerPage] = React.useState(rows_per_page);
  const { user_profile_data } = React.useContext(ApiContext);

  const columns = [
    { id: "name", label: "Op Number", minWidth: 170 },
    // { id: "code", label: "Op Block", minWidth: 170 },
    {
      id: "population",
      label: "Op Type",
      minWidth: 170,
      align: "left",
      format: (value) => value.toLocaleString("en-US"),
    },
    {
      id: "size",
      label: "Op Value",
      minWidth: 170,
      align: "left",
      format: (value) => value.toLocaleString("en-US"),
    },
    {
      id: "info",
      label: "More Details",
      minWidth: 170,
      align: "left",
      format: (value) => value.toLocaleString("en-US"),
    },
  ];

  function createData(name, population, size, info) {
    return { name, population, size, info };
  }

  const op_number = user_profile_data?.map((history) => history[0]);
  const op_block = user_profile_data?.map((history) => history[1].block);
  const op_type = user_profile_data?.map((history) => history[1].op.type);
  const op_value = user_profile_data?.map((history) => history[1].op.value.id);
  const more_details = <Pop />;
  const rows = [];

  for (let i = 0; i < user_profile_data?.length; i++) {
    if (user_profile_data.length !== 0) {
      rows.push(
        createData(op_number[i], op_type[i], op_value[i], more_details)
      );
    } else {
      return rows.push("Loading Data");
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
    <Row>
      <Col xs={1} />
      <Col xs={12} md={3}>
        <Paper sx={{ height: 520 }} style={{ background: "lightblue" }}>
          NEW PAPER
        </Paper>
      </Col>
      <Col xs={12} md={7}>
        <Paper
          sx={{ width: "100%" }}
          style={{
            border: "15px solid lightblue",
            borderRadius: "10px",
          }}
        >
          <TableContainer sx={{ maxHeight: 440 }}>
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
                  .map((row) => {
                    return (
                      <TableRow
                        hover
                        role="checkbox"
                        tabIndex={-1}
                        key={row.code}
                      >
                        {columns.map((column, i) => {
                          const value = row[column.id];
                          return (
                            <TableCell key={i} align={column.align}>
                              {column.format && typeof value === "number"
                                ? column.format(value)
                                : value}
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
              rowsPerPageOptions={[10, 25, 100, 1000]}
              component="div"
              count={rows.length}
              rowsPerPage={rowsPerPage}
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
      <Col xs={1} />
    </Row>
  );
}
