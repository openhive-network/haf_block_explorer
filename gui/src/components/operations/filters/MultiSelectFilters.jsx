import React, { useState, useContext, useEffect } from "react";
import { Modal } from "react-bootstrap";
import {
  FormControl,
  InputLabel,
  Select,
  OutlinedInput,
  MenuItem,
  Checkbox,
  ListItemText,
  Button,
  Stack,
} from "@mui/material";
import { UserProfileContext } from "../../../contexts/userProfileContext";
import {
  handle_filters,
  handle_virtual_filters,
  change_start_date,
  change_end_date,
  MenuProps,
  VIRTUAL_FILTERS,
} from "../../../functions/operation_filters_func";
import "react-calendar/dist/Calendar.css";
import Calendar from "react-calendar";
import moment from "moment";

export default function MultiSelectFilters({ show_filters, set_show_filters }) {
  const {
    op_types,
    set_op_filters,
    op_filters,
    startDateState,
    setStartDateState,
    endDateState,
    setEndDateState,
    set_pagination,
    user_profile_data,
  } = useContext(UserProfileContext);
  const [vfilters, set_v_filters] = useState("");
  const [endValue, endOnChange] = useState(new Date());
  const [startValue, startOnChange] = useState(new Date());
  const [hideEndDateCalendar, setHideEndDateCalendar] = useState(true);
  const [hideStartDateCalendar, setHideStartDateCalendar] = useState(true);
  const trimEndValue = moment(endDateState).format().split("T")[0];
  const trimStartValue = moment(startDateState).format().split("T")[0];
  const [endDateBtn, setEndDateBtn] = useState("select end date");
  const [startDateBtn, setStartDateBtn] = useState("select start date");
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    if (endDateState) {
      setEndDateBtn("loading ...");
      if (
        user_profile_data[0]?.timestamp.split(" ")[0] ===
        endDateState.toISOString().split("T")[0]
      ) {
        setEndDateBtn(`End date : ${trimEndValue}`);
      }
    }
    if (startDateState) {
      setStartDateBtn(`Start date : ${trimStartValue}`);
    }
    if (endDateState && startDateState >= endDateState) {
      setErrorMessage("End date can't be higher or equal to start date");
      setEndDateBtn("Please change date");
    }
    if (user_profile_data.length === 0) {
      setEndDateBtn("Please change date");
    } else {
      setErrorMessage("");
    }
  }, [
    startDateState,
    endDateState,
    trimEndValue,
    trimStartValue,
    user_profile_data,
  ]);

  return (
    <div style={{ owerflow: "auto" }}>
      <Modal show={show_filters} onHide={() => set_show_filters(false)}>
        <Modal.Header closeButton>
          <h5 className="modal-title">Operations filters</h5>
        </Modal.Header>
        <Modal.Body>
          <FormControl sx={{ m: 1, width: 300 }}>
            <InputLabel id="demo-multiple-checkbox-label">
              {op_types?.length === 0 || op_types === null
                ? "Operations loading ..."
                : "Operations"}
            </InputLabel>
            <Select
              labelId="demo-multiple-checkbox-label"
              id="demo-multiple-checkbox"
              multiple
              value={op_filters}
              onChange={(event) => handle_filters(event, set_op_filters)}
              input={
                <OutlinedInput
                  label={
                    op_types?.length === 0 || op_types === null
                      ? "Operations loading ..."
                      : "Operations"
                  }
                />
              }
              renderValue={(selected) => "Active filters : " + selected.length}
              MenuProps={MenuProps}
            >
              {op_types?.map((name, i) => {
                const trim_op_name = name[1].replaceAll("_", " ");
                return (
                  <MenuItem key={i} value={name[0]}>
                    <Checkbox checked={op_filters.indexOf(name[0]) > -1} />
                    <ListItemText primary={trim_op_name} />
                  </MenuItem>
                );
              })}
            </Select>
          </FormControl>

          <FormControl sx={{ m: 1, width: 300 }}>
            <InputLabel id="demo-multiple-checkbox-label2">
              {op_types?.length === 0 || op_types === null
                ? "Virtual operations loading ..."
                : "Virtual operations"}
            </InputLabel>
            <Select
              labelId="demo-multiple-checkbox-label2"
              id="demo-multiple-checkbox2"
              value={vfilters}
              onChange={(event) =>
                handle_virtual_filters(
                  event,
                  op_types,
                  set_v_filters,
                  set_op_filters
                )
              }
              input={<OutlinedInput label="Virtual operations" />}
              MenuProps={MenuProps}
            >
              {VIRTUAL_FILTERS.map((filter, i) => {
                return (
                  <MenuItem key={i} value={filter}>
                    {filter}
                  </MenuItem>
                );
              })}
            </Select>
          </FormControl>
          <Stack spacing={3}>
            <div
              style={{
                display: "flex",
                justifyContent: "center",
                color: "red",
                fontSize: "20px",
              }}
            >
              <p>{errorMessage}</p>
            </div>

            <Button
              onClick={() => setHideStartDateCalendar(!hideStartDateCalendar)}
            >
              {startDateBtn}
            </Button>
            <div
              style={{ display: "flex", justifyContent: "center" }}
              hidden={hideStartDateCalendar}
            >
              <Calendar
                onChange={(e) => {
                  startOnChange(e);
                  change_start_date(e, setStartDateState, set_pagination);
                }}
                value={startValue}
              />
            </div>
            <Button
              onClick={() => setHideEndDateCalendar(!hideEndDateCalendar)}
            >
              {endDateBtn}
            </Button>
            <div
              style={{ display: "flex", justifyContent: "center" }}
              hidden={hideEndDateCalendar}
            >
              <Calendar
                onChange={(e) => {
                  endOnChange(e);
                  change_end_date(e, setEndDateState, set_pagination);
                }}
                value={endValue}
              />
            </div>
          </Stack>
        </Modal.Body>
        <Modal.Footer>
          <Button
            variant="contained"
            color="secondary"
            onClick={() => set_show_filters(false)}
          >
            Close
          </Button>
        </Modal.Footer>
      </Modal>
    </div>
  );
}
