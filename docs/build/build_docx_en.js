// Documizer – Product Documentation (Word), CSBG, English edition.
// Gleicher Aufbau wie build_docx.js; nur die Inhalte sind uebersetzt.
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow,
  TableCell, WidthType, BorderStyle, ShadingType, ImageRun, Header, Footer, PageNumber,
  TableOfContents, LevelFormat, PositionalTab, PositionalTabAlignment,
  PositionalTabRelativeTo, PositionalTabLeader, VerticalAlign, PageBreak,
} = require('docx');

const OUT = process.argv[2];
const LOGO = fs.readFileSync(path.join(__dirname, 'csbg_logo.png'));

// Akzent ist das Markenblau aus dem CSBG-Logo (#0063A6), ACCFILL sein heller
// Anstrich fuer die Kaesten, CODE ein dunkleres Blau fuer Inline-Code.
const ACC = '0063A6', GREY = '808285', INK = '2B2B2B', MUTED = '5F6062';
const FILL = 'F4F4F5', ACCFILL = 'E9F2F8', RULE = 'D9D9DB', CODE = '0A4D80';
const FONT = 'Arial', MONO = 'Consolas';
const W = 9638; // type area A4 with 2 cm margins

// ---------- inline markup: **bold**, *italic*, `code` ----------
function runs(text, base = {}) {
  const out = [];
  for (const part of text.split(/(\*\*[^*]+\*\*|\*[^*\s][^*]*\*|`[^`]+`)/)) {
    if (!part) continue;
    if (part.startsWith('**')) out.push(new TextRun({ ...base, text: part.slice(2, -2), bold: true }));
    else if (part.startsWith('*')) out.push(new TextRun({ ...base, text: part.slice(1, -1), italics: true }));
    else if (part.startsWith('`')) out.push(new TextRun({
      ...base, text: part.slice(1, -1), font: MONO, size: Math.max((base.size || 21) - 2, 15),
      color: base.color === 'FFFFFF' ? 'FFFFFF' : CODE,
    }));
    else out.push(new TextRun({ ...base, text: part }));
  }
  return out;
}
const P = (t, o = {}) => new Paragraph({ children: runs(t, o.run || {}), spacing: { after: 140, line: 288 }, ...o.para });
const LEAD = (t) => new Paragraph({ children: runs(t, { size: 24, color: MUTED }), spacing: { after: 220, line: 312 } });
const H1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: true, children: [new TextRun(t)] });
const H2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)] });
const H3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(t)] });
const B = (t, lvl = 0) => new Paragraph({ children: runs(t), numbering: { reference: 'bul', level: lvl }, spacing: { after: 80, line: 276 } });
const N = (t, ref = 'num') => new Paragraph({ children: runs(t), numbering: { reference: ref, level: 0 }, spacing: { after: 80, line: 276 } });
const SP = (after = 120) => new Paragraph({ children: [], spacing: { after } });

const NOB = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };
const NOBORDERS = { top: NOB, bottom: NOB, left: NOB, right: NOB, insideHorizontal: NOB, insideVertical: NOB };
const thin = { style: BorderStyle.SINGLE, size: 4, color: RULE };

// ---------- table ----------
function table(headers, rows, widths) {
  const sum = widths.reduce((a, b) => a + b, 0);
  const cell = (t, w, head, alt) => new TableCell({
    width: { size: w, type: WidthType.DXA },
    shading: head ? { type: ShadingType.CLEAR, color: 'auto', fill: ACC }
                  : alt ? { type: ShadingType.CLEAR, color: 'auto', fill: 'FAFAFA' } : undefined,
    margins: { top: 70, bottom: 70, left: 110, right: 110 },
    verticalAlign: VerticalAlign.TOP,
    children: [new Paragraph({
      children: runs(t, head ? { bold: true, color: 'FFFFFF', size: 18 } : { size: 18 }),
      spacing: { after: 0, line: 264 },
    })],
  });
  return [new Table({
    width: { size: sum, type: WidthType.DXA },
    columnWidths: widths,
    borders: { top: thin, bottom: thin, left: NOB, right: NOB, insideHorizontal: thin, insideVertical: NOB },
    rows: [
      new TableRow({ tableHeader: true, children: headers.map((h, i) => cell(h, widths[i], true)) }),
      ...rows.map((r, ri) => new TableRow({ cantSplit: true, children: r.map((c, i) => cell(c, widths[i], false, ri % 2 === 1)) })),
    ],
  }), SP(160)];
}

// ---------- benefit callout ----------
function callout(title, lines) {
  const kids = [new Paragraph({ children: [new TextRun({ text: title, bold: true, color: ACC, size: 20 })], spacing: { after: 60 } })];
  for (const l of [].concat(lines)) kids.push(new Paragraph({ children: runs(l, { size: 20 }), spacing: { after: 60, line: 276 } }));
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: [W],
    borders: { top: NOB, bottom: NOB, right: NOB, insideHorizontal: NOB, insideVertical: NOB,
               left: { style: BorderStyle.SINGLE, size: 24, color: ACC } },
    rows: [new TableRow({ cantSplit: true, children: [new TableCell({
      width: { size: W, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, color: 'auto', fill: ACCFILL },
      margins: { top: 140, bottom: 100, left: 220, right: 220 }, children: kids })] })],
  }), SP(180)];
}

// ---------- code block ----------
function code(lines) {
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: [W],
    borders: { top: NOB, bottom: NOB, right: NOB, insideHorizontal: NOB, insideVertical: NOB,
               left: { style: BorderStyle.SINGLE, size: 18, color: GREY } },
    rows: [new TableRow({ cantSplit: true, children: [new TableCell({
      width: { size: W, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, color: 'auto', fill: FILL },
      margins: { top: 120, bottom: 120, left: 200, right: 200 },
      children: lines.map(l => new Paragraph({
        children: [new TextRun({ text: l === '' ? ' ' : l, font: MONO, size: 16, color: INK })],
        spacing: { after: 0, line: 240 } })) })] })],
  }), SP(180)];
}

