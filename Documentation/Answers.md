# Answers

Answers are short, written help cards the Command Bar can show above its
results when a person asks how to do something: "how do I split view", "undo
close tab", "where are my Boosts". Each card holds one to three plain steps,
the keyboard shortcut, an action the card can run, and a link to the full
guide in Ode Help. Cards are written and checked by people against the app.
Nothing in a card is generated, and no model writes or changes answer text.

The cards live in `OdeCore/src/OdeCore/Domain/Answers/answers.json`, which the
core embeds and ranks. The guides in
`HelpCenter/docs` are written from the same cards: every live card has one
section in the guide its `help` link names, headed by the card's title with the
card's id as the heading id, holding the card's steps, its shortcut and its
note word for word. Change a card and its section together.

## File format

The file is one JSON object.

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | `1`. Raise it when a field changes meaning. |
| `helpBase` | string | The address every card's `help` path is relative to. |
| `synonyms` | array of arrays | Groups of single, lowercase words that ranking treats as the same word, such as `["incognito", "private"]`. Keep groups tight: a broad group makes unrelated cards match. |
| `suggested` | array of ids | The live cards Ode Help lists before anything is asked, in order. |
| `cards` | array | The cards, grouped by topic. Order carries no meaning. |

### Card fields

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Lowercase kebab-case, unique and stable. It is the heading id of the card's section in Ode Help. Never reuse an id for a different task. |
| `status` | yes | `live` for a feature that ships in Ode; `pending` for a feature still being built. The Command Bar never shows a pending card. |
| `kind` | yes | `task` for how to do something, `explain` for what something is or why it behaves as it does, `missing` for something Ode does not have, said plainly, with what to use instead. |
| `topic` | yes | One of the topics below. |
| `title` | yes | The task in the person's own words, in sentence case: "Reopen a closed tab", not "Reopen Last Closed Tab". |
| `questions` | yes | At least three ways people ask for this, in lowercase, as they type them: short, without punctuation, sometimes without a verb. |
| `aliases` | no | Other names for the feature: Ode's menu and settings labels, and the words other browsers use, such as Arc's "Little Arc" for Quick Window. An alias names one card only, and is never a website's or brand's name, since typing a name exactly leads with its card. |
| `keywords` | no | Loose words that point to the card, brand names included. |
| `steps` | yes | One to three sentences, each ending in a period, written for someone who is not technical. A `task` card's steps are actions in order; an `explain` or `missing` card's steps are statements read as one paragraph. Prefer what to click over what to press; the shortcut has its own field. |
| `keys` | no | The default shortcut in Mac key symbols, modifiers in the order ⌃⌥⇧⌘, such as `⇧⌘T`. When `action` names a command, the Command Bar shows the person's current shortcut for it instead. |
| `action` | no | What the card's "Do it" button runs, exactly one of: `{"command": name}`, a `ShortcutCommand` name from `OdeCore/src/OdeCore/Contracts/Shortcuts/ShortcutCommand.cs`; `{"settings": name}`, a `BrowserSettingsDestination` name; `{"space": name}`, a `BrowserSpaceSettingsTab` name, which opens that page of the current Space's settings; or `{"app": name}`, a `BrowserMacApplicationAction` name. Leave it out when no single action does the task. |
| `note` | no | One short sentence of caveat, such as a limit or an engine the feature needs. |
| `waitsFor` | pending only | The unfinished work the card waits for. Remove it when the card goes live. |
| `help` | yes | The guide section for the card, relative to `helpBase`: a page path ending in `/`, then `#` and the section id. A pending card links only to the page its section will join. |
| `related` | no | Ids of other cards worth showing next. |

Topics: `command-bar`, `tabs`, `folders`, `split-view`, `spaces`, `sidebar`,
`windows`, `links`, `page`, `boosts`, `previews`, `downloads`, `history`,
`recovery`, `import-export`, `passwords`, `privacy`, `extensions`, `engines`,
`agents`, `intelligence`, `app`, `arc`.

## Writing a card

- Check every step in the running app and every label against
  `OdeShared/Resources/Localizable.xcstrings`. Write labels exactly as the app
  shows them.
- Write steps someone can follow without knowing the vocabulary: "Right-click
  the tab in the sidebar", not "Open the tab's context menu".
- Menu paths use `>`: "Choose File > Restore from an Earlier Copy…".
- Say what Ode does not do. A `missing` card tells the person the feature is
  not in Ode and what comes closest, never that it is coming on a date.
- Put the person's words in `questions`, including words from browsers they
  are leaving. Misspellings belong in the golden questions, not in cards.
- Add the card's section to the guide its `help` names, with the heading id
  set to the card id: `## Reopen a closed tab {#reopen-closed-tab}`.

## Turning on a pending card

When the feature lands, check each step in the app, update the labels, add its
section to the guide, remove `waitsFor` and set `status` to `live`.

## How the Command Bar uses answers

`AnswerCatalog` reads the file once and `AnswerIndex` ranks the live cards for
what a person types: BM25 over each card's fields, with a word in the title or
an alias counting most and a word in the steps least; words a synonym group
treats as one; a typo fixed against the words the cards hold; two words typed
as one; and bonuses for a card whose title, alias or question the text is, or
whose alias the text holds whole. `AnswerWeights.Tuned` holds the weights.

An answer leads the Command Bar, above the search for the text, when the text
is one of a card's titles, aliases or questions, when it reads as a question
and its best card scores clearly, or when one card outscores every other by a
wide margin. An address never leads with an answer. "Do It" runs the card's
action and "Read More" opens its guide; Return runs the one Tab is on.

Typing "help" or "ode" and Tab, or "?" and a space, enters Ode Help, which
lists only answers: the suggested cards before anything is typed, then the
cards that rank for the question.

## Golden questions

`OdeCore/tests/OdeCore.Tests/Palette/Fixtures/AnswerQuestions.json` lists real
questions in people's own words, misspellings included, each with the id of the
card that should rank first:

```json
{ "schemaVersion": 1, "questions": [
  { "text": "undo close tab", "expect": "reopen-closed-tab", "tags": ["synonym"] }
] }
```

`tags` describe why the question is hard: `synonym`, `typo`, `arc`, `why`,
`terse`, `long`. A question whose card is pending carries `"pending": true` and
counts once the card goes live. Add a question whenever someone asks something
the cards answer badly, and fix the card or the synonyms rather than the
question.

`AnswerTests.GoldenQuestionsRankTheirCardFirst` fails when fewer than 90% of
the live questions rank their card first. Every fifth question, counting from
the fifth, is kept back: tune `AnswerWeights` on the others, and the test
reports the kept-back share separately so tuning cannot hide a drop there.
`Scripts/Tests/test_answer_guides.py` checks that every live card's guide
section exists and holds its steps and note.
