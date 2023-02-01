import React from "react";
import BasicModal from "./BasicModal";

export default function MultiSelectFilters({ show_filters, set_show_filters }) {
  return (
    <BasicModal
      open={show_filters}
      handleClose={() => set_show_filters(false)}
    />
  );
}