// ---------- key figures ----------
function kpis(items) {
  const w = Math.floor(W / items.length);
  const widths = items.map((_, i) => i === items.length - 1 ? W - w * (items.length - 1) : w);
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: widths,
    borders: { ...NOBORDERS, top: { style: BorderStyle.SINGLE, size: 18, color: ACC } },
    rows: [new TableRow({ children: items.map(([num, label], i) => new TableCell({
      width: { size: widths[i], type: WidthType.DXA },
      margins: { top: 160, bottom: 80, left: 60, right: 160 },
      children: [
        new Paragraph({ children: [new TextRun({ text: num, bold: true, size: 44, color: ACC })], spacing: { after: 40 } }),
        new Paragraph({ children: runs(label, { size: 17, color: MUTED }), spacing: { after: 0, line: 252 } }),
      ] })) })],
  }), SP(240)];
}

// ---------- cards (three reports) ----------
function cards(items) {
  const gap = 180;
  const w = Math.floor((W - gap * (items.length - 1)) / items.length);
  const widths = []; const cells = [];
  items.forEach(([rep, title, text], i) => {
    widths.push(w);
    cells.push(new TableCell({
      width: { size: w, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, color: 'auto', fill: FILL },
      margins: { top: 180, bottom: 160, left: 180, right: 180 },
      borders: { top: { style: BorderStyle.SINGLE, size: 18, color: ACC }, bottom: NOB, left: NOB, right: NOB },
      children: [
        new Paragraph({ children: [new TextRun({ text: rep, font: MONO, size: 16, color: ACC })], spacing: { after: 60 } }),
        new Paragraph({ children: [new TextRun({ text: title, bold: true, size: 22 })], spacing: { after: 80 } }),
        new Paragraph({ children: runs(text, { size: 18, color: MUTED }), spacing: { after: 0, line: 264 } }),
      ] }));
    if (i < items.length - 1) {
      widths.push(gap);
      cells.push(new TableCell({ width: { size: gap, type: WidthType.DXA }, borders: { top: NOB, bottom: NOB, left: NOB, right: NOB }, children: [new Paragraph('')] }));
    }
  });
  const total = widths.reduce((a, b) => a + b, 0);
  return [new Table({ width: { size: total, type: WidthType.DXA }, columnWidths: widths, borders: NOBORDERS,
                      rows: [new TableRow({ cantSplit: true, children: cells })] }), SP(240)];
}

// ---------- scenario ----------
function scenario(title, task, delivers, benefit) {
  return [
    H2(title),
    new Paragraph({ keepNext: true, children: [new TextRun({ text: 'The task', bold: true, color: GREY, size: 18, allCaps: true })], spacing: { after: 60 } }),
    P(task, { para: { keepNext: true } }),
    new Paragraph({ keepNext: true, children: [new TextRun({ text: 'What the Documizer delivers', bold: true, color: GREY, size: 18, allCaps: true })], spacing: { after: 60 } }),
    ...delivers.map(d => B(d)),
    SP(80),
    ...callout('Your benefit', benefit),
  ];
}

// =====================================================================
// Cover
// =====================================================================
const cover = [
  new Paragraph({ alignment: AlignmentType.RIGHT, spacing: { after: 2200 },
    children: [new ImageRun({ type: 'png', data: LOGO, transformation: { width: 190, height: 66 } })] }),
  new Paragraph({ children: [new TextRun({ text: 'SAP S/4HANA AND SAP ERP · ON PREMISE · CLASSIC ABAP', size: 18, color: ACC, bold: true, characterSpacing: 40 })], spacing: { after: 240 } }),
  new Paragraph({ children: [new TextRun({ text: 'Documizer', bold: true, size: 112, color: INK })], spacing: { after: 120 } }),
  new Paragraph({ children: [new TextRun({ text: 'Documentation, transfer and AI analysis', size: 40, color: GREY })], spacing: { after: 40 } }),
  new Paragraph({ children: [new TextRun({ text: 'for SAP development and customizing', size: 40, color: GREY })],
    border: { bottom: { style: BorderStyle.SINGLE, size: 24, color: ACC, space: 18 } }, spacing: { after: 480 } }),
  new Paragraph({ children: runs('A single ABAP report, installed in seconds. It documents what your system **really** contains — and, if you want, carries it into another system. No transport, no abapGit, no additional repository objects.', { size: 26, color: INK }),
    spacing: { after: 2400, line: 336 } }),
  ...kpis([
    ['3', 'reports: customizing, development, check configuration'],
    ['1', 'source per report — copy and paste into SE38'],
    ['20+', 'object types that can be transferred'],
    ['0', 'transports, installations or extra objects'],
  ]),
  new Paragraph({ spacing: { before: 600, after: 40 }, children: [new TextRun({ text: 'Product documentation · October 2026', size: 18, color: MUTED })] }),
  new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: 'Christian Gathmann · gathmann@csbg.de', size: 18, color: MUTED })] }),
  new Paragraph({ children: [new TextRun({ text: 'C. Gathmann Computer-System-Beratung GmbH (CSBG), Bremen', size: 18, bold: true, color: INK })] }),
];

