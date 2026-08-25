# Documizer

Zwei ABAP-Reports zur Dokumentationserzeugung aus einem SAP S/4HANA On-Premise-System:

- **`ZDOCUMIZER_IMG`** — Strukturbaum des Einführungsleitfadens, Zuordnung der IMG-Aktivitäten,
  Übernahme der SAP-Standarddokumentation, Auslesen des zugehörigen Customizings bis auf
  Tabelleninhalte. Optional mit Projektstatus und -memo aus einem IMG-Projekt.
- **`ZDOCUMIZER_DEV`** — Einstieg an einem Paket oder an einem einzelnen Objekt (Report, Klasse,
  Funktionsbaustein, Tabelle, View, CDS View, Datenelement, Domäne). Kurztexte, Feldlisten,
  Komponenten, Textelemente, Quelltext, Verwendungsnachweis und die verwendeten Objekte.

Gemeinsam ist beiden das Kapitelmodell und der XML-Roundtrip: der Export ist wieder einlesbar.
Jeder Report ist eine einzige Quelle und lässt sich per Copy/Paste in SE38 in ein beliebiges
System bringen — ohne Textelemente, ohne Zusatzobjekte.

Ausgabe als **HTML** zum Lesen (eine Datei, CSS eingebettet, kein JavaScript; große Blöcke
stehen eingeklappt) und als **XML** zur Weiterverarbeitung.

## Import: die Gegenrichtung

`ZDOCUMIZER_DEV` kann ein in System A erzeugtes XML einlesen und die darin definierten Objekte
in System B **anlegen**:

| Objekttyp | Umfang |
|---|---|
| Domäne, Datenelement | mit Festwerten und Texten |
| Tabelle, Struktur | technische Einstellungen, Fremdschlüssel, Suchhilfen, Sekundärindizes |
| View | Basistabellen, Felder, Join-Bedingungen |
| CDS-Quelle | SQL-View und Strukturobjekt entstehen beim Aktivieren von selbst |
| Report, Include | Programmattribute, Textelemente, Dokumentation |
| Interface, Klasse | als quelltextbasierte Fassung |
| Funktionsgruppe | Includes, Bausteine, deren Schnittstelle und Rumpf |

**Testlauf ist Vorbelegung** — der Report meldet, was er anlegen würde, und legt nichts an.
Vorhandene Objekte bleiben unangetastet, solange „überschreiben" nicht gesetzt ist. Die
`S_DEVELOP`-Prüfung der gerufenen SAP-Bausteine bleibt eingeschaltet.

Customizing-Inhalte schreibt der Documizer bewusst nicht zurück — dafür gibt es BC-Sets.
Siehe [Reimport](docs/spezifikation-documizer.md#56-reimport).

## Dokumente

| Datei | Inhalt |
|---|---|
| [docs/dokumentation.html](docs/dokumentation.html) | Bedienung und Hintergrund, für Anwender |
| [docs/spezifikation-documizer.md](docs/spezifikation-documizer.md) | Fachliche und technische Spezifikation, umgesetzter Stand |
| [docs/recherche-img-und-entwicklerdoku.md](docs/recherche-img-und-entwicklerdoku.md) | Marktrecherche und das gegen S/4HANA verifizierte IMG-Datenmodell |

## Quellen

| Datei | Inhalt |
|---|---|
| [abap/zdocumizer_img.prog.abap](abap/zdocumizer_img.prog.abap) | IMG-/Customizing-Report |
| [abap/zdocumizer_dev.prog.abap](abap/zdocumizer_dev.prog.abap) | Paket-/Entwicklerreport |
| [abap/zdocumizer_core_demo.prog.abap](abap/zdocumizer_core_demo.prog.abap) | Selbsttest des Kernmodells |
| [abap/zdocumizer_docu.prog.abap](abap/zdocumizer_docu.prog.abap) | erzeugt die SAP-Reportdokumentation |

## Stand

Beide Reports laufen und sind gegen das System S4H (SAP_BASIS 758, S/4HANA 2023) verifiziert —
Export wie Import, je Objekttyp mit einem eigenen Durchlauf von der Erzeugung über den Export
und das Umbenennen bis zum Anlegen im Ziel.

XML-Formatversion 1.1. Ablage auf PC oder Applikationsserver.

Offen sind Markdown als drittes Format, das Anzeigen einer XML-Datei ohne Systemzugriff, das
BAL-Protokoll und eine `S_DEVELOP`-Prüfung vor dem Lauf — siehe
[Offene Punkte](docs/spezifikation-documizer.md#9-offene-punkte).

## Lizenz

Apache License 2.0 — siehe [LICENSE](LICENSE) und [NOTICE](NOTICE).
Copyright 2026 consiness GmbH.

Weitergabe und Änderung sind erlaubt, auch im kommerziellen Einsatz. Bedingung ist, dass der
Copyright- und Lizenzhinweis erhalten bleibt. Weil die Reports per Copy/Paste in ein fremdes
System wandern und die `LICENSE` dabei nicht mitkommt, steht der Hinweis im Kopfkommentar jeder
Quelle — er darf beim Kopieren nicht entfernt werden.

Der Name „consiness" ist von der Lizenz nicht erfasst: der Code darf übernommen werden, der
Name nicht weitergeführt.
