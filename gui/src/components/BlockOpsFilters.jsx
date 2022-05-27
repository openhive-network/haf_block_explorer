import React, { useState, useContext } from "react";
import { Modal } from "react-bootstrap";
import {
  FormControl,
  InputLabel,
  Select,
  OutlinedInput,
  MenuItem,
  Checkbox,
  ListItemText,
} from "@mui/material";
import { BlockContext } from "../contexts/blockContext";

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
const VIRTUAL_FILTERS = ["Virtual", "Not-Virtual", "All"];

export default function BlockOpsFilters({ show_modal, set_show_modal }) {
  const { block_op_types, block_op_filters, set_block_op_filters } =
    useContext(BlockContext);
  const [vfilters, set_v_filters] = useState("");

  const handleChange = (event) => {
    const {
      target: { value },
    } = event;
    set_block_op_filters(value);
  };

  const handleVirtual = (event) => {
    const {
      target: { value },
    } = event;
    const notVirtualOps = block_op_types?.map((op) => op[2] === false && op[0]);
    const virtualOps = block_op_types?.map((op) => op[2] === true && op[0]);
    const trim_not_virtual = notVirtualOps?.filter((m) => m !== false);
    const trim_virtual = virtualOps?.filter((m) => m !== false);

    set_v_filters(value);
    if (value === "Virtual") {
      set_block_op_filters(trim_virtual);
    }
    if (value === "Not-Virtual") {
      set_block_op_filters(trim_not_virtual);
    }
    if (value === "All") {
      set_block_op_filters([]);
    }
  };

  return (
    <div>
      <Modal show={show_modal} onHide={() => set_show_modal(false)}>
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
              value={block_op_filters}
              onChange={handleChange}
              input={<OutlinedInput label="Operations" />}
              renderValue={(selected) => "Active filters : " + selected.length}
              MenuProps={MenuProps}
            >
              {block_op_types?.map((name, i) => {
                const trim_op_name = name[1]?.replaceAll("_", " ");
                return (
                  <MenuItem key={i} value={name[0]}>
                    <Checkbox
                      checked={block_op_filters.indexOf(name[0]) > -1}
                    />
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
          </FormControl>
        </Modal.Body>
        <Modal.Footer></Modal.Footer>
      </Modal>
    </div>
  );
}
