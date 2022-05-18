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
} from "@mui/material";
import { Form } from "react-bootstrap";
import { UserProfileContext } from "../contexts/userProfileContext";
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

  // const op_names = op_types.map((type) => type[1]);
  // const op_number = op_types.map((type) => type[0]);
  // const op_virtual = op_types.map((type) => type[2]);

  // const is_virtual = check_virtual.filter((v) => v === false);
  // const [v, setV] = useState([]);
  // const [nv, setNv] = useState([]);

  // for (let i = 0; i < op_types.length; i++) {
  //   if (vfilters.includes("Virtual") === true) {
  //     setV(op_number[i]);
  //   } else if (vfilters.includes("Not-Virtual") === true) {
  //     setNv(op_number[i]);
  //   }
  // }

  const notVirtualOps = op_types.map((op) => op[2] === false && op[0]);
  const virtualOps = op_types.map((op) => op[2] === true && op[0]);
  const trim_not_virtual = notVirtualOps.filter((m) => m !== false);
  const trim_virtual = virtualOps.filter((m) => m !== false);
  // console.log(trim_not_virtual);
  // console.log(trim_virtual);

  useEffect(() => {
    if (vfilters === "Virtual") {
      set_op_filters(trim_virtual);
    }
    if (vfilters === "Not-Virtual") {
      set_op_filters(trim_not_virtual);
    }
  }, [vfilters]);

  return (
    <div>
      <Modal show={show_filters}>
        <Modal.Header>
          <h5 className="modal-title">Modal title</h5>
          {/* <Button onClick={() => setV(!v)}>show Virtual</Button>
          <Button onClick={() => setNv(!nv)}>show non-Virtual</Button> */}
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
              // multiple
              value={vfilters}
              onChange={handleVirtual}
              input={<OutlinedInput label="Check virtual" />}
              // renderValue={(selected) => selected}
              MenuProps={MenuProps}
            >
              {VIRTUAL_FILTERS.map((filter, i) => {
                return (
                  <MenuItem key={i} value={filter}>
                    {/* <Checkbox checked={vfilters.indexOf(filter) > -1} /> */}
                    {filter}
                  </MenuItem>
                );
              })}
            </Select>

            <Form.Group controlId="dob">
              <Form.Label>Select Date</Form.Label>
              <Form.Control
                type="date"
                name="dob"
                placeholder="Date of Birth"
              />
            </Form.Group>
          </FormControl>
        </Modal.Body>
        <Modal.Footer>
          <Button onClick={() => set_show_filters(false)}>Close</Button>
        </Modal.Footer>
      </Modal>
    </div>
  );
}
