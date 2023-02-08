import { LinearProgress } from "@mui/material";

export default function LinearLoader({ isLoading }) {
  return isLoading && <LinearProgress />;
}
