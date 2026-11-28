import { keepSubmittedRow } from "./saved-question-ids";
import { useState } from "react";
import { ArrowDown, ArrowUp, Info, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { Input } from "../components/ui/input";
import { Item, ItemActions, ItemContent, ItemGroup, ItemSeparator, ItemTitle } from "../components/ui/item";
import { Label } from "../components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { RadioGroup, RadioGroupItem } from "../components/ui/radio-group";
import { Textarea } from "../components/ui/textarea";
import { formatThreshold, moveGuardrailQuestion, parseThreshold, passPreview } from "./guardrails";
import type { GuardrailQuestion } from "./types";

type DraftQuestion = Partial<GuardrailQuestion> & { question: string };

function QuestionDialog({ title, initial, save, close, remove }: {
  title: string; initial: DraftQuestion; save: (question: GuardrailQuestion) => void; close: () => void; remove?: () => void;
}) {
  const [text, setText] = useState(initial.question);
  const [required, setRequired] = useState<"yes" | "no" | "">(initial.required_answer ?? "");
  const [threshold, setThreshold] = useState(formatThreshold(initial.probability_threshold));
  const [response, setResponse] = useState(initial.response ?? "");
  const [error, setError] = useState<string | null>(null);
  const parsed = parseThreshold(threshold);
  return <Dialog open onOpenChange={(open) => { if (!open) close(); }}>
    <DialogContent className="sm:max-w-md">
      <DialogHeader><DialogTitle>{title}</DialogTitle>
        <DialogDescription>Checked questions can hold a turn or handoff until the reply passes.</DialogDescription>
      </DialogHeader>
      <form className="space-y-4" onSubmit={(event) => {
        event.preventDefault();
        if (!text.trim()) { setError("Write the question to check."); return; }
        if (required !== "yes" && required !== "no") { setError("Choose whether Yes or No is the passing answer."); return; }
        if (parsed === null) { setError("Use a threshold from 0.00 to 1.00 in hundredth increments, or leave it blank for 0.70."); return; }
        save({
          ...(initial.id === undefined ? {} : { id: initial.id }),
          question: text.trim(),
          required_answer: required,
          ...(parsed === undefined ? {} : { probability_threshold: parsed }),
          ...(response.trim() ? { response } : {}),
        });
      }}>
        <div className="grid gap-1.5">
          <Label htmlFor="guardrail-question-text">Question</Label>
          <Textarea id="guardrail-question-text" required value={text} onChange={(event) => setText(event.target.value)} />
        </div>
        <fieldset className="grid gap-1.5">
          <Label asChild><legend className="text-sm font-medium">Required answer</legend></Label>
          <RadioGroup value={required} onValueChange={(value) => setRequired(value as "yes" | "no")} className="flex gap-2" aria-label="Required answer">
            {(["yes", "no"] as const).map((value) => <label key={value} className="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-md border border-control-border px-3 py-2 text-sm font-medium has-checked:border-ring has-checked:bg-accent">
              <RadioGroupItem value={value} aria-label={value === "yes" ? "Yes" : "No"} />{value === "yes" ? "Yes" : "No"}
            </label>)}
          </RadioGroup>
          <p className="text-xs text-muted-foreground">On failure the model receives this exact response if supplied, otherwise the question and its required answer.</p>
        </fieldset>
        <div className="space-y-1">
          <Label htmlFor="guardrail-question-threshold">Probability threshold</Label>
          <Input id="guardrail-question-threshold" type="number" min="0" max="1" step="0.01" placeholder="0.70" value={threshold}
            aria-describedby="guardrail-question-threshold-help" onChange={(event) => setThreshold(event.target.value)} />
          <p id="guardrail-question-threshold-help" className="text-xs text-muted-foreground">
            Optional. Defaults to 0.70. {passPreview(parsed === null || parsed === undefined ? undefined : parsed, required === "" ? undefined : required)}
          </p>
        </div>
        <div className="grid gap-1.5">
          <Label htmlFor="guardrail-question-response">Response <span className="font-normal text-muted-foreground">(optional)</span></Label>
          <Textarea id="guardrail-question-response" value={response} rows={2} onChange={(event) => setResponse(event.target.value)}
            placeholder="What the model should hear when this question fails." />
        </div>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <DialogFooter className="flex-row flex-wrap items-center">
          {remove && <Button type="button" variant="ghost" className="mr-auto text-destructive" onClick={remove}>Delete question</Button>}
          <Button type="button" variant="outline" onClick={close}>Cancel</Button>
          <Button type="submit" disabled={!text.trim()}>Save question</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>;
}

export function QuestionSection({ title, timing, unavailable, questions, disabled, onChange }: {
  title: string; timing: string; unavailable?: string; questions: GuardrailQuestion[]; disabled?: boolean; onChange: (questions: GuardrailQuestion[]) => void;
}) {
  const [editing, setEditing] = useState<{ index: number } | { index: null } | null>(null);
  const draft: DraftQuestion | null = editing === null ? null
    : editing.index === null ? { question: "" }
    : { ...questions[editing.index]! };
  return <section aria-label={title} className="space-y-3">
    <header className="flex items-center justify-between gap-3">
      <div className="flex min-w-0 items-center gap-1">
        <h3 className="min-w-0 text-sm font-semibold">{title}</h3>
        <Popover>
          <PopoverTrigger asChild><Button size="icon-sm" variant="ghost" aria-label={`About ${title}`} className="shrink-0 text-muted-foreground"><Info /></Button></PopoverTrigger>
          <PopoverContent aria-label={`About ${title}`} align="start" collisionPadding={12} className="w-64 max-w-[calc(100vw-2rem)] p-3 text-sm">{unavailable ?? timing}</PopoverContent>
        </Popover>
      </div>
      {!unavailable && !disabled && <Button size="sm" variant="outline" onClick={() => setEditing({ index: null })}>
        <Plus />Add question
      </Button>}
    </header>
    {!unavailable && <>
      {questions.length > 0 && <ItemGroup className="rounded-md border border-border/60">
        {questions.map((question, index) => <div key={question.id ?? `question-${index}`}>
          {index > 0 && <ItemSeparator />}
          <Item size="sm" className="flex-nowrap gap-2 py-2">
            <ItemContent className="min-w-0">
              <ItemTitle className="wrap-anywhere font-normal">{question.question}</ItemTitle>
              <p className="text-xs text-muted-foreground">
                Required: {question.required_answer === "yes" ? "Yes" : "No"} · Threshold {(question.probability_threshold ?? 0.7).toFixed(2)}
                {question.response?.trim() ? " · Custom response" : ""}
              </p>
            </ItemContent>
            {!disabled && <ItemActions>
              <Button variant="ghost" size="icon-sm" aria-label={`Move question up: ${question.question}`} disabled={index === 0}
                onClick={() => onChange(moveGuardrailQuestion(questions, index, -1))}><ArrowUp /></Button>
              <Button variant="ghost" size="icon-sm" aria-label={`Move question down: ${question.question}`} disabled={index === questions.length - 1}
                onClick={() => onChange(moveGuardrailQuestion(questions, index, 1))}><ArrowDown /></Button>
              <Button variant="ghost" size="icon-sm" aria-label={`Edit question: ${question.question}`} onClick={() => setEditing({ index })}><Pencil /></Button>
              <Button variant="ghost" size="icon-sm" aria-label={`Delete question: ${question.question}`}
                onClick={() => onChange(questions.filter((_, candidate) => candidate !== index))}><Trash2 /></Button>
            </ItemActions>}
          </Item>
        </div>)}
      </ItemGroup>}
    </>}
    {draft && editing && <QuestionDialog title={editing.index === null ? "Add question" : "Edit question"} initial={draft} close={() => setEditing(null)}
      remove={editing.index === null ? undefined : () => {
        onChange(questions.filter((_, index) => index !== editing.index));
        setEditing(null);
      }}
      save={(question) => {
        onChange(editing.index === null
          ? [...questions, question]
          : questions.map((entry, index) => index === editing.index ? keepSubmittedRow(entry, question) : entry));
        setEditing(null);
      }} />}
  </section>;
}
