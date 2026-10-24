// Documizer – Produktdokumentation (Word), consiness-CI
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow,
  TableCell, WidthType, BorderStyle, ShadingType, ImageRun, Header, Footer, PageNumber,
  TableOfContents, LevelFormat, PositionalTab, PositionalTabAlignment,
  PositionalTabRelativeTo, PositionalTabLeader, VerticalAlign, PageBreak,
} = require('docx');

const OUT = process.argv[2];
const LOGO = fs.readFileSync(path.join(__dirname, 'consiness_logo.png'));

const RED = 'D71920', GREY = '808285', INK = '2B2B2B', MUTED = '5F6062';
const FILL = 'F4F4F5', REDFILL = 'FCEDEE', RULE = 'D9D9DB';
const FONT = 'Arial', MONO = 'Consolas';
const W = 9638; // Satzspiegel A4 bei 2 cm Rand

// ---------- Inline-Markup: **fett**, *kursiv*, `code` ----------
function runs(text, base = {}) {
  const out = [];
  for (const part of text.split(/(\*\*[^*]+\*\*|\*[^*\s][^*]*\*|`[^`]+`)/)) {
    if (!part) continue;
    if (part.startsWith('**')) out.push(new TextRun({ ...base, text: part.slice(2, -2), bold: true }));
    else if (part.startsWith('*')) out.push(new TextRun({ ...base, text: part.slice(1, -1), italics: true }));
    else if (part.startsWith('`')) out.push(new TextRun({
      ...base, text: part.slice(1, -1), font: MONO, size: Math.max((base.size || 21) - 2, 15),
      color: base.color === 'FFFFFF' ? 'FFFFFF' : '8C1117',
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

// ---------- Tabelle ----------
function table(headers, rows, widths) {
  const sum = widths.reduce((a, b) => a + b, 0);
  const cell = (t, w, head, alt) => new TableCell({
    width: { size: w, type: WidthType.DXA },
    shading: head ? { type: ShadingType.CLEAR, color: 'auto', fill: RED }
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

// ---------- Nutzen-Kasten ----------
function callout(title, lines) {
  const kids = [new Paragraph({ children: [new TextRun({ text: title, bold: true, color: RED, size: 20 })], spacing: { after: 60 } })];
  for (const l of [].concat(lines)) kids.push(new Paragraph({ children: runs(l, { size: 20 }), spacing: { after: 60, line: 276 } }));
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: [W],
    borders: { top: NOB, bottom: NOB, right: NOB, insideHorizontal: NOB, insideVertical: NOB,
               left: { style: BorderStyle.SINGLE, size: 24, color: RED } },
    rows: [new TableRow({ cantSplit: true, children: [new TableCell({
      width: { size: W, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, color: 'auto', fill: REDFILL },
      margins: { top: 140, bottom: 100, left: 220, right: 220 }, children: kids })] })],
  }), SP(180)];
}

// ---------- Codeblock ----------
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

// ---------- Kennzahlen ----------
function kpis(items) {
  const w = Math.floor(W / items.length);
  const widths = items.map((_, i) => i === items.length - 1 ? W - w * (items.length - 1) : w);
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: widths,
    borders: { ...NOBORDERS, top: { style: BorderStyle.SINGLE, size: 18, color: RED } },
    rows: [new TableRow({ children: items.map(([num, label], i) => new TableCell({
      width: { size: widths[i], type: WidthType.DXA },
      margins: { top: 160, bottom: 80, left: 60, right: 160 },
      children: [
        new Paragraph({ children: [new TextRun({ text: num, bold: true, size: 44, color: RED })], spacing: { after: 40 } }),
        new Paragraph({ children: runs(label, { size: 17, color: MUTED }), spacing: { after: 0, line: 252 } }),
      ] })) })],
  }), SP(240)];
}

// ---------- Karten (drei Reports) ----------
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
      borders: { top: { style: BorderStyle.SINGLE, size: 18, color: RED }, bottom: NOB, left: NOB, right: NOB },
      children: [
        new Paragraph({ children: [new TextRun({ text: rep, font: MONO, size: 16, color: RED })], spacing: { after: 60 } }),
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

// ---------- Szenario ----------
function scenario(title, task, delivers, benefit) {
  return [
    H2(title),
    new Paragraph({ keepNext: true, children: [new TextRun({ text: 'Die Aufgabe', bold: true, color: GREY, size: 18, allCaps: true })], spacing: { after: 60 } }),
    P(task, { para: { keepNext: true } }),
    new Paragraph({ keepNext: true, children: [new TextRun({ text: 'Was der Documizer liefert', bold: true, color: GREY, size: 18, allCaps: true })], spacing: { after: 60 } }),
    ...delivers.map(d => B(d)),
    SP(80),
    ...callout('Ihr Nutzen', benefit),
  ];
}

// =====================================================================
// Deckblatt
// =====================================================================
const cover = [
  new Paragraph({ alignment: AlignmentType.RIGHT, spacing: { after: 2200 },
    children: [new ImageRun({ type: 'png', data: LOGO, transformation: { width: 190, height: 61 } })] }),
  new Paragraph({ children: [new TextRun({ text: 'SAP S/4HANA UND SAP ERP · ON-PREMISE · KLASSISCHES ABAP', size: 18, color: RED, bold: true, characterSpacing: 40 })], spacing: { after: 240 } }),
  new Paragraph({ children: [new TextRun({ text: 'Documizer', bold: true, size: 112, color: INK })], spacing: { after: 120 } }),
  new Paragraph({ children: [new TextRun({ text: 'Dokumentation, Transfer und KI-Analyse', size: 40, color: GREY })], spacing: { after: 40 } }),
  new Paragraph({ children: [new TextRun({ text: 'für SAP-Entwicklungen und Customizing', size: 40, color: GREY })],
    border: { bottom: { style: BorderStyle.SINGLE, size: 24, color: RED, space: 18 } }, spacing: { after: 480 } }),
  new Paragraph({ children: runs('Ein einziger ABAP-Report, in Sekunden installiert. Er dokumentiert, was Ihr System **wirklich** enthält — und bringt es auf Wunsch in ein anderes System. Ohne Transport, ohne abapGit, ohne zusätzliche Repository-Objekte.', { size: 26, color: INK }),
    spacing: { after: 2400, line: 336 } }),
  ...kpis([
    ['3', 'Reports: Customizing, Entwicklung, Prüfkonfiguration'],
    ['1', 'Quelltext je Report — per Copy & Paste in SE38'],
    ['20+', 'Objektarten, die sich übertragen lassen'],
    ['0', 'Transporte, Installationen oder Zusatzobjekte'],
  ]),
  new Paragraph({ spacing: { before: 600, after: 40 }, children: [new TextRun({ text: 'Produktdokumentation · Stand Oktober 2026', size: 18, color: MUTED })] }),
  new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: 'Christian Gathmann · gathmann@csbg.de', size: 18, color: MUTED })] }),
  new Paragraph({ children: [new TextRun({ text: 'C. Gathmann Computer-System-Beratung GmbH (CSBG), Bremen', size: 18, bold: true, color: INK })] }),
];

