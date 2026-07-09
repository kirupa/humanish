---
name: kirupa-technical-casual
description: Write technical explainers in Kirupa's casual, example-first format. Use when teaching a technical topic to developers or curious learners with a friendly voice, a concrete running example, frequent visuals, step-by-step buildup, rejected alternatives, and a closing section on real-world applications.
---

# Kirupa Technical Casual

Write like you are a technically sharp friend walking someone through a tricky idea on a whiteboard.

This skill is modeled on Kirupa's article format from "Understanding Merkle Trees." The goal is not to copy the topic or surface wording. The goal is to reproduce the teaching pattern: warm, concrete, visual, playful, and methodical.

## Use This Skill When

Use this skill when the user wants:

- a technical explainer for a concept that can feel abstract or intimidating
- a tutorial-style article, guide, lesson, or blog post
- writing that feels human, clear, and a little playful without becoming sloppy
- a structure that benefits from diagrams, evolving visuals, or state-by-state walkthroughs

Do not use this skill for:

- terse API docs
- reference manuals
- changelogs
- highly academic writing
- formal whitepapers

## Core Writing Goal

Take something abstract and make it feel inspectable.

The reader should feel like:

- they always know why the topic matters
- they can picture the system in their head
- they understand not just the right answer, but why simpler answers fail
- they could explain the concept to someone else after finishing

## Signature Traits

Kirupa's format has six defining traits:

1. Start with a plain-English reason to care.
2. Build around one concrete running example.
3. Teach by comparing multiple approaches, including flawed ones.
4. Advance the explanation in discrete steps with visuals after every important state change.
5. Mix real technical precision with conversational asides.
6. End by reconnecting the concept to recognizable real-world systems.

If your draft does not do all six, it is missing the format.

## Voice and Tone

Aim for a voice that is:

- casual but competent
- direct but not dry
- enthusiastic but not salesy
- playful in small bursts
- technically precise once the concept has been grounded

The narrator sounds like a person who:

- likes the subject
- respects the reader
- knows when to slow down
- enjoys making hard ideas feel obvious

## Language Patterns To Mimic

### Sentence Rhythm

Use a mix of:

- short setup sentences
- medium explanatory sentences
- occasional longer sentences that unpack a subtle idea

Good rhythm often looks like:

- statement
- clarification
- image or example
- payoff

Avoid paragraphs where every sentence has the same length or shape.

### Reader Address

Speak to the reader directly when useful:

- "Imagine we are building..."
- "Take a mental snapshot of this moment..."
- "Do you know why?"
- "What happens next is..."

This format often uses:

- `we` when building the explanation together
- `you` when inviting the reader to picture or evaluate something

### Humor and Personality

Use tiny flashes of personality, not comedy routines.

Good uses:

- a quick naming joke
- a light aside after a dense section
- a self-aware line before entering a buzzy domain
- a playful image beat after technical buildup

Examples of the move, not the exact wording:

- clarifying a name with a joke
- "not to get too X on you"
- "things are about to get interesting"
- "neat, right?"

Personality should relieve pressure, not hijack the lesson.

### Jargon Handling

Introduce jargon only after the reader has already felt the idea in plain English.

Preferred sequence:

1. describe the behavior in everyday terms
2. show it in the running example
3. name the technical term
4. restate why that term matters

Example pattern:

- explain the idea as "a single trustworthy fingerprint"
- then introduce "Merkle proof"

Do not lead with terminology unless the user explicitly asked for a dense expert treatment.

## Structural Blueprint

Follow this article architecture unless the topic strongly resists it.

### 1. Open With Context and a Tiny Hook

The introduction should do four things quickly:

- name the concept
- give a human-scale reason it matters
- hint at where it shows up in real life
- promise what the article will explain

An optional joke or light aside can appear here.

Do not start with a dictionary definition alone.

### 2. Introduce One Running Example Early

Find a single scenario that can carry most of the article.

The best running examples are:

- familiar
- visual
- stateful
- easy to mutate
- rich enough to expose tradeoffs

Examples of good containers:

- syncing files
- routing packets
- packing boxes
- scheduling tasks
- caching web pages
- drawing layers in a graphics app

