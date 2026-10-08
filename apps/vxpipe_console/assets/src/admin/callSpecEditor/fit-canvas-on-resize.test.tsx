import { cleanup, render } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FitCanvasOnResize } from "./fit-canvas-on-resize";

const canvas = vi.hoisted(() => ({ width: 900, height: 1000, fitView: vi.fn(async () => true) }));
vi.mock("@xyflow/react", () => ({ useReactFlow: () => ({ fitView: canvas.fitView }), useStore: (selector: (state: typeof canvas) => unknown) => selector(canvas) }));
afterEach(() => { cleanup(); vi.clearAllMocks(); });

test("refits when the available canvas changes from desktop to phone and ignores ordinary rerenders", () => {
  const view = render(<FitCanvasOnResize />);
  canvas.fitView.mockClear();
  view.rerender(<FitCanvasOnResize />); expect(canvas.fitView).not.toHaveBeenCalled();
  canvas.width = 390; canvas.height = 844;
  view.rerender(<FitCanvasOnResize />); expect(canvas.fitView).toHaveBeenCalledOnce();
  expect(canvas.fitView).toHaveBeenCalledWith({ padding: 0.3, maxZoom: 0.85 });
});