// =====================================================================
// Auf einen Blick + Inhalt
// =====================================================================
const glance = [
  new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun('Auf einen Blick')] }),
  LEAD('Wer ein SAP-System verantwortet, kennt das Problem: Die Dokumentation beschreibt, was einmal geplant war. Was tatsächlich im System steht, weiß nur das System selbst. Der Documizer fragt es — und macht aus der Antwort ein Dokument, das Menschen lesen, Systeme wieder einlesen und KI-Assistenten auswerten können.'),
  ...cards([
    ['ZDOCUMIZER_IMG', 'Customizing', 'Liest einen Strukturbaum des Einführungsleitfadens, übernimmt SAPs Dokumentation je IMG-Aktivität und liest das Customizing dahinter bis in die Tabelleninhalte. Erzeugt auf Wunsch ein BC-Set.'],
    ['ZDOCUMIZER_DEV', 'Entwicklungen', 'Startet an einem Paket, einem einzelnen Objekt oder einem Transportauftrag — Report, Klasse, Tabelle, CDS, RAP, IDoc, UI5-App, Formular. Liefert Felder, Methoden, Texte, Quelltext, Verwendungen. Und importiert.'],
    ['ZDOCUMIZER_ATC', 'Prüfkonfiguration', 'Dokumentiert ATC- und Code-Inspector-Varianten: welche Checks laufen, mit welcher Priorität, Kundenpriorisierung, Pseudokommentar, Pragma und Ausnahmen.'],
  ]),
  H3('Was den Documizer auszeichnet'),
  B('**Installiert in Sekunden.** Jeder Report ist eine einzige Quelle. Einfügen in SE38, aktivieren, fertig — auch dort, wo nichts installiert und kein Transport eingespielt werden darf.'),
  B('**Ein Format für alles.** Das XML ist vollständig, versioniert und lässt sich verlustfrei wieder einlesen. Das HTML ist in sich geschlossen und öffnet sich auch in Jahren noch ohne Nacharbeit.'),
  B('**Dokumentation, die zurück ins System kann.** Der Development-Report legt aus demselben Dokument Tabellen, Klassen, CDS-Views, RAP-Objekte, IDoc-Typen, UI5-Apps und Adobe-Formulare in einem anderen System an.'),
  B('**Auch ein Transport ist eine Quelle.** Auftragsnummer eintragen, und das Dokument beschreibt genau das, was dieser Transport enthält — mit Quelltext und Verwendungen.'),
  B('**Nicht nur S/4HANA.** Dieselbe Quelle läuft im alten ERP — geprüft bis hinunter zu SAP_BASIS 7.40. Was es dort nicht gibt, sucht der Report dynamisch und lässt es leer, statt abzubrechen.'),
  B('**Nie stillschweigend unvollständig.** Greift eine Mengengrenze, steht das im Dokument. Jeder Lauf kann sich selbst prüfen: serialisieren, einlesen, vergleichen.'),
  B('**Sicher im Kundensystem.** Die Berechtigungsprüfungen von SAP bleiben eingeschaltet. Customizing wird nie direkt geschrieben, sondern als BC-Set zur Prüfung angeboten.'),
  B('**Offen.** Apache-2.0-Lizenz, Quellen auf GitHub — siehe Kapitel 12.'),
  new Paragraph({ children: [new PageBreak()] }),
  new Paragraph({ children: [new TextRun({ text: 'Inhalt', bold: true, size: 36, color: RED })], spacing: { after: 240 } }),
  new TableOfContents('Inhalt', { hyperlink: true, headingStyleRange: '1-1' }),
];

// =====================================================================
// 1 Warum
// =====================================================================
const why = [
  H1('1  Warum Documizer'),
  LEAD('SAP-Systeme wachsen über Jahre. Pakete, Klassen, CDS-Views, Customizing-Einträge — und mit jedem Release driftet die Dokumentation weiter von der Wirklichkeit weg.'),
  H2('Vier Probleme aus dem Projektalltag'),
  ...table(['Problem', 'Was es kostet'], [
    ['**Dokumentation veraltet.** Sie beschreibt den Entwurf, nicht den Stand im System.', 'Einarbeitung dauert Wochen; Fehler werden an der falschen Stelle gesucht.'],
    ['**Kundensysteme sind abgeschottet.** Keine Installation, keine Transporte, abapGit ist keine Option.', 'Werkzeuge, die im eigenen System selbstverständlich sind, stehen beim Kunden nicht zur Verfügung.'],
    ['**Wissen steckt im System.** Wer was verwendet, welche Felder gelesen werden, welche Checks greifen — das steht in Tabellen, nicht in Dokumenten.', 'Auswirkungsanalysen werden geschätzt statt nachgelesen.'],
    ['**KI braucht Kontext.** Ein Assistent hilft nur so gut, wie die Informationen, die er bekommt.', 'Einzelne Code-Schnipsel reichen für Recherche und Fehlersuche selten aus.'],
  ], [4600, 5038]),
  H2('Die Antwort'),
  P('Der Documizer liest direkt aus dem laufenden System — über die Standard-APIs von SAP, wo es sie gibt. Er schreibt dabei nichts, außer wenn Sie ihn ausdrücklich zum Import auffordern. Das Ergebnis ist ein kapitelweise gegliedertes Dokument in zwei Formaten:'),
  B('**XML** — vollständig, versioniert, maschinenlesbar. Das Transportformat für den Import und die ideale Eingabe für KI-Assistenten.'),
  B('**HTML** — eine einzige Datei mit Inhaltsverzeichnis, eingebettetem Stil und ohne JavaScript. Zum Lesen, Weitergeben, Ablegen.'),
  ...callout('Das Prinzip', 'Eine Quelle je Report. Ein Format für Mensch, System und KI. Keine Installation im Zielsystem.'),
];