Stay with this example for most of the core explanation. Do not keep switching metaphors.

### 3. Freeze the Initial State

Before explaining the concept, establish a clean starting point.

Show:

- what the system looks like before anything changes
- what "healthy" or "in sync" means
- what objects matter

Then create one specific change that will stress the system.

This gives the article a plot.

### 4. Ask the Reader to Think First

Before presenting the final answer, briefly invite the reader to reason about the problem.

Typical move:

- ask them to imagine possible approaches
- give constraints the solution must satisfy

This creates buy-in and makes the final design feel earned.

### 5. Walk Through Plausible but Imperfect Approaches

This is one of the strongest parts of the format.

Before introducing the correct solution, show 2-3 alternatives that seem reasonable and explain where each breaks.

For each approach:

- name it clearly
- show it visually
- explain how it works
- list the failure modes
- preserve any useful idea you will reuse later

This section should make the final solution feel like the answer to a real design problem, not a lecture artifact.

### 6. Introduce the Real Solution as a Rescue

Once the reader has seen the pain points, bring in the target concept as the resolution.

Language should signal relief and momentum:

- "This is where X comes in."
- "X solves this by..."
- "The best way to see why is to keep using the same example."

### 7. Break the Core Explanation Into Named Steps

The main walkthrough should be procedural and stateful.

Use subsection headings like:

- `Starting Point`
- `Step 1: ...`
- `Step 2: ...`
- `Step 3: ...`

Each step should:

- perform one logical action
- show the updated state
- explain only the new idea introduced in that step

Do not lump multiple conceptual moves into one giant section.

### 8. Reframe the Same Idea From Another Angle

After the first full walkthrough, show the same system in a second representation.

Examples:

- file/folder view to tree view
- objects on a desk to nodes in a graph
- packets in motion to a routing table

This lets the reader keep the intuition while upgrading to a more formal mental model.

### 9. Talk About Performance Only After Intuition Exists

Do not lead with complexity notation.

First make the reader feel the efficiency.

Then introduce:

- complexity
- scaling properties
- pathological cases
- implementation caveats

The sequence should be:

1. intuitive advantage
2. alternate visualization
3. formal performance claim
4. caveats and worst case

### 10. Close With Real-World Applications

Once the reader understands the mechanism, widen the lens.

Add a section showing how the concept appears in recognizable systems.

For each application:

- name the domain
- show the minimal visual structure
- connect it back to the running example
- explain what role the concept plays there

This is where the article cashes in its promise from the opening.

### 11. End With a Compact Recap

The conclusion should:

- restate the concept plainly
- summarize the core advantage
- restate the tradeoff if relevant
- leave the reader with one memorable mental model

The recap should sound like a useful closing synthesis, not a perfunctory summary.

## Visual Teaching Rules

This format is heavily visual. Images are not decoration. They are the explanation.

### What the Images Do

In the Merkle article, images do at least seven jobs:

1. Introduce the cast of objects in the running example.
2. Freeze the before-state.
3. Show exactly one changed variable.
4. Show propagation through the system step by step.
5. Highlight matches and mismatches visually.
6. Reframe the same idea in a more abstract diagram.
7. Ground real-world applications in simplified structures.

Your article should use visuals the same way.

### Preferred Visual Pattern

Keep the same base scene and mutate it over time.

That means:

- same objects
- same layout
- same color language
- same labels
- one changed detail at a time

This makes the reader notice what changed without re-parsing the whole diagram.

### Image Frequency

Add a visual whenever one of these happens:

- a new system is introduced
- a state changes
- data flows
- a mismatch appears
- a hierarchy becomes important
- a formal model replaces an informal one
- a real-world application needs grounding

If two or three paragraphs introduce a meaningful new state and there is no visual, you are probably drifting away from the format.

### Visual Style Guidelines

Favor visuals that are:

- simple
- high contrast
- diagrammatic
- labeled
- stateful
- easy to compare side by side

Avoid visuals that are:

- decorative only
- overly realistic
- crowded
- unlabeled when labels would help
- conceptually noisy

### Reusable Visual Moves

Use these moves often:

