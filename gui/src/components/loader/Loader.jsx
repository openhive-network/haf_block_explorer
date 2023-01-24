import * as React from "react";
import CircularProgress from "@mui/material/CircularProgress";
import Box from "@mui/material/Box";

const DEFAULT_LOADER_STYLE = {
  display: "flex",
  justifyContent: "center",
  alignItems: "center",
  height: "100%",
};

export default function Loader({ containerStyle, loaderSize }) {
  return (
    <Box sx={containerStyle ?? DEFAULT_LOADER_STYLE}>
      <CircularProgress size={loaderSize} />
    </Box>
  );
}