// =====================================================================
// 2 Einsatzszenarien
// =====================================================================
const scen = [
  H1('2  Sieben Einsatzszenarien'),
  LEAD('Derselbe Report, dieselbe Datei — sieben Aufgaben, für die sonst jeweils ein eigenes Werkzeug nötig wäre.'),
  ...scenario('Entwicklungen dokumentieren',
    'Ein Paket, eine Anwendung oder ein einzelnes Objekt soll vollständig beschrieben werden — für Übergabe, Wartung, Audit oder Einarbeitung neuer Kollegen.',
    ['Kurztexte, Autor und Paket je Objekt, auf Wunsch die Objektdokumentation',
     'Feldlisten von Tabellen, Strukturen, Views und CDS-Views mit Datenelementen und Schlüsseln',
     'Klassen mit Oberklasse, Schnittstellen, Komponenten und lokalen Klassen — auch die Handler eines RAP-Behavior-Pools',
     'Quelltext, Verwendungsnachweis mit Fundstellen und die Objekte, die verwendet werden'],
    'Eine Dokumentation, die dem System entspricht — auf Knopfdruck neu erzeugt, statt mühsam nachgepflegt.'),
  ...scenario('Einen Transport dokumentieren',
    'Was steckt in diesem Auftrag? Vor einer Abnahme, einem Review oder einem Import in die Produktion soll nachlesbar sein, was er tatsächlich verändert.',
    ['Auftragsnummer als Startpunkt — die Wertehilfe zeigt die eigenen Aufträge',
     'Kopf mit Art, Status, Kurztext, Eigentümer, Datum, Zielsystem und den Aufgaben darunter',
     'Jedes Objekt des Auftrags als Kapitel, mit Details, Quelltext und Verwendungen',
     'Customizing-Einträge, Löschungen und fehlende Objekte werden vorweg benannt statt übergangen'],
    'Ein Transport wird lesbar, bevor er ankommt — und mit dem Testlauf des Imports sehen Sie sogar, was er im Zielsystem verändern würde.'),
  ...scenario('IMG-Einstellungen dokumentieren',
    'Das Customizing eines Bereichs oder Projekts soll nachvollziehbar festgehalten werden — mit Erklärung und tatsächlichen Werten.',
    ['Strukturbaum des Einführungsleitfadens mit allen IMG-Aktivitäten',
     'SAPs Standarddokumentation je Aktivität, als lesbarer Text aufbereitet',
     'Die Customizing-Tabellen dahinter mit Feldliste und Inhalt — auf Wunsch nur die kundeneigenen Einträge',
     'Projektstatus und Memo aus einem IMG-Projekt'],
    'Die Customizing-Dokumentation entsteht aus dem System selbst. SAPs Erklärung steht direkt neben Ihren Werten.'),
  ...scenario('Entwicklungen übertragen',
    'Objekte sollen in ein anderes System — etwa aus der Sandbox ins Kundensystem —, wo weder Transporte eingespielt noch abapGit installiert werden können.',
    ['Definitionsdaten im XML: dieselben Strukturen, die SAP beim Lesen liefert und beim Anlegen erwartet',
     'Import von über 20 Objektarten, von der Domäne bis zum Adobe-Formular',
     'Testlauf als Vorbelegung, bestehende Objekte bleiben unangetastet',
     'Objekte einzeln abwählbar oder umbenennbar, Paketregeln alt → neu, Auftrag und Aufgabe automatisch zugeordnet'],
    'Entwicklungen wandern als eine Datei. Das Zielsystem braucht nur den Documizer selbst.'),
  ...scenario('Customizing übertragen per BC-Set',
    'Customizing aus einem System soll in einem anderen nachgezogen werden — kontrolliert und nachvollziehbar.',
    ['Aus dem IMG-Dokument entsteht ein Business Configuration Set',
     'Aktiviert wird in SCPR20: mit Protokoll, Transportauftrag, Vorschau und Weg zurück',
     'Eine Fehlliste nennt die Tabellen, die im Zielsystem noch fehlen — der Development-Report exportiert genau diese'],
    'Kein Report schreibt in Ihre Customizing-Tabellen. Sie entscheiden, was aktiviert wird.'),
  ...scenario('KI-gestützte Analyse',
    'Ein KI-Assistent wie Claude soll bei Recherche, Fehlersuche oder Dokumentation helfen — und braucht dafür den vollständigen Zusammenhang.',
    ['Ein strukturiertes XML mit Quelltexten, Feldlisten, Verwendungen und Customizing in einem Stück',
     'Eindeutige Kapitel und Objektreferenzen, auf die sich Fragen beziehen lassen',
     'Vermerke, wo etwas gekürzt wurde — der Assistent weiß, was er nicht sieht'],
    'Statt einzelne Schnipsel zu kopieren, geben Sie dem Assistenten die ganze Anwendung — und bekommen fundierte Antworten.'),
  ...scenario('Prüfstandards transparent machen',
    'Welche ATC-Checks laufen, mit welcher Priorität, und wie lassen sich Meldungen unterdrücken? Die Antwort steht verteilt in Clustern und Klassen.',
    ['Prüfvarianten mit Kategorien, Checks und allen Meldungen',
     'Priorität der Checkklasse neben der kundeneigenen Priorisierung',
     'Pseudokommentar und Pragma je Meldung, erteilte Ausnahmen'],
    'Code-Standards werden nachlesbar und zwischen Systemen vergleichbar.'),
];

// =====================================================================
// 3 Installation
// =====================================================================
const install = [
  H1('3  Installation in Sekunden'),
  LEAD('Jeder Report ist eine einzige Quelltextdatei. Es gibt nichts zu transportieren und nichts zu konfigurieren.'),
  N('SE38 aufrufen, Programmnamen vergeben (etwa `ZDOCUMIZER_DEV`), **Anlegen** wählen, Typ *Ausführbares Programm*.'),
  N('Quelltext einfügen, sichern, aktivieren.'),
  N('Programmtitel unter *Springen → Attribute* eintragen — das einzige, was von Hand gesetzt wird.'),
  SP(80),
  ...callout('Warum das funktioniert', [
    'Keine globalen Klassen, keine Textelemente, keine eigenen Tabellen, keine Simple Transformation, keine Nachrichtenklasse. Alle Bildschirmtexte stehen im Quelltext — auf Englisch, bei deutscher Anmeldung auf Deutsch.',
    'XML wird über die Kernelklassen `cl_sxml_string_writer` und `cl_sxml_string_reader` geschrieben und gelesen. Sie sind in jedem System vorhanden.']),
  H2('Reportdokumentation im System (optional)'),
  P('Der Hilfsreport `ZDOCUMIZER_DOCU` schreibt die SAP-Reportdokumentation für die drei Reports — sichtbar in SE38 unter *Dokumentation* und über das Info-Symbol des Selektionsbilds. Für die Funktion wird er nicht gebraucht; sinnvoll ist er, wenn im System weitere Kollegen mit dem Documizer arbeiten.'),
  H2('Systemvoraussetzungen'),
  ...table(['Punkt', 'Anforderung'], [
    ['Plattform', 'SAP S/4HANA On-Premise **und** SAP ERP (R/3), klassisches ABAP'],
    ['Release', 'Verifiziert auf SAP_BASIS 758 (S/4HANA 2023). Für ältere Stände umgebaut: POSIX-`REGEX` statt `PCRE`, keine Konstruktoren, die erst ab 7.55 gelten — der IMG-Report läuft nachweislich auf einem Kundensystem mit SAP_BASIS 7.40'],
    ['Berechtigung Dokumentation', 'Lesender Zugriff auf das Repository; für Customizing-Inhalte `S_TABU_NAM`'],
    ['Berechtigung Import', '`S_DEVELOP` für die anzulegenden Objekte und Pakete — die SAP-Prüfungen bleiben eingeschaltet'],
    ['Betrieb', 'Dialog und Hintergrund; im Hintergrund Ablage auf dem Applikationsserver'],
  ], [3000, 6638]),
  ...callout('Auch im alten ERP', 'Neuere Objektarten gibt es in einem älteren System nicht — RAP, CDS, UI5. Der Report sucht sie deshalb dynamisch und läuft auch dort, wo es sie nicht gibt: was fehlt, bleibt leer, statt den Lauf abzubrechen.'),
];