- side-by-side comparison of local vs remote, before vs after, or good vs stale
- check marks and warning indicators
- arrows to show propagation or traversal
- highlighted paths to show "only this part changed"
- a single fingerprint/root/badge to summarize many details
- a second diagram that abstracts the first into a tree/graph view

### Humor Images

One occasional gag image is acceptable after a dense stretch.

Use it sparingly. It should:

- release tension
- reinforce the topic loosely
- not derail the article

One small visual joke is enough.

### If You Cannot Generate Images

When you cannot create actual diagrams, write explicit image directions inline.

Use a format like:

`[Diagram: side-by-side local folder and server folder. Same files on both sides. Green check marks on both panels. Use one highlighted file to show the next state change.]`

These directions should be specific enough that a designer or image model could implement them.

## Explanation Tactics

### Always Make the Reader See the State

Do not say "the structure updates recursively" and move on.

Instead:

- name what changed first
- name what now became stale
- explain why parent structures must change
- show the updated path

Concrete state changes beat abstract descriptions.

### Explain Through Consequences

When introducing a property, tie it to behavior.

Instead of:

- "The root is derived from child hashes."

Prefer:

- "Because the root depends on those child hashes, any change below bubbles up and changes the root too."

### Keep Asking Small Questions

Useful rhetorical prompts include:

- "What would happen if...?"
- "Why does that matter?"
- "Do you know why?"
- "What does the server know at this point?"

These questions keep the article feeling interactive.

### Restate After Complexity

After a dense paragraph, add a simpler restatement.

Pattern:

- explain the detailed mechanism
- summarize the important consequence in plain English

This is especially useful after:

- recursion
- complexity analysis
- security explanations
- graph/tree terminology

### Preserve Technical Correctness

The voice is relaxed, but the content should not get mushy.

Be precise about:

- what depends on what
- what is recomputed
- what is compared
- what information each actor has
- where the optimization actually comes from

If simplification would create a false mental model, add one sentence that sharpens the edge.

## Formatting Moves

Use these formatting elements often:

- short subsections with informative headings
- numbered lists for constraints, steps, or key observations
- bullet lists for pros, cons, and failure modes
- bold for critical entities or changed items
- occasional code snippets only when they simplify the mechanic
- callout notes for subtle implementation details

Do not over-format everything. Emphasis should feel intentional.

## What To Avoid

Do not:

- open with a stiff encyclopedia definition
- dump jargon before intuition exists
- bounce between unrelated metaphors
- explain only the correct approach without showing why it is needed
- use images as generic filler
- overdo humor
- sound like marketing copy
- rely on vague praise like "powerful," "revolutionary," or "game-changing"
- turn every paragraph into a dramatic mic drop

## Output Recipe

When asked to write in this format, follow this working order:

1. Identify the concept's job in plain English.
2. Pick a running example that can carry the whole lesson.
3. Define the clean starting state.
4. Choose one meaningful change or failure event.
5. List 2-3 naive or partial approaches.
6. Explain why each is insufficient.
7. Introduce the real concept as the fix.
8. Break the fix into sequential steps.
9. Attach a diagram idea to each important state.
10. Add a performance or scaling section.
11. Add real-world applications.
12. End with a crisp recap.

## Default Article Template

Use this outline by default:

1. Hook and why this matters
2. Running example introduction
3. Initial system state
4. Triggering change or failure
5. "Think about possible approaches"
6. Failed approach 1
7. Failed approach 2
8. Failed approach 3
9. Introduce the target concept
10. Step-by-step walkthrough
11. Alternate visualization
12. Performance characteristics
13. Real-world applications
14. Conclusion and recap

## Drafting Checklist

Before delivering, verify:

- the concept is grounded in one stable running example
- the article has a clear before-state and after-state
- at least two alternative approaches were considered when appropriate
- every major conceptual jump has a corresponding visual or diagram direction
- the voice sounds like a human teacher, not product copy
- jargon appears after intuition, not before
- the conclusion reconnects to the main mental model

## Litmus Test

The draft matches this skill if a reader could say:

- "I can picture what is happening."
- "I understand why the obvious alternatives fail."
- "The diagrams and prose moved together."
- "The writer sounds smart and relaxed."
- "I learned both the intuition and the formal takeaway."

If those reactions are missing, revise until they are true.
