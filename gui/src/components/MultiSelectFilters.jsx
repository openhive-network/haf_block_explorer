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
  TextField,
} from "@mui/material";
import { UserProfileContext } from "../contexts/userProfileContext";
import { AdapterMoment } from "@mui/x-date-pickers/AdapterMoment";
import { LocalizationProvider } from "@mui/x-date-pickers/LocalizationProvider";
import { MobileDatePicker } from "@mui/x-date-pickers/MobileDatePicker";

const ITEM_HEIGHT = 48;
const ITEM_PADDING_TOP = 8;
const MenuProps = {
  PaperProps: {
    style: {
      maxHeight: ITEM_HEIGHT * 4.5 + ITEM_PADDING_TOP,
      width: 250,
    },
  },
};

const VIRTUAL_FILTERS = ["Virtual", "Not-Virtual"];

export default function MultiSelectFilters({ show_filters, set_show_filters }) {
  const { op_types, set_op_filters, op_filters } =
    useContext(UserProfileContext);
  const [vfilters, set_v_filters] = useState("");

  const handleChange = (event) => {
    const {
      target: { value },
    } = event;
    set_op_filters(value);
  };

  const handleVirtual = (event) => {
    const {
      target: { value },
    } = event;
    set_v_filters(value);
  };

  const notVirtualOps = op_types?.map((op) => op[2] === false && op[0]);
  const virtualOps = op_types?.map((op) => op[2] === true && op[0]);
  const trim_not_virtual = notVirtualOps?.filter((m) => m !== false);
  const trim_virtual = virtualOps?.filter((m) => m !== false);

  useEffect(() => {
    if (vfilters === "Virtual") {
      set_op_filters(trim_virtual);
    }
    if (vfilters === "Not-Virtual") {
      set_op_filters(trim_not_virtual);
    }
  }, [vfilters, set_op_filters, trim_virtual, trim_not_virtual]);

  //Calendar
  const [dateSelectError, setDateSelectError] = useState("");
  const [startDateState, setStartDateState] = useState(null);

  const changeStartDate = (e) => {
    setStartDateState(e);
  };
  const [endDateState, setEndDateState] = useState(null);
  const changeEndDate = (e) => {
    setEndDateState(e);
  };
  const trimDate = (date) => date?.toISOString().split("T")[0];

  const handleFilterBtn = () => {
    set_show_filters(false);
    setDateSelectError("");
    if (startDateState?._d > endDateState?._d) {
      set_show_filters(true);
      setDateSelectError("End date can't be higher than start date ");
    }
  };
  // console.log(trimDate(startDateState?._d));
  return (
    <div>
      <Modal show={show_filters} onHide={() => set_show_filters(false)}>
        <Modal.Header closeButton>
          <h5 className="modal-title">Modal title</h5>
        </Modal.Header>
        <Modal.Body>
          <FormControl sx={{ m: 1, width: 300 }}>
            <InputLabel id="demo-multiple-checkbox-label">
              Operations
            </InputLabel>
            <Select
              labelId="demo-multiple-checkbox-label"
              id="demo-multiple-checkbox"
              multiple
              value={op_filters}
              onChange={handleChange}
              input={<OutlinedInput label="Operations" />}
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
              Check virtual
            </InputLabel>
            <Select
              labelId="demo-multiple-checkbox-label2"
              id="demo-multiple-checkbox2"
              value={vfilters}
              onChange={handleVirtual}
              input={<OutlinedInput label="Check virtual" />}
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

            <div className="mt-4">
              <LocalizationProvider dateAdapter={AdapterMoment}>
                <Stack spacing={3}>
                  <MobileDatePicker
                    label="Start Date"
                    inputFormat="MM/dd/yyyy"
                    value={startDateState}
                    onChange={changeStartDate}
                    renderInput={(params) => <TextField {...params} />}
                  />
                  <MobileDatePicker
                    label="End Date"
                    inputFormat="MM/dd/yyyy"
                    value={endDateState}
                    onChange={changeEndDate}
                    renderInput={(params) => <TextField {...params} />}
                  />
                </Stack>
              </LocalizationProvider>
              <p style={{ color: "red" }}>{dateSelectError}</p>
            </div>
          </FormControl>
        </Modal.Body>
        <Modal.Footer>
          <Button onClick={handleFilterBtn}>Filter</Button>
        </Modal.Footer>
      </Modal>
    </div>
  );
}