// =====================================================================
// 4 IMG-Report
// =====================================================================
const img = [
  H1('4  Customizing dokumentieren: ZDOCUMIZER_IMG'),
  LEAD('Der IMG-Report liest einen Strukturbaum des Einführungsleitfadens, ordnet jedem Knoten seine IMG-Aktivität zu und geht bis zu den Customizing-Einträgen hinunter.'),
  H2('Was im Dokument steht'),
  ...code([
    '1  <Wurzelknoten>                          Gliederungskapitel',
    '   1.1 <Unterknoten>                       Gliederungskapitel',
    '       1.1.1 <IMG-Aktivität>               Aktivitätskapitel',
    '             ├─ Beschreibung               SAP-Dokumentation, lesbar aufbereitet',
    '             ├─ Technische Zuordnung       Aktivität, Transaktion, Dokuobjekt',
    '             ├─ Projektstatus / Memo       im Projektmodus',
    '             ├─ Objekt je Zuordnung        Feldliste, Auswahlverfahren, Zeilenzahl',
    '             ├─ Customizing-Inhalt         Daten gemäß Mengensteuerung',
    '             ├─ Transport-Historie         Aufträge zur Tabelle',
    '             └─ Verwendete Objekte         Programm hinter der Transaktion',
  ]),
  H2('Selektionsbild'),
  ...table(['Feld', 'Vorbelegung', 'Wirkung'], [
    ['Struktur-ID (GUID) / oder Suchbegriff Wurzel', '', 'Einstieg. Die eigene Wertehilfe zeigt Wurzelknoten mit Text, Knotenzahl und Änderungsdatum — statt 500 nackter GUIDs'],
    ['Projekt (Status/Memo) / nur Projektknoten', '', 'Überlagert den Baum mit einem IMG-Projekt, beschneidet auf dessen Knoten'],
    ['Max. Tiefe / Max. Kapitel', '0 / 300', 'Umfang des Baums; 0 = alle'],
    ['Unterstrukturen auflösen', 'an', 'Entscheidend: ohne dies endet der Lauf nach der ersten Ebene'],
    ['Standarddokumentation / Objektzuordnung', 'an / an', 'SAP-Doku je Aktivität, zugeordnete Customizing-Objekte'],
    ['Customizing-Inhalte lesen', 'an', 'Feldliste und Tabelleninhalte'],
    ['nur kundeneigene Einträge / Max. Zeilen', 'an / 500', 'Mengensteuerung, siehe unten'],
    ['Transport-Historie / Ausgehende Aufrufe', 'aus / aus', 'Aufträge je Tabelle; Programm hinter der Transaktion'],
  ], [3500, 1300, 4838]),
  H2('Nur, was Ihnen gehört'),
  P('Customizing-Tabellen reichen von drei Zeilen bis zu Millionen. Mit *nur kundeneigene Einträge* wirken zwei Verfahren zugleich: der **Namensraum** des ersten Schlüsselfelds (Y, Z, `/`) und das **Vorkommen in Transportaufträgen** zu dieser Tabelle. So werden auch nie transportierte Einträge und Schlüssel außerhalb des Kundennamensraums gefunden.'),
  P('Welches Verfahren gegriffen hat, steht am Objekt — nicht nur im Protokoll. Fehlt die Leseberechtigung, erscheint das Objekt mit Vermerk statt stillschweigend leer.'),
  H2('Projektmodus'),
  P('Ein IMG-Projekt trägt je Aktivität Status, Fortschritt und Memo. Der Report überlagert den Baum damit und kann auf die bearbeiteten Knoten beschneiden. Gliederungskapitel bleiben erhalten, solange darunter ein Projektknoten hängt; die Kapitelnummern behalten ihre Position, Lücken zeigen, was ausgelassen wurde.'),
  ...callout('Gemessen', 'Projektmodus mit 351 Kapiteln: **0,48 Sekunden**. Der Einstieg wird aus den Projektdaten abgeleitet — statt über den ganzen Leitfaden zu laufen.'),
];

// =====================================================================
// 5 BC-Sets
// =====================================================================
const bcs = [
  H1('5  Customizing übertragen: BC-Sets und Fehlliste'),
  LEAD('Die Gegenrichtung des IMG-Reports: aus einem Dokument entsteht im Zielsystem ein Business Configuration Set. Geschrieben wird damit noch nichts.'),
  H2('Warum ein BC-Set und kein Direktzugriff'),
  P('Das Customizing entsteht erst, wenn jemand das Set in **SCPR20** aktiviert. Aktivierung läuft mit Protokoll, mit Transportauftrag, mit Vorschau und mit einem Weg zurück. Ein Report, der direkt in Customizing-Tabellen schreibt, hätte davon nichts.'),
  ...table(['Sperre', 'Grund'], [
    ['Tabelle im Zielsystem unbekannt', 'Ein Set auf eine fehlende Tabelle lässt sich nicht aktivieren'],
    ['Auslieferungsklasse nicht C, G oder E', 'Alles andere ist keine Customizing-Tabelle'],
    ['Inhalt beim Export gekürzt', 'Ein gekürzter Inhalt sähe im Set vollständig aus — beim Aktivieren verschwände der Rest'],
  ], [3800, 5838]),
  H2('Die Fehlliste schließt den Kreis'),
  P('Kundeneigene Customizing-Tabellen gibt es im Zielsystem oft noch nicht — sie sind Entwicklung. Der IMG-Report schreibt deshalb eine **Fehlliste** der übergangenen Objekte. Im Quellsystem liest der Development-Report diese Liste als Startpunkt und exportiert genau diese Objekte. Nach deren Import läuft die BC-Set-Erzeugung auch für sie durch.'),
  ...code([
    'Zielsystem     IMG-Report       BC-Set erzeugen  →  Fehlliste: Z_SKIP_IND, ZV_SKIP_IND',
    'Quellsystem    DEV-Report       Startpunkt AL    →  Export mit Definitionsdaten',
    'Zielsystem     DEV-Report       Import           →  Tabelle und View angelegt',
    'Zielsystem     IMG-Report       BC-Set erzeugen  →  vollständig',
  ]),
  ...callout('Ihr Nutzen', 'Das Zielsystem sagt selbst, was fehlt. Angefordert wird nur, was dort wirklich nicht vorhanden ist.'),
];

