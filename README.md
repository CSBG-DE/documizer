# Documizer

Zwei ABAP-Reports zur Dokumentationserzeugung aus einem SAP S/4HANA On-Premise-System:

- **IMG-/Customizing-Dokumentationsreport** — Bereichsauswahl im Einführungsleitfaden, Auslesen des
  zugehörigen Customizings, Übernahme der SAP-Standarddokumentation, kapitelweiser Aufbau,
  Export nach XML sowie HTML/Markdown.
- **ABAP-Paket-/Entwicklerdokumentationsreport** — rekursive Analyse eines Startpakets und seiner
  Unterpakete, Aufbereitung der enthaltenen Entwicklungsobjekte, gleicher Exportweg.

Gemeinsam ist beiden das Kapitelmodell und der XML-Roundtrip: Der Export ist später wieder
einlesbar.

## Dokumente

| Datei | Inhalt |
|---|---|
| [docs/recherche-img-und-entwicklerdoku.md](docs/recherche-img-und-entwicklerdoku.md) | Marktrecherche und das gegen S/4HANA verifizierte IMG-Datenmodell |
| [docs/spezifikation-documizer.md](docs/spezifikation-documizer.md) | Fachliche und technische Spezifikation beider Reports |

## Stand

Konzeptphase — noch kein ABAP-Code. Die Spezifikation ist gegen das System S4H
(SAP_BASIS 758, S/4HANA 2023) verifiziert.
