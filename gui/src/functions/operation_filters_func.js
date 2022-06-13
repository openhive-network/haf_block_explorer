export const ITEM_HEIGHT = 48;
export const ITEM_PADDING_TOP = 8;
export const MenuProps = {
  PaperProps: {
    style: {
      maxHeight: ITEM_HEIGHT * 4.5 + ITEM_PADDING_TOP,
      width: 250,
    },
  },
};
export const VIRTUAL_FILTERS = ["Virtual", "Not-Virtual", "All"];

// Operations filters
export const handle_filters = (event, set_op_filters) => {
  const {
    target: { value },
  } = event;
  set_op_filters(value);
};
//Virtual operations filters
export const handle_virtual_filters = (
  event,
  op_types,
  set_v_filters,
  set_op_filters
) => {
  const notVirtualOps = op_types?.map((op) => op[2] === false && op[0]);
  const virtualOps = op_types?.map((op) => op[2] === true && op[0]);
  const trim_not_virtual = notVirtualOps?.filter((m) => m !== false);
  const trim_virtual = virtualOps?.filter((m) => m !== false);
  const {
    target: { value },
  } = event;

  set_v_filters(value);
  if (value === "Virtual") {
    set_op_filters(trim_virtual);
  }
  if (value === "Not-Virtual") {
    set_op_filters(trim_not_virtual);
  }
  if (value === "All") {
    set_op_filters([]);
  }
};
//Date filters
export const change_start_date = (e, setStartDateState) => {
  setStartDateState(e);
};
export const change_end_date = (e, setEndDateState) => {
  setEndDateState(e);
};
export const trim_date = (date, moment) =>
  moment(date?._d).format().split("T")[0];

export const handle_date_filter_btn = (
  set_show_filters,
  setDateSelectError,
  startDateState,
  endDateState
) => {
  set_show_filters(false);
  setDateSelectError("");
  if (startDateState?._d > endDateState?._d) {
    set_show_filters(true);
    setDateSelectError("End date can't be higher than start date ");
  }
};
