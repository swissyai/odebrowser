import Foundation

/// A script Ode runs for an agent in the agent's own world of a page, the
/// same on both engines: reading the page as an outline, finding the element
/// a uid names, filling a field, or looking for text. Each is the body of an
/// async function; its arguments are written into it as JSON.
///
/// Every script reads the DOM through the prototypes of the agent's own
/// world rather than through an element's properties, since a form's named
/// controls shadow its properties and a document's named elements shadow
/// the document's: a form holding `<input name="title">` answers that input
/// for `form.title`, and one holding `<input name="hidden">` would look
/// hidden.
struct BrowserAgentPageScript {
    // MARK: - Types

    /// How the snapshot script reads a page. Every read walks the whole
    /// document, so a uid's reach, a heading's section and a cut outline's
    /// continuation mean the same whatever else the read asks.
    struct Reading: Encodable, Sendable {
        /// Who reads: the agent's session, whose last read of each document
        /// the page keeps, for `changes` and `report`.
        var reader = ""
        var depth: Int?
        var filter: String?
        var find: String?
        var maxChars = BrowserAgentPageScript.snapshotLimit
        /// Only this element and what it holds, or for a heading its section.
        var uid: String?
        /// Only what follows this element, to read on past a cut.
        var after: String?
        /// Only headings and landmarks, each with how many elements it holds.
        var skeleton = false
        /// Only what changed since the reader's last read of the document;
        /// the other bounds don't apply.
        var changes = false
        /// A report of what changed after input, within `maxChars`: past it,
        /// only how many lines changed, and the reader's last read stays as
        /// it was, so a later read with `changes` still finds them.
        var report = false
        /// The autocomplete tokens of fields only the person fills, whose
        /// values an outline never shows.
        let protectedTokens = BrowserAgentFillRefusal.protectedTokens.sorted()
        let protectedPrefix = BrowserAgentFillRefusal.protectedPrefix
    }

    // MARK: - Static Variables