// =====================================================================
// At a glance + contents
// =====================================================================
const glance = [
  new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun('At a glance')] }),
  LEAD('Anyone responsible for an SAP system knows the problem: the documentation describes what was once planned. What is actually in the system is known only to the system itself. The Documizer asks it — and turns the answer into a document that people can read, systems can read back in, and AI assistants can analyse.'),
  ...cards([
    ['ZDOCUMIZER_IMG', 'Customizing', 'Reads a structure tree of the Implementation Guide, picks up SAP’s documentation for each IMG activity and follows the customizing behind it down to the table contents. Creates a BC set on request.'],
    ['ZDOCUMIZER_DEV', 'Development', 'Starts at a package, a single object or a transport request — report, class, table, CDS, RAP, IDoc, UI5 app, form. Delivers fields, methods, texts, source code, where-used lists. And imports.'],
    ['ZDOCUMIZER_ATC', 'Check configuration', 'Documents ATC and Code Inspector variants: which checks run, at which priority, customer prioritisation, pseudo comment, pragma and exemptions.'],
  ]),
  H3('What sets the Documizer apart'),
  B('**Installed in seconds.** Each report is a single source. Paste it into SE38, activate, done — even where nothing may be installed and no transport may be imported.'),
  B('**One format for everything.** The XML is complete, versioned and can be read back without loss. The HTML is self-contained and will still open years from now without any rework.'),
  B('**Documentation that can go back into a system.** From the same document, the development report creates tables, classes, CDS views, RAP objects, IDoc types, UI5 apps and Adobe forms in another system.'),
  B('**A transport is a source too.** Enter the request number and the document describes exactly what that transport contains — with source code and where-used lists.'),
  B('**Not only S/4HANA.** The same source runs on classic SAP ERP — verified down to SAP_BASIS 7.40. What does not exist there is looked up dynamically and left empty instead of ending the run.'),
  B('**Never silently incomplete.** If a limit takes effect, the document says so. Every run can check itself: serialise, read back, compare.'),
  B('**Safe in a customer system.** SAP’s authorization checks stay switched on. Customizing is never written directly; it is offered as a BC set for review.'),
  B('**Open.** Apache 2.0 licence, sources on GitHub — see chapter 12.'),
  new Paragraph({ children: [new PageBreak()] }),
  new Paragraph({ children: [new TextRun({ text: 'Contents', bold: true, size: 36, color: ACC })], spacing: { after: 240 } }),
  new TableOfContents('Contents', { hyperlink: true, headingStyleRange: '1-1' }),
];

// =====================================================================
// 1 Why
// =====================================================================
const why = [
  H1('1  Why Documizer'),
  LEAD('SAP systems grow over years. Packages, classes, CDS views, customizing entries — and with every release the documentation drifts further away from reality.'),
  H2('Four problems from everyday project work'),
  ...table(['Problem', 'What it costs'], [
    ['**Documentation is out of date.** It describes the design, not the state of the system.', 'Onboarding takes weeks; faults are looked for in the wrong place.'],
    ['**Customer systems are sealed off.** No installation, no transports, abapGit is not an option.', 'Tools that are a matter of course in your own system are simply not available at the customer.'],
    ['**Knowledge sits inside the system.** Who uses what, which fields are read, which checks apply — that lives in tables, not in documents.', 'Impact analyses are estimated instead of looked up.'],
    ['**AI needs context.** An assistant is only as helpful as the information it is given.', 'Individual code snippets are rarely enough for research and troubleshooting.'],
  ], [4600, 5038]),
  H2('The answer'),
  P('The Documizer reads straight from the running system — through SAP’s standard APIs wherever they exist. It writes nothing in the process, unless you explicitly ask it to import. The result is a document structured into chapters, in two formats:'),
  B('**XML** — complete, versioned, machine-readable. The transfer format for the import and the ideal input for AI assistants.'),
  B('**HTML** — a single file with a table of contents, embedded styling and no JavaScript. For reading, passing on, filing away.'),
  ...callout('The principle', 'One source per report. One format for people, systems and AI. No installation in the target system.'),
];

// =====================================================================
// 2 Scenarios
// =====================================================================
const scen = [
  H1('2  Seven scenarios'),
  LEAD('The same report, the same file — seven tasks that would otherwise each call for a tool of their own.'),
  ...scenario('Documenting development',
    'A package, an application or a single object is to be described completely — for handover, maintenance, audit, or onboarding new colleagues.',
    ['Short texts, author and package for each object, and the object documentation on request',
     'Field lists of tables, structures, views and CDS views with data elements and keys',
     'Classes with superclass, interfaces, components and local classes — including the handlers of a RAP behavior pool',
     'Source code, where-used list with the exact occurrences, and the objects that are used'],
    'Documentation that matches the system — regenerated at the push of a button instead of being maintained by hand.'),
  ...scenario('Documenting a transport',
    'What is in this request? Before an acceptance, a review or an import into production it should be readable what it actually changes.',
    ['The request number as the start point — the value help shows your own requests',
     'A header with kind, status, short text, owner, date, target system and the tasks below it',
     'Every object of the request as a chapter, with details, source code and where-used lists',
     'Customizing entries, deletions and missing objects are named up front rather than dropped'],
    'A transport becomes readable before it arrives — and with the import’s test run you even see what it would change in the target system.'),
  ...scenario('Documenting IMG settings',
    'The customizing of an area or a project is to be recorded so that it can be followed — with explanation and actual values.',
    ['Structure tree of the Implementation Guide with all IMG activities',
     'SAP’s standard documentation for each activity, rendered as readable text',
     'The customizing tables behind it with field list and content — customer entries only, if you wish',
     'Project status and memo from an IMG project'],
    'The customizing documentation comes out of the system itself. SAP’s explanation sits right next to your values.'),
  ...scenario('Transferring development',
    'Objects are to go into another system — from a sandbox into the customer system, say — where neither transports can be imported nor abapGit installed.',
    ['Definition data in the XML: the same structures SAP returns when reading and expects when creating',
     'Import of more than 20 object types, from the domain to the Adobe form',
     'Test run as the default, existing objects are left untouched',
     'Objects can be skipped or renamed one by one, package rules old → new, request and task assigned automatically'],
    'Development travels as a single file. The target system only needs the Documizer itself.'),
  ...scenario('Transferring customizing via BC set',
    'Customizing from one system is to be reproduced in another — in a controlled and traceable way.',
    ['The IMG document becomes a Business Configuration Set',
     'Activation happens in SCPR20: with a log, a transport request, a preview and a way back',
     'A list of gaps names the tables still missing in the target system — the development report exports exactly those'],
    'No report writes into your customizing tables. You decide what is activated.'),
  ...scenario('AI-assisted analysis',
    'An AI assistant such as Claude is to help with research, troubleshooting or documentation — and needs the full context for that.',
    ['A structured XML with source code, field lists, where-used lists and customizing in one piece',
     'Unambiguous chapters and object references that questions can refer to',
     'Notes wherever something was shortened — the assistant knows what it cannot see'],
    'Instead of copying individual snippets, you hand the assistant the whole application — and get well-founded answers.'),
  ...scenario('Making check standards transparent',
    'Which ATC checks run, at which priority, and how can findings be suppressed? The answer is spread across clusters and classes.',
    ['Check variants with categories, checks and all findings',
     'Priority of the check class next to the customer-specific prioritisation',
     'Pseudo comment and pragma for each finding, exemptions granted'],
    'Code standards become readable and comparable between systems.'),
];