// =====================================================================
// 6 Development-Report
// =====================================================================
const dev = [
  H1('6  Entwicklungen dokumentieren: ZDOCUMIZER_DEV'),
  LEAD('Der Einstieg ist ein Paar aus Typ und Name, wie im Object Navigator. Ein Paket ergibt Paket → Objekttyp → Objekt; ein Einzelobjekt ergibt das Objekt, alles was es verwendet, und alle, die es verwenden.'),
  H2('Startpunkte'),
  ...table(['Code', 'Startpunkt', 'Code', 'Startpunkt'], [
    ['`K`', 'Paket (Vorbelegung)', '`SB`', 'Service-Binding'],
    ['`P`', 'Programm / Report', '`IS`', 'IDoc-Segmenttyp'],
    ['`C`', 'Klasse oder Interface', '`IT`', 'IDoc-Basistyp'],
    ['`FF`', 'Funktionsbaustein', '`U5`', 'UI5-Anwendung'],
    ['`F`', 'Funktionsgruppe', '`SF`', 'Smart Form'],
    ['`T`', 'Tabelle / Struktur', '`AF`', 'Adobe Form (Formular)'],
    ['`V`', 'View', '`AI`', 'Adobe Form (Schnittstelle)'],
    ['`D`', 'Datenelement', '`TR`', '**Transportauftrag / Aufgabe**'],
    ['`DO`', 'Domäne', '`AL`', 'Arbeitsliste aus Fehlliste'],
    ['`W`', 'CDS View', '`MX`', 'Metadata Extension'],
    ['`BD`', 'Verhaltensdefinition', '`SD`', 'Service-Definition'],
  ], [900, 3919, 900, 3919]),
  P('Zwei Codes benennen kein Objekt, sondern eine Liste davon: `AL` die Fehlliste aus dem Zielsystem und `TR` einen Transportauftrag. Jedes Objekt der Liste wird ein eigenes Kapitel.'),
  H2('Einen Transportauftrag dokumentieren'),
  P('Mit `TR` steht im Namensfeld eine Auftrags- oder Aufgabennummer; die Wertehilfe zeigt die eigenen Aufträge, die neuesten zuerst. Der Kopf des Laufs nennt Art und Status, Kurztext, Eigentümer, Datum, Zielsystem und die Aufgaben darunter. Drei Eigenheiten des Korrektursystems nimmt der Report Ihnen ab:'),
  B('**Die Objekte hängen an den Aufgaben, nicht am Auftrag.** Die Objektliste eines Auftrags ist regelmäßig leer — transportiert wird, was in den Aufgaben darunter steht. Gelesen werden beide Ebenen.'),
  B('**Teile werden auf ihr Objekt zurückgeführt.** Ein Auftrag führt neben ganzen Objekten auch einzelne Methoden, Includes und Tabellendefinitionen auf. Dokumentiert wird das Objekt, zu dem der Teil gehört, und jedes nur einmal.'),
  B('**Was kein dokumentierbares Objekt ist, wird vorweg genannt:** Customizing-Einträge mit Tabelle und Zahl der Schlüssel samt Verweis auf den IMG-Report, Löschungen, Einträge ohne Katalogobjekt und Objekte, die es im System nicht mehr gibt.'),
  ...callout('Freigegeben oder änderbar', 'Ein freigegebener Auftrag dokumentiert, was drin *war*; ein änderbarer, was gerade drin *ist*. Im zweiten Fall steht das als Hinweis im Kopf — sonst liest sich beides gleich.'),
  H2('Selektionsbild'),
  ...table(['Feld', 'Vorbelegung', 'Wirkung'], [
    ['Unterpakete rekursiv / lokale Pakete einbeziehen', 'an / aus', 'Umfang im Paketmodus'],
    ['Objekttyp / Objektname', '', 'Filter auf die Objektliste'],
    ['Max. Objekte', '2000', 'Die Gesamtzahl bleibt im Dokument vermerkt'],
    ['Objektdokumentation / Details', 'an / an', 'Doku; Felder, Methoden, Textelemente, Festwerte …'],
    ['Quelltext ausgeben / Max. Zeilen je Objekt', 'an / 30000', 'Quelltext; eine Kürzung steht im Kopf des Dokuments'],
    ['Verwendungsnachweis / auch für verwendete Objekte', 'an / an', 'Wer nutzt das Objekt — mit Fundstellen und Feldern'],
    ['Ausgehende Aufrufe / Verweistiefe', 'an / 3', 'Was das Objekt nutzt, und wie tief dem gefolgt wird'],
    ['Verwendungstiefe', '3', 'Gefundene Verwender selbst als Kapitel dokumentieren'],
    ['SAP-Standard ausschließen', 'an', 'Nur Eigenentwicklung in den Verweislisten'],
    ['Definitionsdaten für Reimport', 'aus', 'Technische Definition für den Import — zieht die XML-Ausgabe nach sich'],
  ], [3900, 1300, 4438]),
  H2('Details je Objektart'),
  ...table(['Objektart', 'Im Dokument'], [
    ['Programm', 'Titel, Selektionstexte, Textsymbole, Überschriften, Objektdokumentation'],
    ['Klasse, Interface', 'Oberklasse, Schnittstellen, Komponenten, implementierte Schnittstellenmethoden, lokale Klassen mit Methoden; Quelltext als eine geschlossene Quelle'],
    ['Funktionsbaustein, -gruppe', 'Schnittstelle mit allen Parametern; Bausteinliste'],
    ['Tabelle, Struktur', 'Feldliste mit Datenelement oder eingebautem Typ und Schlüssel'],
    ['View', 'Feldliste, Basistabellen mit Join-Bedingung'],
    ['CDS View', 'Feldliste der Entität, verwendete Objekte, Quelltext'],
    ['Verhaltensdefinition, Service-Definition, Metadata Extension', 'Beschreibung und Quelltext'],
    ['Service-Binding', 'Bindungsart, verknüpfte Service-Definition, Publikationsstand'],
    ['IDoc-Basistyp', 'Segmenthierarchie (WE60), Nachrichtentypen (WE82), verarbeitende Bausteine (WE57)'],
    ['IDoc-Segment', 'Felder mit den Datenelementen, die WE31 zeigt'],
    ['UI5-Anwendung', 'Beschreibung; mit Definitionsdaten alle Dateien samt Verzeichnisbaum'],
    ['Smart Form', 'Knotenbaum, Schnittstelle, globale Definitionen und das Coding der Code-Knoten — gelesen aus dem Objektmodell des Form Builders'],
    ['Adobe Form', 'Formular und seine Schnittstelle als Einheit: Kontext, Felder, Handler-Klasse; mit Definitionsdaten das Layout als Ganzes'],
    ['Datenelement, Domäne', 'Feldbezeichner; Festwerte'],
  ], [3200, 6438]),
  H2('Verweise in beide Richtungen'),
  P('**Ausgehende Aufrufe** zeigen, was ein Objekt verwendet. Weil die Querverweisindizes von SAP jeweils nur einen Teil kennen, liest der Report zusätzlich den Quelltext: `CALL FUNCTION`, `SUBMIT`, Tabellenzugriffe, Includes, Nachrichtenklassen — und sogar Objektnamen in Zeichenliteralen, die zur Laufzeit gebraucht werden. Jeder Treffer wird gegen den Objektkatalog geprüft, bevor er ins Dokument kommt.'),
  P('Der **Verwendungsnachweis** zeigt, wer ein Objekt nutzt: mit Programmart, bei Tabellen mit Zugriffsart lesend oder schreibend, mit Fundstellen samt Zeilennummer — und bei Strukturen mit den Feldern, die an der jeweiligen Stelle angefasst werden. Zu einer Tabelle erscheinen auch die Views und CDS Views, die auf ihr aufsetzen.'),
  ...callout('Aufbau ist nie begrenzt', 'Die Mengengrenzen gelten für Verwendungen — nie für das, woraus ein Objekt besteht. Die Datenelemente einer Tabelle werden immer vollständig gesammelt, sonst ließe sie sich im Zielsystem nicht aktivieren.'),
  H2('SAP-Standard ausschließen'),
  P('Maßstab ist die Auslieferungseinheit des Pakets — dieselbe Linie, die SAP selbst zieht. Sie trifft anders als eine Namensprüfung auf Z und Y auch Kundenobjekte in reservierten Namensräumen und SAP-Objekte, die mit Z beginnen.'),
];

