import React, { useContext } from "react";
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
import { BlockContext } from "../../../contexts/blockContext";
import {
  handle_filters,
  handle_virtual_filters,
  MenuProps,
  VIRTUAL_FILTERS,
} from "../../../functions/operation_filters_func";

export default function BlockOpsFilters({
  show_modal,
  set_show_modal,
  vfilters,
  set_v_filters,
}) {
  const { block_op_types, block_op_filters, set_block_op_filters } =
    useContext(BlockContext);

  return (
    <div>
      <Modal show={show_modal} onHide={() => set_show_modal(false)}>
        <Modal.Header closeButton>
          <h5 className="modal-title">Operations filters</h5>
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
              onChange={(event) => handle_filters(event, set_block_op_filters)}
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
              onChange={(event) =>
                handle_virtual_filters(
                  event,
                  block_op_types,
                  set_v_filters,
                  set_block_op_filters
                )
              }
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
        <Modal.Footer>
          {" "}
          <Button
            variant="contained"
            color="secondary"
            onClick={() => set_show_modal(false)}
          >
            Close
          </Button>
        </Modal.Footer>
      </Modal>
    </div>
  );
}