// =====================================================================
// 3 Installation
// =====================================================================
const install = [
  H1('3  Installed in seconds'),
  LEAD('Each report is a single source file. There is nothing to transport and nothing to configure.'),
  N('Call SE38, choose a program name (`ZDOCUMIZER_DEV`, for instance), select **Create**, type *Executable program*.'),
  N('Paste the source, save, activate.'),
  N('Enter the program title under *Goto → Attributes* — the only thing set by hand.'),
  SP(80),
  ...callout('Why this works', [
    'No global classes, no text elements, no tables of its own, no Simple Transformation, no message class. All screen texts live in the source — in English, and in German for a German logon.',
    'XML is written and read through the kernel classes `cl_sxml_string_writer` and `cl_sxml_string_reader`. They exist in every system.']),
  H2('Report documentation in the system (optional)'),
  P('The helper report `ZDOCUMIZER_DOCU` writes the SAP report documentation for the three reports — visible in SE38 under *Documentation* and through the info icon on the selection screen. It is not needed for the reports to work; it makes sense when other colleagues work with the Documizer in that system.'),
  H2('System requirements'),
  ...table(['Item', 'Requirement'], [
    ['Platform', 'SAP S/4HANA on premise **and** SAP ERP (R/3), classic ABAP'],
    ['Release', 'Verified on SAP_BASIS 758 (S/4HANA 2023). Rebuilt for older levels: POSIX `REGEX` instead of `PCRE`, no constructs that only exist from 7.55 — the IMG report demonstrably runs on a customer system with SAP_BASIS 7.40'],
    ['Authorization for documentation', 'Read access to the repository; `S_TABU_NAM` for customizing content'],
    ['Authorization for import', '`S_DEVELOP` for the objects and packages to be created — SAP’s checks stay switched on'],
    ['Operation', 'Dialog and background; in the background, output goes to the application server'],
  ], [3000, 6638]),
  ...callout('On classic ERP as well', 'Newer object types do not exist in an older system — RAP, CDS, UI5. The report therefore looks them up dynamically and runs where they are absent too: what is missing stays empty instead of ending the run.'),
];

// =====================================================================
// 4 IMG report
// =====================================================================
const img = [
  H1('4  Documenting customizing: ZDOCUMIZER_IMG'),
  LEAD('The IMG report reads a structure tree of the Implementation Guide, assigns its IMG activity to each node and goes all the way down to the customizing entries.'),
  H2('What the document contains'),
  ...code([
    '1  <root node>                              structure chapter',
    '   1.1 <sub-node>                           structure chapter',
    '       1.1.1 <IMG activity>                 activity chapter',
    '             ├─ Description                SAP documentation, made readable',
    '             ├─ Technical assignment       activity, transaction, doc object',
    '             ├─ Project status / memo      in project mode',
    '             ├─ Object per assignment      field list, selection method, row count',
    '             ├─ Customizing content        data according to the volume settings',
    '             ├─ Transport history          requests for the table',
    '             └─ Objects used               program behind the transaction',
  ]),
  H2('Selection screen'),
  ...table(['Field', 'Default', 'Effect'], [
    ['Structure ID (GUID) / or search term for root', '', 'Entry point. The report’s own value help shows root nodes with text, node count and change date — instead of 500 bare GUIDs'],
    ['Project (status/memo) / project nodes only', '', 'Overlays the tree with an IMG project, trims it to that project’s nodes'],
    ['Max. depth / max. chapters', '0 / 300', 'Size of the tree; 0 = all'],
    ['Resolve substructures', 'on', 'Decisive: without it the run ends after the first level'],
    ['Standard documentation / object assignment', 'on / on', 'SAP documentation per activity, assigned customizing objects'],
    ['Read customizing content', 'on', 'Field list and table contents'],
    ['Customer entries only / max. rows', 'on / 500', 'Volume control, see below'],
    ['Transport history / outgoing references', 'off / off', 'Requests per table; program behind the transaction'],
  ], [3500, 1300, 4838]),
  H2('Only what is yours'),
  P('Customizing tables range from three rows to millions. With *customer entries only*, two methods work side by side: the **namespace** of the first key field (Y, Z, `/`) and the **occurrence in transport requests** for that table. That way entries that were never transported, and keys outside the customer namespace, are found as well.'),
  P('Which method applied is stated at the object — not only in the log. If the read authorization is missing, the object appears with a note instead of silently empty.'),
  H2('Project mode'),
  P('An IMG project carries status, progress and a memo for each activity. The report overlays the tree with it and can trim the tree to the nodes being worked on. Structure chapters remain as long as a project node hangs below them; chapter numbers keep their position, and the gaps show what was left out.'),
  ...callout('Measured', 'Project mode with 351 chapters: **0.48 seconds**. The entry point is derived from the project data — instead of walking the entire guide.'),
];