// =====================================================================
// 7 ATC
// =====================================================================
const atc = [
  H1('7  Prüfstandards dokumentieren: ZDOCUMIZER_ATC'),
  LEAD('Die dritte Sicht: nicht was im System steht, sondern woran es gemessen wird.'),
  ...table(['Modus', 'Beantwortet'], [
    ['Prüfvariante (V)', 'Was **wird** geprüft — eine Variante oder alle'],
    ['Katalog (K)', 'Was **könnte** geprüft werden — alle aktivierten Checks'],
  ], [2800, 6838]),
  ...code([
    '1       Prüfvariante     Eigentümer, transportierbar, versteckt',
    '1.1       Kategorie',
    '1.1.1       Check        Meldungen mit Code, Priorität, Kundenpriorität,',
    '                         Pseudokommentar, Pragma, Ausnahmen, Text',
  ]),
  P('Die Checkliste einer Variante steht nicht lesbar in der Datenbank; der Report liest sie über die Code-Inspector-API. Ein Check, den eine Variante nennt, den es aber nach einem Upgrade nicht mehr gibt, bekommt trotzdem ein Kapitel — mit dem Vermerk *nicht ladbar*.'),
  ...callout('Gemessen', 'Standardvariante `DEFAULT`: **17 Checks, 1.198 Meldungen**, Roundtrip identisch.'),
];

// =====================================================================
// 8 Ausgabe
// =====================================================================
const output = [
  H1('8  Ausgabe: XML und HTML'),
  LEAD('Beide Formate entstehen aus demselben Kapitelmodell im selben Lauf.'),
  H2('XML — vollständig, versioniert, wieder einlesbar'),
  ...code([
    '<documizer version="1.1" type="DEV">',
    '  <meta>',
    '    <system>DV1</system> <client>100</client> <language>D</language>',
    '    <truncated>false</truncated> <node_limit>2000</node_limit> <node_total>44</node_total>',
    '  </meta>',
    '  <chapters>',
    '    <chapter id="1.1.1" level="3" type="OBJECT">',
    '      <title>Z_TABLE - Kopfdaten</title>',
    '      <object type="TABL" note="Feldliste"> … </object>',
    '      <source> … </source>',
    '      <definition kind="TABL"> … </definition>',
    '    </chapter>',
    '  </chapters>',
    '</documizer>',
  ]),
  B('**Nie unbemerkt unvollständig.** Jede Kürzung — Objektgrenze, Zeilengrenze, Quelltextgrenze — steht im Kopf und am Datenblock.'),
  B('**Vergleichbar zwischen Systemen.** Benutzer, Zeitstempel und Mandant stehen nur im Kopf, nie in den Kapiteln.'),
  B('**Roundtrip-geprüft.** Auf Wunsch serialisiert der Report, liest wieder ein, serialisiert erneut und vergleicht Zeichen für Zeichen.'),
  B('**Erweiterbar.** Neue Inhalte kommen in neue Elemente; ältere Dokumente bleiben lesbar.'),
  H2('HTML — lesbar, heute und in Jahren'),
  P('Eine einzige Datei mit Inhaltsverzeichnis, nummerierten Kapiteln, Tabellen und Quelltextblöcken; CSS eingebettet, kein JavaScript. SAP-Dokumentation wird von ITF in lesbaren Text mit Zwischenüberschriften umgesetzt. Lange Blöcke stehen eingeklappt hinter einer Zeile mit Bezeichnung und Umfang.'),
  H2('Ablage und Dateiname'),
  ...table(['Ziel', 'Verfügbar', 'Hinweis'], [
    ['Download auf PC', 'Dialog', 'Binär in UTF-8 — Umlaute bleiben erhalten'],
    ['Ablage auf dem Applikationsserver', 'Dialog und Hintergrund', 'Für große Läufe im Hintergrund'],
  ], [3200, 2400, 4038]),
  P('Der Dateiname wird aus System, Startobjekt, Datum und Uhrzeit vorgeschlagen — etwa `documizer_dev_DV1_z_package1_20260922_101500` — und lässt sich frei überschreiben.'),
];

