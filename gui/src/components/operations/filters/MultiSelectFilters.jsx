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
import { UserProfileContext } from "../../../contexts/userProfileContext";
import { AdapterMoment } from "@mui/x-date-pickers/AdapterMoment";
import { LocalizationProvider } from "@mui/x-date-pickers/LocalizationProvider";
import { MobileDatePicker } from "@mui/x-date-pickers/MobileDatePicker";
import {
  handle_filters,
  handle_virtual_filters,
  change_start_date,
  change_end_date,
  // handle_date_filter_btn,
  MenuProps,
  VIRTUAL_FILTERS,
} from "../../../functions/operation_filters_func";

export default function MultiSelectFilters({ show_filters, set_show_filters }) {
  const {
    op_types,
    set_op_filters,
    op_filters,
    startDateState,
    setStartDateState,
    endDateState,
    setEndDateState,
  } = useContext(UserProfileContext);
  const [vfilters, set_v_filters] = useState("");
  useEffect(() => {
    if (endDateState?._d < startDateState?._d) {
      setStartDateState(null);
      setEndDateState(null);
    }
  }, [endDateState, startDateState, setStartDateState, setEndDateState]);

  return (
    <div>
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
          <FormControl sx={{ m: 1, width: 300 }}>
            <div className="mt-4">
              <LocalizationProvider dateAdapter={AdapterMoment}>
                <Stack spacing={3}>
                  <MobileDatePicker
                    label="Start Date"
                    inputFormat="DD/MM/yyyy"
                    value={startDateState}
                    onChange={(event) =>
                      change_start_date(event, setStartDateState)
                    }
                    renderInput={(params) => <TextField {...params} />}
                  />
                  <MobileDatePicker
                    label="End Date"
                    inputFormat="DD/MM/yyyy"
                    value={endDateState}
                    onChange={(event) =>
                      change_end_date(event, setEndDateState)
                    }
                    renderInput={(params) => <TextField {...params} />}
                  />
                </Stack>
              </LocalizationProvider>
            </div>
          </FormControl>
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