// =====================================================================
// 5 BC sets
// =====================================================================
const bcs = [
  H1('5  Transferring customizing: BC sets and the list of gaps'),
  LEAD('The IMG report in reverse: a document becomes a Business Configuration Set in the target system. Nothing is written yet.'),
  H2('Why a BC set and not direct access'),
  P('The customizing comes into being only when someone activates the set in **SCPR20**. Activation runs with a log, with a transport request, with a preview and with a way back. A report writing straight into customizing tables would have none of that.'),
  ...table(['Blocked when', 'Reason'], [
    ['The table is unknown in the target system', 'A set pointing at a missing table cannot be activated'],
    ['Delivery class is not C, G or E', 'Anything else is not a customizing table'],
    ['Content was shortened during export', 'Shortened content would look complete in the set — on activation the rest would vanish'],
  ], [3800, 5838]),
  H2('The list of gaps closes the loop'),
  P('Customer-specific customizing tables often do not exist yet in the target system — they are development. The IMG report therefore writes a **list of gaps** naming the objects it skipped. In the source system, the development report takes that list as its entry point and exports exactly those objects. Once they are imported, the BC set is created for them too.'),
  ...code([
    'target system   IMG report    create BC set  →  gaps: Z_SKIP_IND, ZV_SKIP_IND',
    'source system   DEV report    entry point AL →  export with definition data',
    'target system   DEV report    import         →  table and view created',
    'target system   IMG report    create BC set  →  complete',
  ]),
  ...callout('Your benefit', 'The target system says for itself what is missing. Only what is genuinely absent there is requested.'),
];

// =====================================================================
// 6 Development report
// =====================================================================
const dev = [
  H1('6  Documenting development: ZDOCUMIZER_DEV'),
  LEAD('The entry point is a pair of type and name, as in the Object Navigator. A package yields package → object type → object; a single object yields the object, everything it uses, and everyone that uses it.'),
  H2('Entry points'),
  ...table(['Code', 'Entry point', 'Code', 'Entry point'], [
    ['`K`', 'Package (default)', '`SB`', 'Service binding'],
    ['`P`', 'Program / report', '`IS`', 'IDoc segment type'],
    ['`C`', 'Class or interface', '`IT`', 'IDoc basic type'],
    ['`FF`', 'Function module', '`U5`', 'UI5 application'],
    ['`F`', 'Function group', '`SF`', 'Smart Form'],
    ['`T`', 'Table / structure', '`AF`', 'Adobe Form (form)'],
    ['`V`', 'View', '`AI`', 'Adobe Form (interface)'],
    ['`D`', 'Data element', '`TR`', '**Transport request / task**'],
    ['`DO`', 'Domain', '`AL`', 'Work list from a list of gaps'],
    ['`W`', 'CDS view', '`MX`', 'Metadata extension'],
    ['`BD`', 'Behavior definition', '`SD`', 'Service definition'],
  ], [900, 3919, 900, 3919]),
  P('Two codes name no object but a list of them: `AL` the list of gaps from the target system and `TR` a transport request. Every object in the list becomes a chapter of its own.'),
  H2('Documenting a transport request'),
  P('With `TR` the name field takes a request or task number; the value help shows your own requests, the most recent first. The header of the run names kind and status, short text, owner, date, target system and the tasks below it. Three peculiarities of the correction system are taken off your hands:'),
  B('**The objects hang off the tasks, not the request.** A request’s own object list is regularly empty — what travels sits in the tasks below it. Both levels are read.'),
  B('**Parts are rolled up to their object.** Besides whole objects a request also lists single methods, includes and table definitions. What gets documented is the object the part belongs to, and each one only once.'),
  B('**Whatever is not a documentable object is named up front:** customizing entries with their table and number of keys plus a pointer to the IMG report, deletions, entries without a catalog object, and objects that no longer exist in the system.'),
  ...callout('Released or modifiable', 'A released request documents what *was* in it; a modifiable one, what *is* in it right now. The second case says so in the header — otherwise the two read the same.'),
  H2('Selection screen'),
  ...table(['Field', 'Default', 'Effect'], [
    ['Subpackages recursively / include local packages', 'on / off', 'Scope in package mode'],
    ['Object type / object name', '', 'Filter on the object list'],
    ['Max. objects', '2000', 'The total count is recorded in the document'],
    ['Object documentation / details', 'on / on', 'Documentation; fields, methods, text elements, fixed values …'],
    ['Output source code / max. lines per object', 'on / 30000', 'Source code; any shortening is stated in the document header'],
    ['Where-used list / also for used objects', 'on / on', 'Who uses the object — with occurrences and fields'],
    ['Outgoing references / reference depth', 'on / 3', 'What the object uses, and how far that is followed'],
    ['Usage depth', '3', 'Document the users found as chapters of their own'],
    ['Exclude SAP standard', 'on', 'Only custom development in the reference lists'],
    ['Definition data for re-import', 'off', 'Technical definition for the import — pulls the XML output along with it'],
  ], [3900, 1300, 4438]),
  H2('Details per object type'),
  ...table(['Object type', 'In the document'], [
    ['Program', 'Title, selection texts, text symbols, headings, object documentation'],
    ['Class, interface', 'Superclass, interfaces, components, implemented interface methods, local classes with their methods; source code as one continuous source'],
    ['Function module, function group', 'Interface with all parameters; list of modules'],
    ['Table, structure', 'Field list with data element or built-in type, and the key'],
    ['View', 'Field list, base tables with join conditions'],
    ['CDS view', 'Field list of the entity, objects used, source code'],
    ['Behavior definition, service definition, metadata extension', 'Description and source code'],
    ['Service binding', 'Binding type, linked service definition, publication state'],
    ['IDoc basic type', 'Segment hierarchy (WE60), message types (WE82), processing modules (WE57)'],
    ['IDoc segment', 'Fields with the data elements that WE31 shows'],
    ['UI5 application', 'Description; with definition data, all files including the directory tree'],
    ['Smart Form', 'Node tree, interface, global definitions and the coding of the code nodes — read from the object model of the Form Builder'],
    ['Adobe Form', 'The form and its interface as one unit: context, fields, handler class; with definition data the layout as a whole'],
    ['Data element, domain', 'Field labels; fixed values'],
  ], [3200, 6438]),
  H2('References in both directions'),
  P('**Outgoing references** show what an object uses. Because SAP’s cross-reference indexes each know only part of the picture, the report also reads the source: `CALL FUNCTION`, `SUBMIT`, table accesses, includes, message classes — and even object names in character literals that are needed at runtime. Every hit is checked against the object catalog before it enters the document.'),
  P('The **where-used list** shows who uses an object: with the program type, for tables with the access type read or write, with occurrences including line numbers — and for structures with the fields touched at each place. For a table, the views and CDS views built on top of it appear as well.'),
  ...callout('Composition is never limited', 'The volume limits apply to usages — never to what an object is made of. The data elements of a table are always collected in full, otherwise it could not be activated in the target system.'),
  H2('Excluding the SAP standard'),
  P('The yardstick is the software component of the package — the same line SAP itself draws. Unlike a name check on Z and Y, it also catches customer objects in reserved namespaces and SAP objects that begin with Z.'),
];