// =====================================================================
// 9 Import
// =====================================================================
const imp = [
  H1('9  Import: Entwicklungen in ein anderes System bringen'),
  LEAD('Ein in System A erzeugtes XML einlesen und die darin definierten Objekte in System B anlegen — mit demselben Report, ohne Transport und ohne abapGit.'),
  H2('Was angelegt wird'),
  ...table(['Objektart', 'Angelegt'], [
    ['Domäne, Datenelement', 'mit Festwerten und Texten'],
    ['Tabelle, Struktur, Sekundärindex', 'mit technischen Einstellungen und Fremdschlüsseln; Indizes nach der Tabelle'],
    ['View, CDS-Quelle', 'mit Basistabellen und Join-Bedingungen; SQL-View entsteht beim Aktivieren'],
    ['Report, Include', 'mit Textelementen und Dokumentation **in allen Sprachen**, GUI-Status'],
    ['Klasse, Interface', 'als quelltextbasierte Fassung, wie SE24 und ADT sie zeigen'],
    ['Funktionsgruppe', 'mit Includes, Bausteinen und deren Schnittstelle'],
    ['Nachrichtenklasse', 'alle Nachrichten in allen gepflegten Sprachen'],
    ['Verhaltensdefinition, Service-Definition, Metadata Extension', 'als Quelltext'],
    ['Service-Binding', 'mit Bindungsart und Services — bewusst unveröffentlicht'],
    ['IDoc-Segmenttyp, IDoc-Basistyp', 'als echtes Segment, mit der ganzen Hierarchie'],
    ['UI5-Anwendung', 'mit allen Dateien und Verzeichnisbaum über die UI5-Repository-API'],
    ['Adobe Form und Schnittstelle', 'aus SAPs eigener Serialisierung wiederhergestellt — derselbe Weg, den das Kopieren im Form Builder nimmt'],
    ['Dynpro, Pflegedialog, Transaktion, View-Cluster', 'der komplette SM30-Apparat, auch Parametertransaktionen'],
  ], [4200, 5438]),
  H2('Sicher von Anfang an'),
  B('**Testlauf ist vorbelegt.** Jeder Schritt meldet, was er täte — geschrieben wird erst, wenn Sie den Haken bewusst herausnehmen.'),
  B('**Bestehendes bleibt.** Ein Objekt, das es schon gibt, wird nur mit *Bestehende Objekte überschreiben* angefasst.'),
  B('**Die richtige Reihenfolge.** Domänen vor Datenelementen vor Tabellen vor Views vor Programmen — der Report sortiert selbst.'),
  B('**Gezielt aktiviert.** Aus den inaktiven Objekten des Benutzers nimmt der Import nur die eigenen; angefangene Arbeit anderer bleibt unberührt.'),
  B('**Geprüft nach dem Lauf.** Aktive Fassung, Syntax-Check für Programme — gemeldet wird, was auffällt.'),
  H2('Sie wählen aus, was kommt'),
  P('Vor dem Import lässt sich eine Liste dazwischenschalten: eine Zeile je Objekt des Dokuments, mit **Zielname**, **Zielpaket** und einer Ankreuzspalte **Übergehen**.'),
  B('**Umbenennen** wirkt auf das ganze Dokument, nicht nur auf den Objektnamen: der neue Name wird wortgenau und unabhängig von Groß- und Kleinschreibung auch im Quelltext ersetzt. Die Wortgrenze verhindert Teiltreffer — `ZKUNDE` lässt `ZKUNDE2` in Ruhe. So lässt sich auch ein SAP-Objekt unter einem Z-Namen hereinholen, ohne das Original zu überschreiben.'),
  B('**Übergehen** nimmt die Zeile ganz aus dem Lauf: weder angelegt noch geändert, auch nicht nachgeprüft. Jede Abwahl steht vorweg im Kopf und noch einmal im Protokoll — ein Weglassen ohne Vermerk wäre eine stillschweigende Lücke.'),
  P('Abhängigkeiten werden dabei nicht erzwungen: wer eine Domäne abwählt, deren Datenelement importiert wird, bekommt den bekannten Aktivierungsfehler. Der Report warnt davor, verbietet es aber nicht — oft ist das abgewählte Objekt im Zielsystem längst vorhanden und soll gerade nicht angefasst werden.'),
  H2('Der Testlauf zeigt, was sich ändern würde'),
  P('Ein Testlauf, der nur *würde geändert* sagt, verschweigt das Wesentliche. Zu jedem Objekt, das es im Zielsystem schon gibt, stellt er deshalb den Quelltext gegenüber:'),
  ...code([
    'CLAS  ZCL_MAILER   Quelltext anders   +12 / -3 Zeilen',
    '        12   DATA lv_a TYPE i.',
    '        13 - lv_a = 1.',
    '        13 + DATA lv_b TYPE i.',
    '        14 + lv_a = 2.',
    '        15   WRITE lv_a.',
    '       ... 240 Zeilen unveraendert',
  ]),
  P('Neue Zeilen grün, entfallende rot, zwei Zeilen Umgebung, unveränderte Strecken zusammengefasst. Den alten Stand liest der Report aus dem Zielsystem in derselben Zusammenstellung, die der Export erzeugt — sonst wären Unterschiede zu sehen, die keine sind. Ist nichts anders, steht *Quelltext gleich* mit der Zeilenzahl.'),
  H2('Pakete, Auftrag und Aufgabe'),
  P('Vier Regelzeilen **alt → neu** lenken Objekte aus dem Quellpaket in ein Zielpaket — etwa `$TMP` → `Z_PACKAGE1`. Der Auftrag hängt am Paket jedes einzelnen Objekts. Fehlt unter dem Auftrag eine offene Aufgabe für Sie, legt der Report sie dialogfrei an; ohne diese Aufgabe würde das Korrektursystem den Import mit einer irreführenden Meldung ablehnen.'),
  H2('Ein Protokoll, das Ursachen nennt'),
  P('Je Objekt steht, was geschehen ist und warum — mit dem echten Rückgabecode und der Meldung des SAP-Bausteins. Scheitert eine Aktivierung, nennt das Protokoll das fehlende Objekt dahinter:'),
  ...code([
    'PROG Z_REPORT_COPY   angelegt                560 Zeilen',
    'TEXT Z_REPORT_COPY   Textelemente gesetzt    D:5 E:8',
    'DOKU Z_REPORT_COPY   Dokumentation gesetzt   Sprachen D',
    'DTEL Z_ACTION        DDIF_DTEL_ACTIVATE rc 8 fehlt oder inaktiv: Domäne Z_ACTION_D',
  ]),
  ...callout('Gemessen: eine RAP-Anwendung als eine Datei', 'Paketlauf mit Quelltext und Definitionsdaten: **34 Definitionen** — 16 CDS-Views, 8 Klassen, 2 Verhaltensdefinitionen, Service-Definition und -Binding, Tabellen, Domäne, Datenelement und 2 UI5-Anwendungen mit **76 Dateien in 12 Ordnern**. Roundtrip identisch.'),
];

// =====================================================================
// 10 Betrieb
// =====================================================================
const ops = [
  H1('10  Sicherheit und Betrieb'),
  H2('Berechtigungen bleiben SAPs Sache'),
  P('Der IMG-Report prüft `S_TABU_NAM` vor jedem Tabellenzugriff; fehlt die Berechtigung, steht das im Dokument. Beim Import prüfen die gerufenen SAP-Bausteine `S_DEVELOP` gegen Objekt und Paket — und diese Prüfung bleibt eingeschaltet. Der Documizer ist damit kein Werkzeug, mit dem jemand Objekte anlegt, die er von Hand nicht anlegen dürfte.'),
  H2('Laufzeiten'),
  ...table(['Lauf', 'Umfang', 'Dauer'], [
    ['IMG, Projektmodus', '351 Kapitel', '0,48 s'],
    ['DEV, Pakethierarchie', '10 Pakete / 352 Objekte', '0,23 s'],
    ['DEV, CDS mit Quelltext', '4 Objekte', '0,08 s'],
    ['DEV, Transportauftrag', '75 Objekte aus 2 Aufgaben', 'wenige Sekunden'],
  ], [3800, 3500, 2338]),
  P('Die teuersten Anteile sind die Dokumentationstexte je Objekt und die Suche nach Verwendungen; beides ist per Kennzeichen steuerbar. Verweistiefe und Verwendungstiefe sind die wirksamsten Stellschrauben — bei einem großen Paket lohnt es, sie zurückzunehmen. Für Vollläufe: Mengengrenzen auf 0, Hintergrundjob, Ablage auf dem Applikationsserver.'),
];

