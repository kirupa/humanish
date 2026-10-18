# Welcome to Humanish

Humanish is a clean space to write documents and have AI help review them — the
**web build** of the same editor that ships for macOS. It uses the *same*
parsing, formatting, and range-mapping logic, ported to JavaScript, with your
Markdown file as the canonical document underneath.

## Three ways to work

1. **Rich Text** — edit the rendered document directly
2. **Side by Side** — rendered and raw Markdown, synchronized
3. **Markdown** — the raw source, with representative typography

## What it supports

- Headings, `inline code`, and ~~strikethrough~~
- [Links](https://www.kirupa.com/) that open where you expect
- Task lists:
  - [x] Port the core
  - [ ] Ship it

> Everything the macOS build can do with a document, this can do too.

```swift
let editor = MarkdownEditor()
editor.open("Welcome.md")
```

---

Press **Control-Command-1**, **2**, or **3** to switch modes.
