import * as React from "react";
import CircularProgress from "@mui/material/CircularProgress";
import Box from "@mui/material/Box";

const DEFAULT_LOADER_STYLE = {
  display: "flex",
  justifyContent: "center",
  alignItems: "center",
  height: "100%",
};

export default function Loader({ style }) {
  return (
    <Box sx={style ?? DEFAULT_LOADER_STYLE}>
      <CircularProgress />
    </Box>
  );
}