// =====================================================================
// 11 Grenzen
// =====================================================================
const limits = [
  H1('11  Grenzen und Ausblick'),
  LEAD('Was der Documizer nicht originalgetreu anlegen kann, sagt er — statt es halb zu tun.'),
  ...table(['Thema', 'Stand'], [
    ['Customizing-Inhalte', 'bewusst nicht direkt geschrieben — dafür BC-Sets'],
    ['Smart Forms', 'werden dokumentiert, nicht angelegt; Adobe Forms dagegen beides'],
    ['Umgebung einer Fiori-App', 'ICF-Knoten, MIME-Objekte und Gateway-Registrierung werden dokumentiert, nicht angelegt'],
    ['Berechtigungsvorschlagswerte', 'dokumentiert, nicht übertragen (SU22/SU24)'],
    ['IDoc-Erweiterungstypen', 'noch nicht unterstützt; Basistypen und Segmente vollständig'],
    ['Bestehende Dynpros', 'werden nicht überschrieben — SAP bietet dafür keinen dialogfreien Weg'],
    ['Fehlende Pakete', 'werden nicht automatisch angelegt; das bleibt eine Entscheidung des Entwicklers'],
    ['Vergleich im Testlauf', 'vergleicht Quelltext; für DDIC-Objekte ist ein Feldvergleich vorgesehen'],
    ['Gelöschte Objekte beim Sender', 'erkennbar, sobald der Startpunkt im Dokumentkopf steht — vorbereitet, nicht umgesetzt'],
    ['Weitere Formate', 'Markdown und Anzeige einer XML-Datei ohne Systemzugriff sind vorbereitet'],
  ], [3600, 6038]),
];

// =====================================================================
// 12 Bezug und Lizenz
// =====================================================================
const oss = [
  H1('12  Bezug, Lizenz und Mitwirkung'),
  LEAD('Der Documizer ist quelloffen. Die aktuelle Fassung der drei Reports und der vollständigen technischen Spezifikation liegt öffentlich auf GitHub.'),
  ...callout('Quelle', 'github.com/csbg-de/documizer'),
  P('Dort finden Sie die Quelltexte der Reports `ZDOCUMIZER_IMG`, `ZDOCUMIZER_DEV` und `ZDOCUMIZER_ATC`, den Hilfsreport für die Reportdokumentation, die Spezifikation mit allen Entwurfsentscheidungen und diese Produktdokumentation. Beiträge, Fehlermeldungen und Erfahrungsberichte aus anderen Systemständen sind willkommen.'),
  H2('Lizenz'),
  ...table(['Punkt', 'Regelung'], [
    ['Lizenz', 'Apache License 2.0'],
    ['Copyright', '2026 C. Gathmann Computer-System-Beratung GmbH (CSBG), Bremen'],
    ['Nutzung', 'Weitergabe und Änderung erlaubt, auch kommerziell'],
    ['Bedingung', 'Der Copyright- und Lizenzvermerk bleibt erhalten'],
    ['Name', '*consiness* und *consiness Documizer* sind keine lizenzierten Bestandteile — der Code darf übernommen werden, der Name nicht weitergeführt'],
  ], [2600, 7038]),
  P('Weil die Reports per Copy & Paste in ein fremdes System wandern und die Datei `LICENSE` dabei nicht mitkommt, steht der Vermerk im Kopfkommentar **jeder** Quelle. Beim Kopieren darf er nicht entfernt werden — er ist die einzige Stelle, an der die Herkunft im Zielsystem noch erkennbar ist.'),
  ...callout('Entstehung', 'Entworfen, spezifiziert und am laufenden System verifiziert von Christian Gathmann; der Code ist mit KI-Unterstützung entstanden. Jede Funktion dieses Handbuchs ist in einem echten SAP-System gelaufen, bevor sie hier beschrieben wurde.'),
];

// =====================================================================
// 13 Kontakt
// =====================================================================
const contact = [
  H1('13  Kontakt'),
  LEAD('Sie möchten den Documizer in Ihrem System einsetzen, eine Anwendung dokumentieren oder Entwicklungen übertragen?'),
  new Paragraph({ children: [new TextRun({ text: 'Christian Gathmann', bold: true, size: 28 })], spacing: { before: 240, after: 60 } }),
  new Paragraph({ children: [new TextRun({ text: 'gathmann@csbg.de', size: 24, color: RED })], spacing: { after: 60 } }),
  new Paragraph({ children: [new TextRun({ text: 'C. Gathmann Computer-System-Beratung GmbH (CSBG), Bremen', size: 22, color: MUTED })], spacing: { after: 240 } }),
  new Paragraph({ children: [new TextRun({ text: 'github.com/csbg-de/documizer', size: 20, color: MUTED })], spacing: { after: 600 } }),
  new Paragraph({ children: [new ImageRun({ type: 'png', data: LOGO, transformation: { width: 150, height: 48 } })] }),
];

// =====================================================================
// Dokument
// =====================================================================
const header = new Header({ children: [new Paragraph({
  border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: RULE, space: 6 } },
  children: [
    new TextRun({ text: 'Documizer', bold: true, size: 16, color: RED }),
    new TextRun({ text: '  ·  Produktdokumentation', size: 16, color: GREY }),
    new TextRun({ children: [new PositionalTab({ alignment: PositionalTabAlignment.RIGHT, relativeTo: PositionalTabRelativeTo.MARGIN, leader: PositionalTabLeader.NONE })] }),
    new ImageRun({ type: 'png', data: LOGO, transformation: { width: 68, height: 22 } }),
  ] })] });
const footer = new Footer({ children: [new Paragraph({
  border: { top: { style: BorderStyle.SINGLE, size: 4, color: RULE, space: 6 } },
  children: [
    new TextRun({ text: 'Documizer · Christian Gathmann · gathmann@csbg.de', size: 15, color: GREY }),
    new TextRun({ children: [new PositionalTab({ alignment: PositionalTabAlignment.RIGHT, relativeTo: PositionalTabRelativeTo.MARGIN, leader: PositionalTabLeader.NONE })] }),
    new TextRun({ children: ['Seite ', PageNumber.CURRENT], size: 15, color: GREY }),
  ] })] });

const page = { size: { width: 11906, height: 16838 }, margin: { top: 1418, bottom: 1300, left: 1134, right: 1134, header: 600, footer: 560 } };

const doc = new Document({
  creator: 'Christian Gathmann',
  title: 'Documizer – Produktdokumentation',
  description: 'Dokumentation, Transfer und KI-Analyse für SAP S/4HANA und SAP ERP',
  styles: {
    default: { document: { run: { font: FONT, size: 21, color: INK } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 40, bold: true, color: RED, font: FONT },
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
      style: { run: { color: RED, size: 14 }, paragraph: { indent: { left: 400, hanging: 280 } } } }] },
    { reference: 'num', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
      style: { run: { color: RED, bold: true }, paragraph: { indent: { left: 400, hanging: 340 } } } }] },
  ] },
  sections: [
    { properties: { page }, children: cover },
    { properties: { page }, headers: { default: header }, footers: { default: footer },
      children: [...glance, ...why, ...scen, ...install, ...img, ...bcs, ...dev, ...atc, ...output, ...imp, ...ops, ...limits, ...oss, ...contact] },
  ],
});

Packer.toBuffer(doc).then(buf => { fs.writeFileSync(OUT, buf); console.log('geschrieben:', OUT, buf.length, 'Bytes'); });
