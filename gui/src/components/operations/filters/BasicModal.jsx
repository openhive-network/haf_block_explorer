import { useContext, useState, useEffect } from "react";
import Box from "@mui/material/Box";
import Modal from "@mui/material/Modal";
import { UserProfileContext } from "../../../contexts/userProfileContext";
import {
  FormControl,
  InputLabel,
  Select,
  OutlinedInput,
  MenuItem,
  Checkbox,
  ListItemText,
  Stack,
  TextField,
} from "@mui/material";
import { DesktopDatePicker } from "@mui/x-date-pickers/DesktopDatePicker";
import { AdapterMoment } from "@mui/x-date-pickers/AdapterMoment";
import { LocalizationProvider } from "@mui/x-date-pickers/LocalizationProvider";
import {
  handle_filters,
  handle_virtual_filters,
  change_start_date,
  change_end_date,
  MenuProps,
  VIRTUAL_FILTERS,
} from "../../../functions/operation_filters_func";

const style = {
  position: "absolute",
  top: "50%",
  left: "50%",
  transform: "translate(-50%, -50%)",
  width: 500,
  bgcolor: "background.paper",
  borderRadius: 1,
  boxShadow: 24,
  p: 4,
  height: 500,
  overflow: "auto",
  justifyContent: "center",
  alignItems: "center",
};

export default function BasicModal({ open, handleClose }) {
  const {
    op_types,
    set_op_filters,
    op_filters,
    setStartDateState,
    setEndDateState,
    set_pagination,
    user_profile_data,
  } = useContext(UserProfileContext);
  const [vfilters, set_v_filters] = useState("");
  const [endValue, endOnChange] = useState(new Date());
  const [startValue, startOnChange] = useState(new Date());
  const [errorMessage, setErrorMessage] = useState("");

  const handeStartDateChange = (e) => {
    startOnChange(e);
    change_start_date(e, setStartDateState, set_pagination);
  };

  const handleEndDateChange = (e) => {
    endOnChange(e);
    change_end_date(e, setEndDateState, set_pagination);
  };

  useEffect(() => {
    if (user_profile_data.length === 0) {
      setErrorMessage("Please change date");
    } else {
      setErrorMessage("");
    }
  }, [user_profile_data]);

  return (
    <Modal
      open={open}
      onClose={handleClose}
      aria-labelledby="modal-modal-title"
      aria-describedby="modal-modal-description"
    >
      <Box sx={style}>
        <Stack
          sx={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            alignItems: "center",
            height: "100%",
          }}
        >
          <FormControl sx={{ m: 1, width: 300 }}>
            <InputLabel id="demo-multiple-checkbox-label">
              {!op_types?.length ? "Operations loading ..." : "Operations"}
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
                    !op_types?.length ? "Operations loading ..." : "Operations"
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
              {!op_types?.length
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
          <LocalizationProvider dateAdapter={AdapterMoment}>
            <DesktopDatePicker
              label="Start Date"
              inputFormat="DD/MM/yyyy"
              value={startValue}
              onChange={(e) => handeStartDateChange(e)}
              renderInput={(params) => (
                <TextField
                  error
                  helperText={errorMessage}
                  sx={{ m: 1, width: 300 }}
                  {...params}
                />
              )}
            />
            <DesktopDatePicker
              label="End Date"
              inputFormat="DD/MM/yyyy"
              value={endValue}
              onChange={(e) => handleEndDateChange(e)}
              renderInput={(params) => (
                <TextField
                  error
                  helperText={errorMessage}
                  sx={{ m: 1, width: 300 }}
                  {...params}
                />
              )}
            />
          </LocalizationProvider>
        </Stack>
      </Box>
    </Modal>
  );
}