// =====================================================================
// 7 ATC
// =====================================================================
const atc = [
  H1('7  Documenting check standards: ZDOCUMIZER_ATC'),
  LEAD('The third view: not what is in the system, but what it is measured against.'),
  ...table(['Mode', 'Answers'], [
    ['Check variant (V)', 'What **is** checked — one variant or all of them'],
    ['Catalog (K)', 'What **could** be checked — all activated checks'],
  ], [2800, 6838]),
  ...code([
    '1       Check variant    owner, transportable, hidden',
    '1.1       Category',
    '1.1.1       Check        findings with code, priority, customer priority,',
    '                         pseudo comment, pragma, exemptions, text',
  ]),
  P('The list of checks in a variant is not stored in readable form in the database; the report reads it through the Code Inspector API. A check named by a variant but no longer present after an upgrade still gets a chapter — with the note *cannot be loaded*.'),
  ...callout('Measured', 'Standard variant `DEFAULT`: **17 checks, 1,198 findings**, roundtrip identical.'),
];

// =====================================================================
// 8 Output
// =====================================================================
const output = [
  H1('8  Output: XML and HTML'),
  LEAD('Both formats come out of the same chapter model in the same run.'),
  H2('XML — complete, versioned, readable back in'),
  ...code([
    '<documizer version="1.1" type="DEV">',
    '  <meta>',
    '    <system>DV1</system> <client>100</client> <language>E</language>',
    '    <truncated>false</truncated> <node_limit>2000</node_limit> <node_total>44</node_total>',
    '  </meta>',
    '  <chapters>',
    '    <chapter id="1.1.1" level="3" type="OBJECT">',
    '      <title>Z_TABLE - header data</title>',
    '      <object type="TABL" note="field list"> … </object>',
    '      <source> … </source>',
    '      <definition kind="TABL"> … </definition>',
    '    </chapter>',
    '  </chapters>',
    '</documizer>',
  ]),
  B('**Never unnoticed incomplete.** Every shortening — object limit, row limit, source limit — is stated in the header and at the data block.'),
  B('**Comparable between systems.** User, timestamp and client appear only in the header, never in the chapters.'),
  B('**Roundtrip-checked.** On request the report serialises, reads back in, serialises again and compares character by character.'),
  B('**Extensible.** New content goes into new elements; older documents remain readable.'),
  H2('HTML — readable today and in years to come'),
  P('A single file with a table of contents, numbered chapters, tables and source code blocks; CSS embedded, no JavaScript. SAP documentation is converted from ITF into readable text with subheadings. Long blocks sit collapsed behind a line stating their name and size.'),
  H2('Storage and file name'),
  ...table(['Destination', 'Available', 'Note'], [
    ['Download to the PC', 'Dialog', 'Binary in UTF-8 — special characters are preserved'],
    ['Storage on the application server', 'Dialog and background', 'For large runs in the background'],
  ], [3200, 2400, 4038]),
  P('The file name is proposed from system, start object, date and time — `documizer_dev_DV1_z_package1_20260922_101500`, for instance — and can be overwritten freely.'),
];