    /// What every script shares: the elements outlines named, by uid, and
    /// each reader's last read, which a new document starts without; and,
    /// made anew for each script, the agent world's own DOM accessors, which a
    /// page's names can't shadow.
    private static let state = #"""
        const state = (globalThis.__crestAgent ??= { document: null, uids: new Map(), elements: new WeakMap(), next: 1 });
        if (state.document !== document) {
          state.document = document; state.uids = new Map(); state.elements = new WeakMap(); state.next = 1; state.reads = new Map();
        }
        state.reads ??= new Map();
        const dom = (() => {
          const property = (prototype, name) => {
            for (let object = prototype; object; object = Object.getPrototypeOf(object)) {
              const found = Object.getOwnPropertyDescriptor(object, name);
              if (found) return found;
            }
            return undefined;
          };
          const getter = (prototype, name) => {
            const get = property(prototype, name)?.get;
            return get ? (node) => get.call(node) : () => undefined;
          };
          const method = (prototype, name) => {
            const value = property(prototype, name)?.value;
            return value ? (node, ...rest) => value.call(node, ...rest) : () => undefined;
          };
          return {
            type: getter(Node.prototype, "nodeType"), children: getter(Node.prototype, "childNodes"),
            text: getter(Node.prototype, "textContent"), owner: getter(Node.prototype, "ownerDocument"),
            parent: getter(Node.prototype, "parentElement"), connected: getter(Node.prototype, "isConnected"),
            root: method(Node.prototype, "getRootNode"), contains: method(Node.prototype, "contains"),
            clone: method(Node.prototype, "cloneNode"),
            tag: getter(Element.prototype, "tagName"), namespace: getter(Element.prototype, "namespaceURI"),
            attribute: method(Element.prototype, "getAttribute"), has: method(Element.prototype, "hasAttribute"),
            unset: method(Element.prototype, "removeAttribute"), remove: method(Element.prototype, "remove"),
            all: method(Element.prototype, "querySelectorAll"),
            shadow: getter(Element.prototype, "shadowRoot"), box: method(Element.prototype, "getBoundingClientRect"),
            matches: method(Element.prototype, "matches"), scroll: method(Element.prototype, "scrollIntoView"),
            clientLeft: getter(Element.prototype, "clientLeft"), clientTop: getter(Element.prototype, "clientTop"),
            visible: Element.prototype.checkVisibility ? method(Element.prototype, "checkVisibility") : null,
            editable: getter(HTMLElement.prototype, "isContentEditable"), innerText: getter(HTMLElement.prototype, "innerText"),
            focus: method(HTMLElement.prototype, "focus"),
            view: getter(Document.prototype, "defaultView"), body: getter(Document.prototype, "body"),
            html: getter(Document.prototype, "documentElement"), active: getter(Document.prototype, "activeElement"),
            title: getter(Document.prototype, "title"), contentType: getter(Document.prototype, "contentType"),
            byID: method(Document.prototype, "getElementById"), query: method(Document.prototype, "querySelectorAll"),
            fragmentByID: method(DocumentFragment.prototype, "getElementById"),
            shadowActive: getter(ShadowRoot.prototype, "activeElement"),
            iframeDocument: getter(HTMLIFrameElement.prototype, "contentDocument"),
            frameDocument: getter(HTMLFrameElement.prototype, "contentDocument"),
            objectDocument: getter(HTMLObjectElement.prototype, "contentDocument"),
          };
        })();
        const tagOf = (node) => String(dom.tag(node) ?? "").toUpperCase();
        const isHTML = (node) => dom.namespace(node) === "http://www.w3.org/1999/xhtml";
        const isFrame = (tag) => tag === "IFRAME" || tag === "FRAME" || tag === "OBJECT";
        // The document of a frame of the page's own origin; null for one of
        // another origin, which the agent's world can't read.
        const frameDocument = (node, tag = tagOf(node)) => {
          try {
            if (tag === "IFRAME") return dom.iframeDocument(node) ?? null;
            if (tag === "FRAME") return dom.frameDocument(node) ?? null;
            if (tag === "OBJECT") return dom.objectDocument(node) ?? null;
          } catch {}
          return null;
        };
        // The frame element that holds `node`'s document, when that document
        // is a frame's of the page's own origin.
        const frameOf = (node) => { try { return dom.view(dom.owner(node))?.frameElement ?? null; } catch { return null; } };
        const element = (uid) => {
          const found = state.uids.get(uid)?.deref();
          return found && dom.connected(found) && dom.view(dom.owner(found)) ? found : null;
        };
        // Where the page's focus is, through shadow roots and frames of the
        // page's own origin; `elsewhere` when it is in a frame of another
        // origin or in a component's closed shadow root, whose field Ode
        // can't see.
        const focused = () => {
          let target = dom.active(document) ?? null;
          for (let step = 0; step < 32 && target; step++) {
            const shadow = dom.shadow(target);
            let inner = shadow ? dom.shadowActive(shadow) ?? null : null;
            const tag = tagOf(target);
            if (!inner && isFrame(tag)) {
              const inside = frameDocument(target, tag);
              if (!inside) return { target, elsewhere: tag !== "OBJECT" || dom.has(target, "data") };
              inner = dom.active(inside) ?? null;
            }
            if (!inner || inner === target) break;
            target = inner;
          }
          // A component that holds the focus without an open shadow root or text
          // of its own keeps the focused field in a closed one.
          const closed = target !== null && tagOf(target).includes("-") && !dom.shadow(target) &&
            !(isHTML(target) && dom.editable(target) === true);
          return { target, elsewhere: closed };
        };
        """#

    /// What reading needs beyond `state`: how an element shows and its
    /// text, and an address as the agent reads it.
    private static let reading = #"""
        const squash = (text) => (typeof text === "string" ? text : "").replace(/\s+/g, " ").trim();
        const clean = (text) => squash(text).slice(0, 200);
        const computed = (node) => (dom.view(dom.owner(node)) ?? window).getComputedStyle(node);
        const textOf = (node) => (isHTML(node) ? dom.innerText(node) : dom.text(node));
        // An element without a box of its own, as one with display: contents,
        // still shows what it holds, so only its children are judged.
        const hidden = (node) => {
          if (dom.attribute(node, "aria-hidden") === "true" || dom.has(node, "hidden")) return true;
          if (dom.visible) {
            if (dom.visible(node, { checkOpacity: false, checkVisibilityCSS: true })) return false;
            return computed(node).display !== "contents";
          }
          const style = computed(node);
          return style.display === "none" || style.visibility === "hidden";
        };
        // Addresses on the page's own site as their path, others in full.
        const shorten = (address) => {
          try {
            const url = new URL(address);
            if (url.origin === location.origin) {
              if (url.pathname === location.pathname && url.search === location.search && url.hash) return url.hash;
              return url.pathname + url.search + url.hash;
            }
          } catch {}
          return String(address);
        };
        """#

    /// How many characters an outline takes at most when the agent names no
    /// other bound.
    static let snapshotLimit = 60_000
    /// How many characters a report of what input changed takes at most.
    static let reportLimit = 2_000

    /// The bound a read keeps: what the agent asked, or `snapshotLimit`,
    /// held between 2,000 and 1,000,000 characters.
    static func cap(_ requested: Double?) -> Int {
        Int(min(max(requested ?? Double(snapshotLimit), 2_000), 1_000_000))
    }

    /// Mozilla's Readability and Turndown, bundled with Ode unchanged, each
    /// read as a module of its own so neither leaves a global behind. They
    /// are in the bundle that holds Ode's code, which in the Chromium build
    /// is a framework rather than the app.
    private static let libraries: String = {
        let module = { (name: String) -> String in
            let url = [Bundle(for: BrowserMacAgents.self), .main].lazy.compactMap {
                $0.url(forResource: name, withExtension: "js")
            }.first
            let source = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            return "(() => { const module = { exports: {} }; const exports = module.exports;\n" + source
                + "\nreturn module.exports; })()"
        }
        return "const Readability = \(module("Readability"));\n"
            + "const TurndownService = \(module("turndown.browser.umd"));\n"
    }()

    // MARK: - Variables

    let source: String

    // MARK: - Actions - Reading

    /// The page as an accessibility outline: each meaningful element's role,
    /// name and state with a uid, and the text between them, one space of
    /// indent per level, within `maxChars` characters and `depth` levels.
    /// Links on the page's own site show their path. A container named by its
    /// text, such as a list item, shows that name only when nothing it holds
    /// is listed. Frames of the page's own origin are read as part of it; one
    /// of another origin is listed with its address. `uid` reads one element
    /// and what it holds, or a heading and its section; `after` reads on from
    /// the element after it; `skeleton` keeps only headings and landmarks,
    /// each with how many elements it holds. With `filter` or `find`, only the
    /// elements and text whose role, name or text contains every one of them,
    /// ignoring case, are kept, with their ancestors; with `find`, the answer
    /// counts them. A field's value is never part of it when only the person
    /// fills that field, as with a password, a one-time code or a payment
    /// card. The answer names the last element it listed, where a cut outline
    /// reads on. Each read is kept as the reader's last of the document; with
    /// `changes` or `report`, the answer is what changed since then: lines
    /// added, under the element they went into, changed and removed.
    static func snapshot(_ reading: Reading) -> Self {
        Self(
            source: state + Self.reading + #"""
                const options = \#(encoded(reading));
                if (options.changes) Object.assign(options, { depth: null, filter: null, find: null, uid: null, after: null, skeleton: false });
                const deepest = options.depth ?? Infinity;
                const terms = [options.filter, options.find].filter((term) => term).map((term) => term.toLowerCase());
                const roles = { A: "link", BUTTON: "button", SELECT: "combobox", TEXTAREA: "textbox", IMG: "img", NAV: "navigation",
                  MAIN: "main", HEADER: "banner", FOOTER: "contentinfo", ASIDE: "complementary", FORM: "form", TABLE: "table",
                  TR: "row", TD: "cell", TH: "columnheader", UL: "list", OL: "list", LI: "listitem", DIALOG: "dialog",
                  SUMMARY: "button", DETAILS: "group", OPTION: "option", IFRAME: "iframe", FRAME: "iframe", H1: "heading", H2: "heading",
                  H3: "heading", H4: "heading", H5: "heading", H6: "heading", PROGRESS: "progressbar" };
                const inputs = { checkbox: "checkbox", radio: "radio", button: "button", submit: "button", reset: "button",
                  image: "button", range: "slider", number: "spinbutton", search: "searchbox", file: "button", color: "button" };
                const interactive = new Set(["link", "button", "combobox", "textbox", "searchbox", "checkbox", "radio", "slider",
                  "spinbutton", "option", "tab", "menuitem", "menuitemcheckbox", "menuitemradio", "switch", "treeitem"]);
                const landmarks = new Set(["heading", "img", "navigation", "main", "banner", "contentinfo", "complementary",
                  "form", "table", "row", "cell", "columnheader", "list", "listitem", "dialog", "group", "iframe", "region",
                  "progressbar", "alert", "status", "tablist", "menu", "tree", "grid"]);
                // Containers named by their text, whose children list that text.
                const contentNamed = new Set(["heading", "cell", "columnheader", "listitem"]);
                const fromContent = new Set(["link", "button", "option", "tab", "menuitem", "treeitem"]);
                const skeletal = new Set(["banner", "navigation", "main", "complementary", "contentinfo", "region", "form", "dialog",
                  "heading", "iframe"]);
                const valued = new Set(["textbox", "searchbox", "combobox", "spinbutton", "slider"]);
                const protectedTokens = new Set(options.protectedTokens);
                const labelable = new Set(["INPUT", "SELECT", "TEXTAREA", "BUTTON", "METER", "OUTPUT", "PROGRESS"]);
                const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "HEAD", "META", "LINK"]);
                const inline = new Set(["A", "ABBR", "B", "BDI", "BDO", "CITE", "CODE", "DATA", "DEL", "DFN", "EM", "FONT", "I", "INS",
                  "KBD", "LABEL", "MARK", "NOBR", "Q", "S", "SAMP", "SMALL", "SPAN", "STRONG", "SUB", "SUP", "TIME", "TT", "U", "VAR", "WBR"]);
                const roleOf = (node, tag) => {
                  const explicit = (dom.attribute(node, "role") ?? "").split(" ")[0];
                  if (explicit) return explicit;
                  if (!isHTML(node)) return null;
                  if (tag === "INPUT") return inputs[String(node.type).toLowerCase()] ?? "textbox";
                  if (tag === "A" && !dom.has(node, "href")) return null;
                  if (tag === "SECTION" && (dom.has(node, "aria-label") || dom.has(node, "aria-labelledby"))) return "region";
                  if (dom.editable(node)) {
                    const parent = dom.parent(node);
                    if (!parent || !isHTML(parent) || dom.editable(parent) !== true) return "textbox";
                  }
                  return roles[tag] ?? null;
                };
                const nameOf = (node, role, tag) => {
                  const label = dom.attribute(node, "aria-label");
                  if (label) return clean(label);
                  const by = dom.attribute(node, "aria-labelledby");
                  if (by) {
                    const root = dom.root(node);
                    const named = (id) => dom.type(root) === Node.DOCUMENT_NODE ? dom.byID(root, id) : dom.fragmentByID(root, id);
                    return clean(by.split(" ").map((id) => { const found = named(id); return found ? dom.text(found) : ""; }).join(" "));
                  }
                  // A label's own words, not those of a control inside it, such as a menu's options.
                  const own = (label) => [...dom.children(label)].filter((child) => dom.type(child) === Node.TEXT_NODE ||
                    (dom.type(child) === Node.ELEMENT_NODE && !dom.matches(child, "input, select, textarea, button")))
                    .map((child) => dom.text(child)).join(" ");
                  if (labelable.has(tag) && node.labels?.length) return clean([...node.labels].map(own).join(" "));
                  if (tag === "IMG" || tag === "AREA" || (tag === "INPUT" && node.type === "image")) {
                    const alt = dom.attribute(node, "alt");
                    if (alt) return clean(alt);
                  }
                  if (fromContent.has(role)) return clean(textOf(node));
                  const title = dom.attribute(node, "title");
                  if (title) return clean(title);
                  return tag === "INPUT" || tag === "TEXTAREA" ? clean(dom.attribute(node, "placeholder")) : "";
                };
                const uidOf = (node) => {
                  let uid = state.elements.get(node);
                  if (!uid) {
                    uid = "e" + state.next++;
                    state.elements.set(node, uid);
                    state.uids.set(uid, new WeakRef(node));
                  }
                  return uid;
                };
                const focus = focused().target;
                // What follows an element's role, name and uid: its state.
                const stateOf = (node, role, tag) => {
                  const parts = [];
                  if ((isHTML(node) && dom.matches(node, ":disabled")) || dom.attribute(node, "aria-disabled") === "true")
                    parts.push("[disabled]");
                  if ((tag === "INPUT" && node.checked) || dom.attribute(node, "aria-checked") === "true") parts.push("[checked]");
                  const expanded = dom.attribute(node, "aria-expanded");
                  if (expanded) parts.push(`[expanded=${expanded}]`);
                  if ((tag === "OPTION" && node.selected) || dom.attribute(node, "aria-selected") === "true") parts.push("[selected]");
                  if (node === focus) parts.push("[focused]");
                  if (isHTML(node) && tag === "A" && node.href) parts.push(`[href=${shorten(node.href).slice(0, 300)}]`);
                  if (role === "iframe" && isFrame(tag) && !frameDocument(node, tag)) {
                    try {
                      const url = new URL(node.src);
                      parts.push(`[src=${(url.origin + url.pathname).slice(0, 120)}]`);
                    } catch {}
                    parts.push("[other site]");
                  }
                  const autocomplete = (dom.attribute(node, "autocomplete") ?? "").toLowerCase().split(/\s+/);
                  if (tag === "INPUT" && String(node.type).toLowerCase() === "password") parts.push("[password]");
                  else if (autocomplete.some((token) => protectedTokens.has(token) || token.startsWith(options.protectedPrefix)))
                    parts.push("[protected]");
                  else if (valued.has(role)) {
                    const value = ["INPUT", "TEXTAREA", "SELECT"].includes(tag) ? node.value
                      : tag !== "FORM" && typeof node.value === "string" ? node.value : "";
                    if (value) parts.push(`[value=${JSON.stringify(String(value).slice(0, 200))}]`);
                  }
                  return parts.join(" ");
                };
                // Every element and run of text the page shows, in document order,
                // each with its depth and the index of the element it lies in.
                // Runs of text that only inline elements split, as a highlighted line
                // of code is, are one line, up to the length of one.
                const entries = [];
                let elementCount = 0;
                let joint = "";
                const walk = (root, depth, parent) => {
                  const children = dom.children(root);
                  if (!children) return;
                  for (const child of children) {
                    const type = dom.type(child);
                    if (type === Node.TEXT_NODE) {
                      const raw = dom.text(child) ?? "";
                      const last = entries[entries.length - 1];
                      if (last && last.raw !== undefined && last.parent === parent && last.depth === depth &&
                          squash(last.raw + joint + raw).length <= 200) {
                        last.raw += joint + raw;
                      } else if (squash(raw)) entries.push({ depth, parent, raw });
                      joint = "";
                      continue;
                    }
                    if (type !== Node.ELEMENT_NODE) continue;
                    const tag = tagOf(child);
                    if (skipped.has(tag) || hidden(child)) continue;
                    const role = roleOf(child, tag);
                    if (isFrame(tag)) {
                      // A frame too small to show anything is left out.
                      const box = dom.box(child);
                      if (box.width < 2 || box.height < 2) continue;
                    }
                    if (role && (interactive.has(role) || landmarks.has(role))) {
                      const index = entries.length;
                      const level = role === "heading"
                        ? Number(dom.attribute(child, "aria-level")) || (/^H[1-6]$/.test(tag) ? Number(tag[1]) : 2) : 0;
                      const entry = { depth, parent, node: child, role, uid: uidOf(child), level,
                        name: contentNamed.has(role) ? "" : nameOf(child, role, tag), state: stateOf(child, role, tag),
                        otherSite: role === "iframe" && isFrame(tag) && !frameDocument(child, tag) };
                      entries.push(entry);
                      elementCount++;
                      const before = elementCount;
                      // A control's own text is its name; its children add nothing.
                      if (!interactive.has(role)) walk(child, depth + 1, index);
                      const shadow = dom.shadow(child);
                      if (shadow) walk(shadow, depth + 1, index);
                      enter(child, tag, depth + 1, index);
                      if (contentNamed.has(role)) {
                        // Holding only text, a container takes the text as its name; holding
                        // elements, it is named only when none of them is listed.
                        const text = elementCount === before ? squash(textOf(child)) : null;
                        if (text !== null && text.length <= 200) {
                          entry.name = text;
                          entries.length = index + 1;
                        } else if (text === null) entry.unnamed = true;
                      }
                    } else {
                      // Text either side of a block is apart.
                      if (!inline.has(tag)) joint = " ";
                      walk(child, depth, parent);
                      const shadow = dom.shadow(child);
                      if (shadow) walk(shadow, depth, parent);
                      enter(child, tag, depth, parent);
                      if (!inline.has(tag)) joint = " ";
                    }
                  }
                };
                // A frame of the page's own origin is read as part of the page.
                const enter = (node, tag, depth, parent) => {
                  if (!isFrame(tag)) return;
                  const inside = frameDocument(node, tag);
                  const body = inside && (dom.body(inside) ?? dom.html(inside));
                  if (body) walk(body, depth, parent);
                };
                walk(dom.body(document) ?? dom.html(document), 0, -1);
                for (const entry of entries) if (entry.raw !== undefined) entry.text = clean(entry.raw);
                const page = { url: location.href, title: squash(dom.title(document)) };
                const lineOf = (entry, name = entry.name) => entry.node
                  ? [`- ${entry.role}`, name ? JSON.stringify(name) : "", `[uid=${entry.uid}]`,
                    entry.level ? `[level=${entry.level}]` : "", entry.state].filter((part) => part).join(" ")
                  : `- text ${JSON.stringify(entry.text)}`;
                const textKey = (entry) => (entry.parent >= 0 ? entries[entry.parent].uid : "") + "\n" + entry.text;
                // The page as this read sees it, which the reader's next read compares with.
                const now = { elements: new Map(), texts: new Map() };
                for (const entry of entries) {
                  if (entry.node) now.elements.set(entry.uid, lineOf(entry));
                  else now.texts.set(textKey(entry), (now.texts.get(textKey(entry)) ?? 0) + 1);
                }
                const previous = state.reads.get(options.reader);
                let changes = null;
                if (options.changes || options.report) {
                  const added = [];
                  const changed = [];
                  const removed = [];
                  if (previous) {
                    const left = new Map(previous.texts);
                    entries.forEach((entry, index) => {
                      if (!entry.node) {
                        const count = left.get(textKey(entry)) ?? 0;
                        if (count > 0) left.set(textKey(entry), count - 1);
                        else added.push(index);
                      } else if (!previous.elements.has(entry.uid)) added.push(index);
                      else if (previous.elements.get(entry.uid) !== now.elements.get(entry.uid)) changed.push(index);
                    });
                    for (const [uid, line] of previous.elements) if (!now.elements.has(uid)) removed.push(line);
                    for (const [key, count] of left)
                      for (let copy = 0; copy < count; copy++) removed.push(`- text ${JSON.stringify(key.slice(key.indexOf("\n") + 1))}`);
                  }
                  // Added lines in runs, each under the element it went into.
                  const sections = [];
                  const fresh = new Set(added);
                  for (let first = 0; first < added.length;) {
                    // A run goes on while each line follows the last, in the run or beside its first.
                    const members = new Set([added[first]]);
                    let next = first + 1;
                    while (next < added.length && added[next] === added[next - 1] + 1) {
                      const parent = entries[added[next]].parent;
                      if (!members.has(parent) && parent !== entries[added[first]].parent) break;
                      members.add(added[next++]);
                    }
                    const run = added.slice(first, next);
                    const top = Math.min(...run.map((index) => entries[index].depth));
                    const parent = entries[run[0]].parent;
                    const into = parent >= 0 && !fresh.has(parent) ? ` in ${entries[parent].uid}` : "";
                    sections.push(`added${into}:\n` + run.map((index) => " ".repeat(entries[index].depth - top) + lineOf(entries[index])).join("\n"));
                    first = next;
                  }
                  if (changed.length) sections.push("changed:\n" + changed.map((index) => lineOf(entries[index])).join("\n"));
                  if (removed.length) sections.push("removed:\n" + removed.join("\n"));
                  const text = sections.join("\n\n");
                  changes = { compared: previous !== undefined, added: added.length, changed: changed.length, removed: removed.length };
                  if (options.report) {
                    if (!previous) return { ...page, changes };
                    if (text.length > options.maxChars) return { ...page, changes: { ...changes, summary: true } };
                    state.reads.set(options.reader, now);
                    return { ...page, outline: text, changes };
                  }
                  // A cut delta keeps its baseline: repeat with a larger cap to receive all changes.
                  // A change bigger than half the page is read as the whole page.
                  const whole = entries.reduce((sum, entry) => sum + entry.depth + lineOf(entry).length + 1, 0);
                  if (previous && (text.length <= 2000 || text.length <= whole / 2)) {
                    if (text.length <= options.maxChars) state.reads.set(options.reader, now);
                    return { ...page, outline: text.slice(0, options.maxChars), truncated: text.length > options.maxChars,
                      elements: added.filter((index) => entries[index].node).length, changes };
                  }
                  if (previous) changes.whole = true;
                  Object.assign(options, { uid: null, after: null, skeleton: false });
                }
                // Where an element's reach ends: its subtree, or for a heading its
                // section, up to the next heading of its level or higher.
                const endOf = (index) => {
                  const root = entries[index];
                  let end = index + 1;
                  while (end < entries.length) {
                    const entry = entries[end];
                    if (entry.depth < root.depth || (root.role !== "heading" && entry.depth === root.depth)) break;
                    if (root.role === "heading" && entry.role === "heading" && entry.level <= root.level) break;
                    end++;
                  }
                  return end;
                };
                const indexOf = (uid, from, to) => {
                  const target = element(uid);
                  if (!target) return { error: "unknown", uid };
                  for (let index = from; index < to; index++) if (entries[index].node === target) return { index };
                  return { error: "hidden", uid };
                };
                let start = 0;
                let end = entries.length;
                let base = 0;
                if (options.uid) {
                  const found = indexOf(options.uid, 0, entries.length);
                  if (found.error) return { ...page, ...found };
                  start = found.index;
                  end = endOf(start);
                  base = entries[start].depth;
                }
                if (options.after) {
                  const found = indexOf(options.after, start, end);
                  if (found.error) return { ...page, ...found };
                  start = found.index + 1;
                }
                let indices = [];
                for (let index = start; index < end; index++) if (entries[index].depth - base <= deepest) indices.push(index);
                let depthOf = (index) => entries[index].depth - base;
                let size = () => "";
                if (options.skeleton) {
                  indices = indices.filter((index) => skeletal.has(entries[index].role));
                  const kept = new Set(indices);
                  const levels = new Map();
                  for (const index of indices) {
                    let level = 0;
                    for (let parent = entries[index].parent; parent >= start; parent = entries[parent].parent)
                      if (kept.has(parent)) level++;
                    levels.set(index, level);
                    const entry = entries[index];
                    if (entry.role === "heading" && !entry.name) entry.name = clean(textOf(entry.node));
                  }
                  depthOf = (index) => levels.get(index);
                  size = (index) => {
                    let count = 0;
                    for (let next = index + 1, last = endOf(index); next < last; next++) if (entries[next].node) count++;
                    return ` [elements=${count}]`;
                  };
                }
                let matches;
                if (terms.length) {
                  const kept = new Set();
                  matches = 0;
                  for (const index of indices) {
                    const entry = entries[index];
                    const words = entry.node ? [entry.role, entry.name] : [entry.text];
                    if (!terms.every((term) => words.some((word) => word.toLowerCase().includes(term)))) continue;
                    matches++;
                    kept.add(index);
                    for (let parent = entry.parent; parent >= start && !kept.has(parent); parent = entries[parent].parent)
                      kept.add(parent);
                  }
                  indices = indices.filter((index) => kept.has(index));
                }
                // The containers that hold a listed line, which aren't named by their text.
                const holding = new Set();
                for (const index of indices) {
                  for (let parent = entries[index].parent; parent >= 0 && !holding.has(parent); parent = entries[parent].parent)
                    holding.add(parent);
                }
                const lines = [];
                let length = 0;
                let truncated = false;
                let last = null;
                let elements = 0;
                let otherSites = 0;
                for (const index of indices) {
                  const entry = entries[index];
                  let line;
                  if (entry.node) {
                    const name = entry.unnamed && !holding.has(index) ? clean(textOf(entry.node)) : entry.name;
                    line = lineOf(entry, name) + size(index);
                  } else line = lineOf(entry);
                  line = " ".repeat(Math.max(0, depthOf(index))) + line;
                  if (length + line.length + 1 > options.maxChars) { truncated = true; break; }
                  length += line.length + 1;
                  lines.push(line);
                  if (!entry.node) continue;
                  elements++;
                  last = entry.uid;
                  if (entry.otherSite) otherSites++;
                }
                // Failed uid reads never advance the baseline. A bounded ordinary read
                // observes the whole page; a cut change read must be retried before it is consumed.
                if (!options.changes || !truncated) state.reads.set(options.reader, now);
                return { ...page, outline: lines.join("\n"), elements, truncated, last, otherSites,
                  ...(options.find ? { matches } : {}), ...(changes ? { changes } : {}) };
                """#)
    }

    /// The page's main content as Markdown: the page's own Markdown when it
    /// links one on its own site, otherwise what Readability takes for the
    /// main content, or with `fullPage` the whole page, through Turndown.
    /// Hidden text, form fields and their values, scripts and frames are
    /// never part of it. `maxChars` characters from `offset` are answered,
    /// with the whole Markdown's length.
    static func markdown(fullPage: Bool, offset: Int, maxChars: Int) -> Self {
        Self(
            source: state + Self.reading + libraries + """
                const fullPage = \(fullPage ? "true" : "false");
                const offset = \(offset);
                const limit = \(maxChars);
                """ + #"""
                    const page = { url: location.href, title: squash(dom.title(document)) };
                    const own = (address) => {
                      try {
                        const url = new URL(address, location.href);
                        return url.origin === location.origin && /^https?:$/.test(url.protocol) ? url : null;
                      } catch { return null; }
                    };
                    // Lengths and offsets count UTF-16 code units, as the agent's offset does.
                    const answer = (markdown, source, from) => ({ ...page, source, ...(from ? { from } : {}), total: markdown.length,
                      markdown: markdown.slice(offset, offset + limit), end: Math.min(markdown.length, offset + limit),
                      truncated: offset + limit < markdown.length });
                    const type = String(dom.contentType(document) ?? "").toLowerCase();
                    if (/^text\/(plain|markdown|x-markdown)$/.test(type)) return answer(dom.text(dom.body(document) ?? dom.html(document)) ?? "", "document");
                    // A Markdown copy the page itself links on its own site: an alternate,
                    // or a link to the page's own address ending in .md.
                    const candidates = [];
                    for (const link of dom.query(document, "link[rel~='alternate' i][type]")) {
                      if (/^text\/(x-)?markdown$/i.test(squash(dom.attribute(link, "type")))) {
                        const url = own(dom.attribute(link, "href"));
                        if (url) candidates.push(url);
                      }
                    }
                    const path = location.pathname;
                    const copies = new Set([path + ".md", path.replace(/\/$/, "") + ".md", path.replace(/\.html?$/i, ".md")]);
                    if (path.endsWith("/")) copies.add(path + "index.md");
                    copies.delete(path);
                    for (const anchor of dom.query(document, "a[href]")) {
                      const url = own(dom.attribute(anchor, "href"));
                      if (url && copies.has(url.pathname)) candidates.push(url);
                    }
                    const tried = new Set();
                    for (const url of candidates) {
                      url.hash = "";
                      if (tried.has(url.href) || tried.size >= 2) continue;
                      tried.add(url.href);
                      const controller = new AbortController();
                      const timer = setTimeout(() => controller.abort(), 5000);
                      try {
                        const response = await fetch(url.href, { method: "GET", mode: "same-origin", credentials: "same-origin",
                          redirect: "follow", headers: { Accept: "text/markdown, text/plain;q=0.9" }, signal: controller.signal });
                        const served = (response.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
                        if (!response.ok || !own(response.url) || !/^text\/(markdown|x-markdown|plain)$/.test(served)) continue;
                        const reader = response.body.getReader();
                        const chunks = [];
                        let size = 0;
                        while (size <= 4_000_000) {
                          const { done, value } = await reader.read();
                          if (done) break;
                          chunks.push(value);
                          size += value.length;
                        }
                        reader.cancel().catch(() => {});
                        const bytes = new Uint8Array(size);
                        let at = 0;
                        for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.length; }
                        const text = new TextDecoder().decode(bytes).replace(/\r\n?/g, "\n").trim();
                        if (text) return answer(text, "site", url.pathname + url.search);
                      } catch {} finally { clearTimeout(timer); }
                    }
                    // A copy of the document without what the page hides, its form
                    // fields, scripts and frames, and with no names or ids a form's or
                    // the document's properties could answer, for Readability to read.
                    const copy = dom.clone(document, true);
                    const live = [...dom.query(document, "body *")];
                    const copied = [...dom.query(copy, "body *")];
                    if (live.length !== copied.length) throw new Error("The page changed while Ode read it.");
                    const dropped = new Set(["INPUT", "TEXTAREA", "SELECT", "SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "IFRAME",
                      "FRAME", "FRAMESET", "OBJECT", "EMBED", "CANVAS"]);
                    const removing = [];
                    let gone = null;
                    live.forEach((node, index) => {
                      if (gone && dom.contains(gone, node)) return;
                      if (dropped.has(tagOf(node)) || hidden(node)) { removing.push(copied[index]); gone = node; }
                    });
                    for (const node of removing) dom.remove(node);
                    for (const node of dom.query(copy, "*")) {
                      const tag = tagOf(node);
                      if (tag !== "META") dom.unset(node, "name");
                      if (["BUTTON", "FIELDSET", "OUTPUT", "IMG", "FORM"].includes(tag)) dom.unset(node, "id");
                    }
                    let root = null;
                    let source = "page";
                    if (!fullPage) {
                      try {
                        const article = new Readability(copy, { serializer: (node) => node, disableJSONLD: true }).parse();
                        if (article?.content && squash(dom.text(article.content))) { root = article.content; source = "main"; }
                      } catch {}
                    }
                    root ??= dom.body(copy) ?? dom.html(copy);
                    // Tracking parameters say nothing an agent needs.
                    const tracking = /^(utm_.*|fbclid|gclid|dclid|gbraid|wbraid|msclkid|mc_cid|mc_eid|igshid|yclid|_hsenc|_hsmi)$/i;
                    const address = (value) => {
                      try {
                        const url = new URL(value, location.href);
                        for (const key of [...url.searchParams.keys()]) if (tracking.test(key)) url.searchParams.delete(key);
                        return shorten(url.href);
                      } catch { return value; }
                    };
                    for (const link of dom.all(root, "a[href]")) dom.attribute(link, "href") !== null &&
                      link.setAttribute("href", address(link.href));
                    for (const image of dom.all(root, "img")) {
                      const src = dom.attribute(image, "src") ?? "";
                      if (!src || src.startsWith("data:")) dom.remove(image);
                      else image.setAttribute("src", address(image.src));
                    }
                    // A table of data, as Readability tells it from one that lays a page
                    // out, or one with headers and no table inside it, becomes a Markdown
                    // table; a layout table's cells stay text.
                    for (const table of dom.all(root, "table")) {
                      const data = table._readabilityDataTable === true || (source === "page" &&
                        dom.all(table, "th, caption").length > 0 && dom.all(table, "table").length === 0);
                      if (!data) continue;
                      table.setAttribute("data-ode-table", "");
                      dom.all(table, "tr")[0]?.setAttribute("data-ode-head", "");
                    }
                    const inTable = (node) => node.closest?.("table")?.hasAttribute("data-ode-table") === true;
                    const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced", bulletListMarker: "-" });
                    turndown.addRule("tableCell", { filter: (node) => ["TH", "TD"].includes(node.nodeName) && inTable(node),
                      replacement: (content) => " " + content.replace(/\s*\n+\s*/g, " ").replace(/\|/g, "\\|").trim() + " |" });
                    turndown.addRule("tableRow", { filter: (node) => node.nodeName === "TR" && inTable(node),
                      replacement: (content, node) => {
                        const row = "|" + content + "\n";
                        if (!node.hasAttribute("data-ode-head")) return row;
                        return row + "|" + " --- |".repeat(Math.max(1, node.children.length)) + "\n";
                      } });
                    turndown.addRule("tableSection", { filter: (node) => ["THEAD", "TBODY", "TFOOT"].includes(node.nodeName) && inTable(node),
                      replacement: (content) => content });
                    turndown.addRule("table", { filter: (node) => node.nodeName === "TABLE" && node.hasAttribute("data-ode-table"),
                      replacement: (content) => "\n\n" + content.replace(/\n+/g, "\n").trim() + "\n\n" });
                    const markdown = turndown.turndown(root).replace(/^(\s*)-   /gm, "$1- ").replace(/^(\s*)(\d+)\.  /gm, "$1$2. ")
                      .replace(/\n{3,}/g, "\n\n").trim();
                    return answer(markdown, source);
                    """#)
    }

    // MARK: - Actions - Elements

    /// Scrolls the element `uid` names into view and answers where it is in
    /// the viewport, in CSS pixels, with its role and name; or an error. An
    /// element in a frame of the page's own origin is placed in the page's
    /// viewport.
    static func locate(_ uid: String) -> Self {
        Self(
            source: state + """
                const target = element(\(json(uid)));
                if (!target) return { error: "unknown" };
                const frames = [];
                for (let frame = frameOf(target); frame; frame = frameOf(frame)) frames.unshift(frame);
                for (const frame of frames) dom.scroll(frame, { block: "center", inline: "center", behavior: "instant" });
                dom.scroll(target, { block: "center", inline: "center", behavior: "instant" });
                const box = dom.box(target);
                let left = box.left;
                let top = box.top;
                for (const frame of frames) {
                  const outer = dom.box(frame);
                  const style = (dom.view(dom.owner(frame)) ?? window).getComputedStyle(frame);
                  left += outer.left + dom.clientLeft(frame) + (parseFloat(style.paddingLeft) || 0);
                  top += outer.top + dom.clientTop(frame) + (parseFloat(style.paddingTop) || 0);
                }
                const tag = tagOf(target);
                return { x: left + box.width / 2, y: top + box.height / 2, left, top,
                  width: box.width, height: box.height, viewportWidth: innerWidth, viewportHeight: innerHeight,
                  tag: tag.toLowerCase(), editable: (isHTML(target) && dom.editable(target) === true) || ["INPUT", "TEXTAREA"].includes(tag),
                  menu: tag === "SELECT" };
                """)
    }

    /// What an agent's text would go into, before any of it is written: the
    /// element `uid` names, or, without one, the element the page's focus is
    /// in, through shadow roots and frames of the page's own origin. Answers
    /// its input type, empty for anything but an input, and its autocomplete
    /// attribute, both lowercased; or an error, which is `unseen` when the
    /// focus is in a frame of another origin or a component's closed shadow
    /// root, whose field Ode can't see.
    static func field(_ uid: String?) -> Self {
        Self(
            source: state + """
                const uid = \(json(uid));
                const found = uid === null ? focused() : { target: element(uid), elsewhere: false };
                const target = found.target;
                if (uid !== null && !target) return { error: "unknown" };
                if (found.elsewhere) return { error: "unseen" };
                return { type: target && tagOf(target) === "INPUT" ? String(target.type ?? "").toLowerCase() : "",
                  autocomplete: String((target && dom.attribute(target, "autocomplete")) ?? "").toLowerCase() };
                """)
    }

    /// Readies the element `uid` names for new text: focuses it and selects
    /// what it holds, so typing replaces it; or chooses the menu option whose
    /// label or value is `value`.
    static func prepareFill(_ uid: String, value: String) -> Self {
        Self(
            source: state + """
                const target = element(\(json(uid)));
                if (!target) return { error: "unknown" };
                const value = \(json(value));
                const tag = tagOf(target);
                if (tag === "SELECT") {
                  const option = [...target.options].find((item) => item.label === value || item.value === value || item.text.trim() === value);
                  if (!option) return { error: "option" };
                  target.value = option.value;
                  target.dispatchEvent(new Event("input", { bubbles: true }));
                  target.dispatchEvent(new Event("change", { bubbles: true }));
                  return { chosen: option.label || option.text };
                }
                const editable = isHTML(target) && dom.editable(target) === true;
                if (!(editable || ["INPUT", "TEXTAREA"].includes(tag))) return { error: "editable" };
                dom.scroll(target, { block: "center", inline: "center", behavior: "instant" });
                // The frames that hold the element take the focus first, as a click would give it.
                const frames = [];
                for (let frame = frameOf(target); frame; frame = frameOf(frame)) frames.unshift(frame);
                for (const frame of frames) dom.focus(frame);
                dom.focus(target);
                if (editable) {
                  const owner = dom.owner(target);
                  const range = owner.createRange();
                  range.selectNodeContents(target);
                  const selection = dom.view(owner).getSelection();
                  selection.removeAllRanges();
                  selection.addRange(range);
                  if (!value) owner.execCommand("delete");
                } else {
                  target.select?.();
                  if (!value) {
                    const prototype = tag === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
                    Object.getOwnPropertyDescriptor(prototype, "value").set.call(target, "");
                    target.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "deleteContentBackward" }));
                  }
                }
                return { ready: true };
                """)
    }

    /// The page's readable text as Markdown, within `limit` characters:
    /// headings, paragraphs, list items, quotes, code and links, leaving out
    /// what the page hides and every form field's value, a password's above
    /// all.
    static func readText(limit: Int) -> Self {
        Self(
            source: """
                const limit = \(limit);
                const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "CANVAS", "IFRAME", "INPUT",
                  "TEXTAREA", "SELECT", "OPTION"]);
                const blocks = new Set(["P", "DIV", "SECTION", "ARTICLE", "MAIN", "HEADER", "FOOTER", "ASIDE", "NAV",
                  "FIGURE", "FIGCAPTION", "TABLE", "TR", "UL", "OL", "DL", "DT", "DD", "FORM", "FIELDSET", "DETAILS", "SUMMARY"]);
                const out = [];
                let size = 0;
                let truncated = false;
                const push = (text) => {
                  if (truncated) return;
                  if (size + text.length > limit) { out.push(text.slice(0, limit - size)); truncated = true; size = limit; return; }
                  out.push(text); size += text.length;
                };
                const hidden = (node) => {
                  if (node.hidden || node.getAttribute("aria-hidden") === "true") return true;
                  if (!node.checkVisibility) return false;
                  // A display: contents wrapper has no box of its own, so only the visibility it
                  // passes down, its own or an ancestor's, hides what it holds.
                  const style = getComputedStyle(node);
                  if (style.display === "contents") return style.visibility !== "visible";
                  return !node.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true, opacityProperty: true,
                    visibilityProperty: true });
                };
                const inline = (node) => {
                  if (node.nodeType === Node.TEXT_NODE) return node.textContent.replace(/\\s+/g, " ");
                  if (node.nodeType !== Node.ELEMENT_NODE || skipped.has(node.tagName) || hidden(node)) return "";
                  const text = [...node.childNodes].map(inline).join("");
                  if (node.tagName === "A" && node.href && text.trim()) return `[${text.trim()}](${node.href})`;
                  if (node.tagName === "IMG") return node.alt ? `![${node.alt}]` : "";
                  if (node.tagName === "CODE") return text ? "`" + text + "`" : "";
                  if (node.tagName === "BR") return "\\n";
                  if (node.tagName === "STRONG" || node.tagName === "B") return text.trim() ? `**${text.trim()}**` : text;
                  return text;
                };
                const walk = (node, depth) => {
                  if (truncated || node.nodeType !== Node.ELEMENT_NODE || skipped.has(node.tagName) || hidden(node)) return;
                  const tag = node.tagName;
                  const heading = /^H([1-6])$/.exec(tag);
                  if (heading) { const text = inline(node).trim(); if (text) push("#".repeat(+heading[1]) + " " + text + "\\n\\n"); return; }
                  if (tag === "LI") {
                    // A nested list follows its item, indented, rather than running into its text.
                    const own = [...node.childNodes].filter((child) => !["UL", "OL"].includes(child.tagName)).map(inline).join("").trim();
                    if (own) push("  ".repeat(Math.max(depth, 0)) + "- " + own + "\\n");
                    for (const child of node.children) if (["UL", "OL"].includes(child.tagName)) walk(child, depth);
                    return;
                  }
                  if (tag === "PRE") { push("```\\n" + node.innerText + "\\n```\\n\\n"); return; }
                  if (tag === "BLOCKQUOTE") { const text = inline(node).trim(); if (text) push("> " + text + "\\n\\n"); return; }
                  if (tag === "UL" || tag === "OL") { for (const child of node.children) walk(child, depth + 1); push("\\n"); return; }
                  const hasBlocks = [...node.children].some((child) => blocks.has(child.tagName) || /^H[1-6]$/.test(child.tagName)
                    || ["LI", "PRE", "BLOCKQUOTE", "UL", "OL"].includes(child.tagName));
                  if (!hasBlocks) { const text = inline(node).trim(); if (text) push(text + "\\n\\n"); return; }
                  for (const child of node.childNodes) {
                    if (child.nodeType === Node.TEXT_NODE) { const text = child.textContent.trim(); if (text) push(text + "\\n\\n"); }
                    else walk(child, depth);
                  }
                };
                if (document.body) walk(document.body, -1);
                return { url: location.href, title: document.title, text: out.join("").replace(/\\n{3,}/g, "\\n\\n").trim(), truncated };
                """)
    }

    /// Whether the page shows `text` now, or, without text, whether it has
    /// finished loading.
    static func shows(_ text: String?) -> Self {
        Self(
            source: """
                const text = \(json(text));
                if (text === null) return document.readyState === "complete";
                return (document.body?.innerText ?? "").includes(text);
                """)
    }

    private static func json(_ value: String?) -> String {
        value.map(encoded) ?? "null"
    }

    private static func encoded(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data("null".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
