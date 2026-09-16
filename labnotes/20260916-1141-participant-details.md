# Participant details

## Objective

Keep the configured participant roster visible throughout setup and calls, and make each sidebar
entry open a Participants tab with authorized configuration details.

## Decisions

- Tabs remain ordered Conversation, Variables, Metrics, Participants.
- The rail renders the complete configured roster. `inactive` replaces the unused `waiting` state;
  inactive and departed entries are visually muted and carry no status label.
- Active entries show only meaningful listening or speaking activity.
- Sidebar entries are buttons that select a stable participant identity and open the Participants
  tab.
- Participant configuration includes capabilities, system prompt, transfer policies and tools.
  The Core contract documents the prompt as an authorized projection; milestone rules prohibit
  exposing this configuration to ordinary participant seats.

## Red/green evidence

- Red: the focused React file failed two new cases because the ready state discarded its roster and
  the console had no Participants tab or selectable sidebar rows.
- Green: all 13 focused React tests pass after retaining the configured fixture roster, adding the
  tab/detail component, and separating inactive styling from active presence labels.

## Rendered evidence

- Inspected the dark desktop conversation/Participants view at 1440 px, the ready state with all
  four roster entries muted, and the Participants view at 390 px. The tab content, horizontally
  scrollable mobile roster, long prompt, capability cards, policies and tool cards remain usable.
