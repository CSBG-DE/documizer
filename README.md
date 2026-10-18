# Documizer

Two ABAP reports that generate documentation from an on-premise SAP S/4HANA system:

- **`ZDOCUMIZER_IMG`** — structure tree of the Implementation Guide, assignment of the IMG
  activities, adoption of the SAP standard documentation, reading of the associated Customizing
  down to table contents. Optionally with project status and memo from an IMG project.
- **`ZDOCUMIZER_DEV`** — entry point at a package or a single object (report, class, function
  module, table, view, CDS view, data element, domain). Short texts, field lists, components,
  text elements, source code, where-used list and the objects used.

Both share the chapter model and the XML roundtrip: the export can be read back in. Each report
is a single source and can be moved into any system by copy/paste in SE38 — no text elements, no
additional objects.

Output as **HTML** for reading (a single file, CSS embedded, no JavaScript; large blocks are
collapsed) and as **XML** for further processing.

## Import: the reverse direction

`ZDOCUMIZER_DEV` can read an XML generated in system A and **create** the objects defined in it
in system B:

| Object type | Scope |
|---|---|
| Domain, data element | with fixed values and texts |
| Table, structure | technical settings, foreign keys, search helps, secondary indexes |
| View | base tables, fields, join conditions |
| CDS source | SQL view and structure object arise on their own upon activation |
| Report, include | program attributes, text elements, documentation |
| Interface, class | as a source-code-based version |
| Function group | includes, modules, their interface and body |

**Test run is the default** — the report reports what it would create, and creates nothing.
Existing objects remain untouched as long as "overwrite" is not set. The `S_DEVELOP` check of the
called SAP modules stays enabled.

Documizer deliberately does not write Customizing contents back — that is what BC Sets are for.
See [Reimport](docs/spezifikation-documizer.md#56-reimport).

## Documents

| File | Content |
|---|---|
| [docs/documentation-en.html](docs/documentation-en.html) | Operation and background, for users |
| [docs/spezifikation-documizer.md](docs/spezifikation-documizer.md) | Functional and technical specification, state as implemented |
| [docs/recherche-img-und-entwicklerdoku.md](docs/recherche-img-und-entwicklerdoku.md) | Market research and the IMG data model verified against S/4HANA |

## Sources

| File | Content |
|---|---|
| [abap/zdocumizer_img.prog.abap](abap/zdocumizer_img.prog.abap) | IMG / Customizing report |
| [abap/zdocumizer_dev.prog.abap](abap/zdocumizer_dev.prog.abap) | Package / developer report |
| [abap/zdocumizer_core_demo.prog.abap](abap/zdocumizer_core_demo.prog.abap) | Self-test of the core model |
| [abap/zdocumizer_docu.prog.abap](abap/zdocumizer_docu.prog.abap) | generates the SAP report documentation |

## Status

Both reports run and are verified against the system S4H (SAP_BASIS 758, S/4HANA 2023) — export
as well as import, each object type with its own pass from creation through export and renaming
to creation in the target.

XML format version 1.1. Storage on the PC or on the application server.

Open items are Markdown as a third format, displaying an XML file without system access, the BAL
log and an `S_DEVELOP` check before the run — see
[Open items](docs/spezifikation-documizer.md#9-offene-punkte).

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
Copyright 2026 C. Gathmann Computer-System-Beratung GmbH (CSBG).

Author: Christian Gathmann. Designed, specified and validated by Christian Gathmann;
code generated with AI assistance.

Current version: https://github.com/csbg-de/documizer — when redistributing, please refer to
this repository.

Redistribution and modification are permitted, including commercial use. The condition is that
the copyright and license notice is retained. Because the reports travel into a foreign system by
copy/paste and the `LICENSE` does not come along, the notice is in the header comment of every
source — it must not be removed when copying.

The name "consiness" or "consiness Documizer" is not covered by the license: the code may be
adopted, the name may not be carried on.
