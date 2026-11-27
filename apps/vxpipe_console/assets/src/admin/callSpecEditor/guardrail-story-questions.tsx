import { Fragment, useState } from "react";
import { Pencil, Plus, Trash2, Info } from "lucide-react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { Input } from "../components/ui/input";
import { Item, ItemActions, ItemContent, ItemGroup, ItemSeparator, ItemTitle } from "../components/ui/item";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { Textarea } from "../components/ui/textarea";

export type Question = { id: string; text: string; threshold: string };
const defaultThreshold = "0.70";

function QuestionDialog({ initial, save, close, remove }: { initial: Question; remove: () => void; save: (question: Question) => void; close: () => void }) {
  const [text, setText] = useState(initial.text);
  const [threshold, setThreshold] = useState(initial.threshold);
  return <Dialog open onOpenChange={open => { if (!open) close(); }}>
    <DialogContent className="sm:max-w-md">
      <DialogHeader><DialogTitle>{initial.id ? "Edit question" : "Add question"}</DialogTitle>
        <DialogDescription>Write a question where “yes” means the guardrail should block.</DialogDescription>
      </DialogHeader>
      <form className="space-y-4" onSubmit={event => {
        event.preventDefault();
        if (text.trim()) save({ ...initial, text: text.trim(), threshold: threshold ? Number(threshold).toFixed(2) : "" });
      }}>
        <label className="grid gap-1.5 text-sm font-medium">Question
          <Textarea required value={text} onChange={event => setText(event.target.value)} />
        </label>
        <div className="space-y-1">
          <label className="grid gap-1.5 text-sm font-medium">Confidence threshold
            <Input type="number" min="0" max="1" step="0.01" placeholder={defaultThreshold} value={threshold}
              aria-describedby="question-confidence-help" onChange={event => setThreshold(event.target.value)} />
          </label>
          <p id="question-confidence-help" className="text-xs text-muted-foreground">Optional. Defaults to {defaultThreshold}.</p>
        </div>
        <DialogFooter className="flex-row flex-wrap items-center">
          {initial.id && <Button type="button" variant="ghost" className="mr-auto text-destructive" onClick={remove}>Delete question</Button>}
          <Button type="button" variant="outline" onClick={close}>Cancel</Button>
          <Button type="submit" disabled={!text.trim()}>Save question</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>;
}

export function QuestionSection({ title, timing, questions, change, unavailable }: {
  title: string; timing?: string; questions: Question[]; change: (questions: Question[]) => void; unavailable?: string;
}) {
  const [editing, setEditing] = useState<Question | null>(null);
  return <section aria-label={title} className="space-y-3">
    <header className="flex items-center justify-between gap-3">
      <div className="flex min-w-0 items-center gap-1">
        <h3 className="min-w-0 text-sm font-semibold">{title}</h3>
        <Popover>
          <PopoverTrigger asChild><Button size="icon-sm" variant="ghost" aria-label={`About ${title}`} className="shrink-0 text-muted-foreground"><Info /></Button></PopoverTrigger>
          <PopoverContent aria-label={`About ${title}`} align="start" collisionPadding={12} className="w-64 max-w-[calc(100vw-2rem)] p-3 text-sm">{unavailable || timing}</PopoverContent>
        </Popover>
      </div>
      {!unavailable && <Button size="sm" variant="outline" onClick={() => setEditing({ id: "", text: "", threshold: "" })}>
          <Plus />Add question
      </Button>}
    </header>
    {!unavailable && <>
      {questions.length > 0 && <ItemGroup className="rounded-md border border-border/60">
        {questions.map((question, index) => <Fragment key={question.id}>{index > 0 && <ItemSeparator />}
          <Item size="sm" className="flex-nowrap gap-2 py-2">
            <ItemContent className="min-w-0"><ItemTitle className="wrap-anywhere font-normal">{question.text}</ItemTitle></ItemContent>
            <ItemActions><Button variant="ghost" size="icon-sm" aria-label={`Edit question: ${question.text}`} onClick={() => setEditing(question)}><Pencil /></Button>
              <Button variant="ghost" size="icon-sm" aria-label={`Delete question: ${question.text}`}
                onClick={() => change(questions.filter(candidate => candidate.id !== question.id))}><Trash2 /></Button>
            </ItemActions>
          </Item>
        </Fragment>)}
      </ItemGroup>}
    </>}
    {editing && <QuestionDialog initial={editing} close={() => setEditing(null)} remove={() => {
      change(questions.filter(q => q.id !== editing.id)); setEditing(null);
    }} save={question => {
      const next = question.id ? questions.map(q => q.id === question.id ? question : q)
        : [...questions, { ...question, id: crypto.getRandomValues(new Uint32Array(2)).join("-") }];
      change(next); setEditing(null);
    }} />}
  </section>;
}