// =====================================================================
// 9 Import
// =====================================================================
const imp = [
  H1('9  Import: bringing development into another system'),
  LEAD('Read an XML produced in system A and create the objects defined in it in system B — with the same report, without a transport and without abapGit.'),
  H2('What is created'),
  ...table(['Object type', 'Created'], [
    ['Domain, data element', 'with fixed values and texts'],
    ['Table, structure, secondary index', 'with technical settings and foreign keys; indexes after the table'],
    ['View, CDS source', 'with base tables and join conditions; the SQL view arises on activation'],
    ['Report, include', 'with text elements and documentation **in all languages**, GUI status'],
    ['Class, interface', 'as the source-based form that SE24 and ADT show'],
    ['Function group', 'with includes, modules and their interface'],
    ['Message class', 'all messages in all maintained languages'],
    ['Behavior definition, service definition, metadata extension', 'as source code'],
    ['Service binding', 'with binding type and services — deliberately unpublished'],
    ['IDoc segment type, IDoc basic type', 'as a real segment, with the whole hierarchy'],
    ['UI5 application', 'with all files and the directory tree, through the UI5 repository API'],
    ['Adobe Form and interface', 'restored from SAP’s own serialization — the same path that copying in the Form Builder takes'],
    ['Screen, maintenance dialog, transaction, view cluster', 'the complete SM30 apparatus, parameter transactions included'],
  ], [4200, 5438]),
  H2('Safe from the start'),
  B('**Test run is the default.** Every step reports what it would do — writing happens only once you deliberately clear the flag.'),
  B('**What exists stays.** An object that is already there is touched only with *overwrite existing objects*.'),
  B('**The right order.** Domains before data elements before tables before views before programs — the report sorts this out itself.'),
  B('**Activated selectively.** From the user’s inactive objects the import takes only its own; work others have started is left alone.'),
  B('**Checked after the run.** Active version, syntax check for programs — anything conspicuous is reported.'),
  H2('You pick what arrives'),
  P('A list can be put in front of the import: one row per object in the document, with **target name**, **target package** and a tick column **Skip**.'),
  B('**Renaming** applies to the whole document, not just to the object name: the new name replaces the old one in the source code as well, word for word and regardless of case. The word boundary prevents partial hits — `ZKUNDE` leaves `ZKUNDE2` alone. That way even an SAP object can be brought in under a Z name without overwriting the original.'),
  B('**Skip** takes the row out of the run entirely: neither created nor changed, and not verified afterwards. Every skipped row is named up front in the header and again in the log — leaving something out without a note would be a silent gap.'),
  P('Dependencies are not enforced: skip a domain whose data element is imported and you get the familiar activation error. The report warns about it but does not forbid it — often the skipped object exists in the target system already and is precisely what should not be touched.'),
  H2('The test run shows what would change'),
  P('A test run that only says *would be changed* withholds the essential part. For every object that already exists in the target system it therefore compares the source:'),
  ...code([
    'CLAS  ZCL_MAILER   source differs   +12 / -3 lines',
    '        12   DATA lv_a TYPE i.',
    '        13 - lv_a = 1.',
    '        13 + DATA lv_b TYPE i.',
    '        14 + lv_a = 2.',
    '        15   WRITE lv_a.',
    '       ... 240 lines unchanged',
  ]),
  P('New lines in green, dropped ones in red, two lines of context, unchanged stretches summarised. The old state is read from the target system in the same composition the export produces — otherwise differences would show that are none. If nothing differs, the log says *source identical* with the line count.'),
  H2('Packages, request and task'),
  P('Four rule lines **old → new** steer objects from the source package into a target package — `$TMP` → `Z_PACKAGE1`, for instance. The request follows the package of each individual object. If there is no open task for you under the request, the report creates it without a dialog; without that task the correction system would reject the import with a misleading message.'),
  H2('A log that names causes'),
  P('For each object it says what happened and why — with the real return code and the message from the SAP function module. When an activation fails, the log names the missing object behind it:'),
  ...code([
    'PROG Z_REPORT_COPY   created                 560 lines',
    'TEXT Z_REPORT_COPY   text elements set       D:5 E:8',
    'DOKU Z_REPORT_COPY   documentation set       languages E',
    'DTEL Z_ACTION        DDIF_DTEL_ACTIVATE rc 8 missing or inactive: domain Z_ACTION_D',
  ]),
  ...callout('Measured: a RAP application as a single file', 'Package run with source code and definition data: **34 definitions** — 16 CDS views, 8 classes, 2 behavior definitions, service definition and binding, tables, domain, data element and 2 UI5 applications with **76 files in 12 folders**. Roundtrip identical.'),
];

// =====================================================================
// 10 Operation
// =====================================================================
const ops = [
  H1('10  Security and operation'),
  H2('Authorizations remain SAP’s business'),
  P('The IMG report checks `S_TABU_NAM` before every table access; if the authorization is missing, the document says so. During the import, the SAP function modules that are called check `S_DEVELOP` against object and package — and that check stays switched on. The Documizer is therefore not a tool for creating objects that someone would not be allowed to create by hand.'),
  H2('Runtimes'),
  ...table(['Run', 'Scope', 'Duration'], [
    ['IMG, project mode', '351 chapters', '0.48 s'],
    ['DEV, package hierarchy', '10 packages / 352 objects', '0.23 s'],
    ['DEV, CDS with source code', '4 objects', '0.08 s'],
    ['DEV, transport request', '75 objects from 2 tasks', 'a few seconds'],
  ], [3800, 3500, 2338]),
  P('The most expensive parts are the documentation texts per object and the search for usages; both are controlled by a flag. Reference depth and usage depth are the most effective levers — on a large package it pays to turn them down. For full runs: volume limits at 0, background job, storage on the application server.'),
];

// =====================================================================
// 11 Limits
// =====================================================================
const limits = [
  H1('11  Limits and outlook'),
  LEAD('Whatever the Documizer cannot recreate faithfully, it says so — instead of doing it halfway.'),
  ...table(['Topic', 'State'], [
    ['Customizing content', 'deliberately not written directly — BC sets serve that purpose'],
    ['Smart Forms', 'documented, not created; Adobe Forms both'],
    ['Environment of a Fiori app', 'ICF nodes, MIME objects and gateway registration are documented, not created'],
    ['Authorization default values', 'documented, not transferred (SU22/SU24)'],
    ['IDoc extension types', 'not supported yet; basic types and segments are complete'],
    ['Existing screens', 'are not overwritten — SAP offers no dialog-free way to do it'],
    ['Missing packages', 'are not created automatically; that remains a developer’s decision'],
    ['Comparison in the test run', 'compares source code; a field comparison for DDIC objects is planned'],
    ['Objects deleted at the sender', 'detectable as soon as the start point is in the document header — prepared, not implemented'],
    ['Further formats', 'Markdown, and displaying an XML file without system access, are prepared'],
  ], [3600, 6038]),
];

