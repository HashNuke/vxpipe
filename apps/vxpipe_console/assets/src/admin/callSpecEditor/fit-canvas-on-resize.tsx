import { useEffect } from "react";
import { useReactFlow, useStore } from "@xyflow/react";

import { flowFitViewOptions } from "./flow-layout";

/** Keep participants in view when the responsive inspector changes the canvas size. */
export function FitCanvasOnResize() {
  const { fitView } = useReactFlow();
  const width = useStore((state) => state.width);
  const height = useStore((state) => state.height);
  useEffect(() => {
    if (width > 0 && height > 0) void fitView(flowFitViewOptions);
  }, [fitView, width, height]);
  return null;
}
