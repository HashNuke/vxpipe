import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { QuestionSection } from "./guardrail-questions";

afterEach(cleanup);

test("clearing both optional fields keeps the saved question identity and restores defaults", () => {
  const onChange = vi.fn();
  const question = { id: "saved_question", question: "Is the caller authorized?", required_answer: "yes" as const };
  render(<QuestionSection title="Before turn" timing="Checks input." questions={[
    { ...question, response: "Ask for authorization.", probability_threshold: 0.85 },
  ]} onChange={onChange} />);

  fireEvent.click(screen.getByRole("button", { name: `Edit question: ${question.question}` }));
  fireEvent.change(screen.getByLabelText("Probability threshold"), { target: { value: "" } });
  fireEvent.change(screen.getByLabelText(/Response/), { target: { value: "" } });
  fireEvent.click(screen.getByRole("button", { name: "Save question" }));

  expect(onChange).toHaveBeenCalledWith([question]);
});

test("a new question preserves the exact authored feedback", () => {
  const onChange = vi.fn();
  render(<QuestionSection title="Before turn" timing="Checks input." questions={[]} onChange={onChange} />);
  fireEvent.click(screen.getByRole("button", { name: "Add question" }));
  fireEvent.change(screen.getByLabelText("Question"), { target: { value: "Is the caller authorized?" } });
  fireEvent.click(screen.getByRole("radio", { name: "Yes" }));
  const response = "  Ask for authorization.\nUse the caller’s own account.  ";
  fireEvent.change(screen.getByLabelText(/Response/), { target: { value: response } });
  fireEvent.click(screen.getByRole("button", { name: "Save question" }));
  expect(onChange).toHaveBeenCalledWith([{ question: "Is the caller authorized?", required_answer: "yes", response }]);
});