// =====================================================================
// 12 Source and licence
// =====================================================================
const oss = [
  H1('12  Source, licence and contributing'),
  LEAD('The Documizer is open source. The current version of the three reports and of the full technical specification is public on GitHub.'),
  ...callout('Source', 'github.com/csbg-de/documizer'),
  P('There you will find the sources of the reports `ZDOCUMIZER_IMG`, `ZDOCUMIZER_DEV` and `ZDOCUMIZER_ATC`, the helper report for the report documentation, the specification with every design decision, and this product documentation. Contributions, bug reports and experience from other release levels are welcome.'),
  H2('Licence'),
  ...table(['Item', 'Terms'], [
    ['Licence', 'Apache License 2.0'],
    ['Copyright', '2026 C. Gathmann Computer-System-Beratung GmbH (CSBG), Bremen'],
    ['Use', 'Redistribution and modification permitted, including commercial use'],
    ['Condition', 'The copyright and licence notice is retained'],
    ['Name', '*consiness* and *consiness Documizer* are not licensed parts — the code may be adopted, the name may not be carried on'],
  ], [2600, 7038]),
  P('Because the reports travel into a foreign system by copy and paste and the `LICENSE` file does not come along, the notice sits in the header comment of **every** source. It must not be removed when copying — it is the only place where the origin is still visible in the target system.'),
  ...callout('How it came about', 'Designed, specified and verified against a running system by Christian Gathmann; the code was generated with AI assistance. Every function in this manual has run in a real SAP system before it was described here.'),
];

// =====================================================================
// 13 Contact
// =====================================================================
const contact = [
  H1('13  Contact'),
  LEAD('Would you like to use the Documizer in your system, document an application or transfer development?'),
  new Paragraph({ children: [new TextRun({ text: 'Christian Gathmann', bold: true, size: 28 })], spacing: { before: 240, after: 60 } }),
  new Paragraph({ children: [new TextRun({ text: 'gathmann@csbg.de', size: 24, color: ACC })], spacing: { after: 60 } }),
  new Paragraph({ children: [new TextRun({ text: 'C. Gathmann Computer-System-Beratung GmbH (CSBG), Bremen', size: 22, color: MUTED })], spacing: { after: 240 } }),
  new Paragraph({ children: [new TextRun({ text: 'github.com/csbg-de/documizer', size: 20, color: MUTED })], spacing: { after: 600 } }),
  new Paragraph({ children: [new ImageRun({ type: 'png', data: LOGO, transformation: { width: 150, height: 52 } })] }),
];

// =====================================================================
// Document
// =====================================================================
const header = new Header({ children: [new Paragraph({
  border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: RULE, space: 6 } },
  children: [
    new TextRun({ text: 'Documizer', bold: true, size: 16, color: ACC }),
    new TextRun({ text: '  ·  Product documentation', size: 16, color: GREY }),
    new TextRun({ children: [new PositionalTab({ alignment: PositionalTabAlignment.RIGHT, relativeTo: PositionalTabRelativeTo.MARGIN, leader: PositionalTabLeader.NONE })] }),
    new ImageRun({ type: 'png', data: LOGO, transformation: { width: 68, height: 24 } }),
  ] })] });
const footer = new Footer({ children: [new Paragraph({
  border: { top: { style: BorderStyle.SINGLE, size: 4, color: RULE, space: 6 } },
  children: [
    new TextRun({ text: 'Documizer · Christian Gathmann · gathmann@csbg.de', size: 15, color: GREY }),
    new TextRun({ children: [new PositionalTab({ alignment: PositionalTabAlignment.RIGHT, relativeTo: PositionalTabRelativeTo.MARGIN, leader: PositionalTabLeader.NONE })] }),
    new TextRun({ children: ['Page ', PageNumber.CURRENT], size: 15, color: GREY }),
  ] })] });

const page = { size: { width: 11906, height: 16838 }, margin: { top: 1418, bottom: 1300, left: 1134, right: 1134, header: 600, footer: 560 } };

const doc = new Document({
  creator: 'Christian Gathmann',
  title: 'Documizer – Product Documentation',
  description: 'Documentation, transfer and AI analysis for SAP S/4HANA and SAP ERP',
  styles: {
    default: { document: { run: { font: FONT, size: 21, color: INK } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 40, bold: true, color: ACC, font: FONT },
        paragraph: { spacing: { before: 0, after: 200 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 27, bold: true, color: INK, font: FONT },
        paragraph: { spacing: { before: 320, after: 120 }, outlineLevel: 1, keepNext: true } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 22, bold: true, color: GREY, font: FONT },
        paragraph: { spacing: { before: 240, after: 100 }, outlineLevel: 2, keepNext: true } },
    ],
  },
  numbering: { config: [
    { reference: 'bul', levels: [{ level: 0, format: LevelFormat.BULLET, text: '■', alignment: AlignmentType.LEFT,
      style: { run: { color: ACC, size: 14 }, paragraph: { indent: { left: 400, hanging: 280 } } } }] },
    { reference: 'num', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
      style: { run: { color: ACC, bold: true }, paragraph: { indent: { left: 400, hanging: 340 } } } }] },
  ] },
  sections: [
    { properties: { page }, children: cover },
    { properties: { page }, headers: { default: header }, footers: { default: footer },
      children: [...glance, ...why, ...scen, ...install, ...img, ...bcs, ...dev, ...atc, ...output, ...imp, ...ops, ...limits, ...oss, ...contact] },
  ],
});

Packer.toBuffer(doc).then(buf => { fs.writeFileSync(OUT, buf); console.log('written:', OUT, buf.length, 'bytes'); });
