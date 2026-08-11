# Recherche: IMG-/Customizing-Dokumentation und ABAP-Entwicklerdokumentation

**Stand:** 11.08.2026
**Zielsystem der Verifikation:** S4H, SAP_BASIS 758 (S/4HANA 2023), Kernel 793, HANA, Mandant 100, On-Premise

## 1. Zweck und Vorgehen

Vor der Spezifikation zweier Reports — einem IMG-/Customizing-Dokumentationsreport und einem
ABAP-Paket-/Entwicklerdokumentationsreport — war zu klären, was es dafür bereits gibt: im
SAP-Standard, als Open Source und als kommerzielles Werkzeug.

Die Recherche lief in zwei Stufen:

1. **Marktrecherche** (Web) nach vorhandenen Werkzeugen und Ansätzen.
2. **Verifikation gegen das Zielsystem** per RFC-Tabellenzugriff und ADT. Alle in Kapitel 3
   genannten Tabellen, Feldnamen, Funktionsbausteine und Beispielwerte stammen aus dem laufenden
   System S4H, nicht aus Dokumentation oder Erinnerung.

Stufe 2 hat einen wesentlichen Irrtum der ersten Fassung korrigiert (Dokumentenklasse, siehe 3.5)
und die zentrale Verknüpfung IMG-Knoten → Customizing gefunden, die in der Literatur meist
unerwähnt bleibt (`TNODEIMGR`, siehe 3.3).

---

## 2. Teil A — IMG/Customizing: Ausgangslage

### 2.1 Was es an fertigen Werkzeugen gibt

| Werkzeug | Art | Deckt ab | Lücke |
|---|---|---|---|
| **BC-Sets** (`SCPR3`/`SCPR20`) | SAP-Standard | Customizing auslesen **und wieder einspielen** | Keine Kapitelstruktur, keine Dokumentation, kein lesbares Dokument |
| **Projektdokumentation** (`SPRO_ADMIN`) | SAP-Standard | Eigene Notizen je IMG-Aktivität, Statusverwaltung | Erfasst nur selbst gepflegte Texte, nicht die Standarddoku, kein Export |
| **CUSTTOOL** / `ZREP_CUST_DOC` | Open Source (MIT) | Customizing-Doku aus Transportaufträgen nach Word | Transport- statt IMG-basiert, kein XML, max. 10 Spalten je Eintrag |
| **Docu Performer** (bluetelligence) | Kommerziell | Dokumentationsgenerierung, Schwerpunkt BW/Analytics | Keine IMG-Kapitelstruktur, kostenpflichtig |

Angaben zu CUSTTOOL und Docu Performer stammen aus der Marktrecherche und sind nicht im Zielsystem
verifiziert.

### 2.2 Bewertung

Kein Werkzeug deckt die geforderte Kette ab: *Bereichsauswahl → zugehöriges Customizing auslesen →
IMG-Knoten zuordnen → SAP-Standarddoku übernehmen → kapitelweise aufbauen → transportabler,
reimportierbarer Export*.

Besonders auffällig: **den XML-Roundtrip (Export, später wieder importierbar) bietet keines der
Werkzeuge.** BC-Sets kommen dem am nächsten, arbeiten aber auf Datenebene ohne Dokumentation und
ohne Gliederung.

---

## 3. Teil A — Das verifizierte IMG-Datenmodell

Das ist der eigentliche Ertrag der Recherche. Die Kette wurde an einem realen Beispiel
(IMG-Aktivität `SIMG_CFMENUORFBOBDI`) lückenlos durchgemessen.

### 3.1 Hierarchieablage

Der IMG ist eine Struktur des STREE-Frameworks (allgemeines Hierarchie-Werkzeug):

| Tabelle | Inhalt |
|---|---|
| `TTREE` | Strukturkopf, Schlüssel `ID` (32-stellige GUID), Feld `TYPE` = Strukturtyp |
| `TNODEIMG` | **Knoten** der IMG-Strukturen: `TREE_ID`, `NODE_ID`, `PARENT_ID`, `BROTHER_ID`, `NODE_TYPE` |
| `TNODEIMGT` | Sprachabhängige **Knotentexte** (`SPRAS`, `TREE_ID`, `NODE_ID`, `TEXT`) |
| `TNODEIMGR` | **Verweise vom Knoten auf Objekte** — siehe 3.3 |

Relevante Strukturtypen (aus `TTREETYPE`, alle mit Knotentabelle `TNODEIMG`, Transportobjekt `SIMH`):

- `IMG` — Referenz-IMG
- `BMIMG` — IMG-Struktur im Business-Modell-Kontext
- `CUSPR`, `CUSPV` — Projekt-IMG bzw. Projektsicht

Erlaubte Knotentypen für Strukturtyp `IMG` (aus `TTREETYPEN`): `IMG`, `IMG0`, `IMG1`.
`IMG1` ist der Aktivitätsknoten.

Wichtig: Die Hierarchie ist über `PARENT_ID`/`BROTHER_ID` als **verkettete Liste** abgelegt, nicht
über Sequenznummern. Die Geschwisterreihenfolge ergibt sich aus der `BROTHER_ID`-Kette — beim
Auslesen muss diese Kette verfolgt werden, sonst stimmt die Kapitelreihenfolge nicht.

### 3.2 Lese-API

Verifiziert vorhanden (Funktionsgruppen `SAPLSHI1`, `SAPLSHI2`, `SAPLSHI12`, `SAPLSHI23`):

| Funktionsbaustein | Zweck |
|---|---|
| `STREE_HIERARCHY_READ` | Struktur komplett lesen. Import `STRUCTURE_ID` (`TTREE-ID`), `LANGUAGE`, `READ_ALSO_TEXTS`; Tabellen `LIST_OF_NODES` (`HIER_IFACE`), `LIST_OF_TEXTS` (`HIER_TEXTS`), `LIST_OF_REFERENCES` (`HIER_REF`) |
| `STREE_HIERARCHY_READ_ALL_SUBS` | Struktur inkl. aller Unterstrukturen |
| `STREE_STRUCTURE_READ_ALL_NODES` | Alle Knoten einer Struktur |
| `STREE_STRUCTURE_READ_N_LEVEL` | Nur n Ebenen tief — für Vorschau/Bereichsauswahl |
| `STREE_READ_REFERENCES_GENER` | Knotenverweise lesen |
| `STREE_READ_MULT_NODE_TEXTS` | Knotentexte mehrsprachig |

**Achtung:** Die Rückgabestruktur `HIER_IFACE` enthält ausschließlich Strukturinformationen
(GUIDs, Ebene, Gültigkeit, Flags) — **kein** Feld für die IMG-Aktivität. Die fachliche Zuordnung
kommt erst über `LIST_OF_REFERENCES` bzw. `TNODEIMGR`. Dieser Punkt kostet erfahrungsgemäß Zeit,
wenn man ihn nicht kennt.

### 3.3 Knoten → Customizing: `TNODEIMGR`

Das ist die zentrale Verknüpfung für die Anforderung „Auslesen des zugehörigen Customizings".

| Feld | Bedeutung |
|---|---|
| `NODE_ID` | Knoten-GUID (Schlüssel) |
| `REF_TYPE` | Verweistyp, für Customizing-Objekte `COBJ` |
| `REF_OBJECT` | Referenziertes Objekt = **IMG-Aktivität** (C70) |
| `IN_SCOPE` | Kennzeichen Projekt-Scope |
| `DEFAULTREF` | Standardverweis |

Verifizierte Beispielwerte: `REF_TYPE = 'COBJ'` mit `REF_OBJECT` = `SIMG_CFMENUORFBOBDI`,
`APOC_C_FORMV`, `_CACS_V_COMB_CASSGN`.

### 3.4 IMG-Aktivität → Customizing-Objekt

| Tabelle | Inhalt |
|---|---|
| `CUS_IMGACH` | Kopfsatz der IMG-Aktivität: `ACTIVITY`, `DOCU_ID`, `TCODE`, `ATTRIBUTES` |
| `CUS_ACTOBJ` | Aktivität → Objekt: `ACT_ID`, `OBJECTTYPE` (z. B. `V` = View), `OBJECTNAME`, `TCODE`, `IMG_POS` |
| `CUS_IMGACT` | Sprachabhängiger Titel der Aktivität (`SPRAS`, `ACTIVITY`, `TEXT`) |

Offizielle API statt Direktzugriff (Funktionsgruppe `S_CUS_IMG_ACTIVITY`, verifiziert):
`S_CUS_IMG_ACTIVITY_READ`, `S_CUS_IMG_ACTIVITY_READ_MULTIP`, `S_CUS_IMG_ACTIVITY_GET_OBJECTS`,
`S_CUS_IMG_ACTIVITY_GET_W_TCODE`, `S_CUS_IMG_ACT_GET_DESC`, `S_CUS_IMG_ACTIVITY_QUERY`.

### 3.5 Standarddokumentation — Korrektur

Die IMG-Dokumentation liegt in `DOKHL`/`DOKTL` unter **Dokumentenklasse `HY`**, nicht unter `SIMG`.

Das Feld `DOKHL-ID` ist nur zwei Zeichen lang (`C(2)`) — eine Klasse `SIMG` kann es dort gar nicht
geben. `SIMG` ist der **Präfix des Dokumentationsobjekts**, nicht die Klasse:

```
CUS_IMGACH-DOCU_ID = 'SIMG' + ACTIVITY
```

Aufruf entsprechend:

```abap
CALL FUNCTION 'DOCU_GET'
  EXPORTING id     = 'HY'
            langu  = sy-langu
            object = ls_imgach-docu_id.   " z. B. 'SIMGSIMG_CFMENUORFBOBDI'
```

Die erste Fassung dieser Recherche nannte hier `SIMG` als Dokuklasse. Das war falsch und hätte in
der Umsetzung zu leeren Dokumentationstexten geführt.

### 3.6 Durchgemessenes Beispiel

```
IMG-Knoten (TNODEIMG.NODE_ID = 005056B254401ED388BEACDCE45F9B9B)
  └─ TNODEIMGR:  REF_TYPE = 'COBJ', REF_OBJECT = 'SIMG_CFMENUORFBOBDI'
       └─ CUS_IMGACH:  ACTIVITY   = 'SIMG_CFMENUORFBOBDI'
                       DOCU_ID    = 'SIMGSIMG_CFMENUORFBOBDI'
                       TCODE      = 'S_E4A_94000040'
            ├─ DOKHL:      ID = 'HY', LANGU = D und E, TYP = 'E'  → DOCU_GET
            ├─ CUS_ACTOBJ: OBJECTTYPE = 'V', OBJECTNAME = 'V_T007Z', TCODE = 'OBDI'
            │                → View V_T007Z → Basistabelle T007Z → Customizing-Daten
            └─ CUS_IMGACT: sprachabhängiger Titel
```

Damit ist die vollständige Kette *Kapitelknoten → Aktivität → Standarddoku → Customizing-Tabelle*
belegt.

### 3.7 Bereichsauswahl und Filter

Für die Anforderung „Auswahl relevanter Bereiche/Anteile" stehen zur Verfügung:

- **Teilbaum**: Startknoten wählen, ab dort rekursiv (`PARENT_ID`/`BROTHER_ID`)
- **Projekt-IMG**: Strukturtypen `CUSPR`/`CUSPV`, Scope-Kennzeichen `TNODEIMGR-IN_SCOPE`,
  zusätzlich `CUS_IMGACH_SCOPE`
- **Ausprägungsfilter des IMG** — im STREE als Ein-/Ausschlusstabellen abgelegt:
  `TTREECOUIN`/`TTREECOUEX` (Länder), `TTREEBRAIN`/`TTREEBRAEX` (Branchen),
  `TTREERELIN`/`TTREERELEX` (Releases), `TTREESUBIN`/`TTREESUBEX`, `TTREEROLIN`/`TTREEROLEX`
- **Status**: `VSTATIMG` (`REF_OBJECT`, `STATUS_ID`, `PROJECT`, `NODE_ID`)

---

## 4. Teil B — ABAP-Paket/Development

### 4.1 Was es an fertigen Werkzeugen gibt

| Werkzeug | Art | Deckt ab | Lücke |
|---|---|---|---|
| **abapGit** | Open Source (MIT) | Serialisiert jedes Repository-Objekt nach XML, systemunabhängig | Quelltext-Transport, keine gegliederte Dokumentation |
| **SAP abap-file-formats** | SAP, offiziell | Nachfolgeformat, JSON-basiert | Ebenfalls Serialisierung, keine Doku |
| **abapDoc** (kctdata) | Open Source (**GPL v3**) | 12 Objekttypen nach DOCX | Kein CDS, Stand SAP_BASIS 7.00, Lizenz für uns unbrauchbar |
| **SE80/ADT-Bordmittel** | SAP-Standard | Anzeige, keine Dokumentgenerierung | — |

**Lizenzhinweis:** abapDoc steht unter GPL v3. Der Code darf nicht übernommen werden, wenn das
Ergebnis nicht selbst unter GPL v3 stehen soll. Als funktionale Messlatte ist das Projekt trotzdem
brauchbar.

### 4.2 Verifizierte Bausteine im Zielsystem

**Rekursive Paketanalyse** — `CL_PAK_PACKAGE_QUERIES` (Paket `SPAK_API`) ist vorhanden, geprüfte
Methoden:

```
GET_ALL_SUBPACKAGES        " rekursiv, komplette Unterbaumermittlung — kein Eigenbau nötig
GET_DIRECT_SUBPACKAGES
GET_SUPERPACKAGES
GET_ROOT_PACKAGE
GET_PACKAGE_ATTRIBUTES
GET_MULTI_PACKAGE_ATTRIBUTES
GET_DEV_OBJECT_TADIR_KEYS  " Objekte eines Pakets
GET_SUB_TREE
GET_PACKAGE_HIERARCHY_DATA
```

Alternativ steht ab S/4HANA 2020 die **XCO Library** (`xco_cp_abap_repository`) zur Verfügung,
ABAP-Cloud-fähig. Für klassisches ABAP On-Premise ist `CL_PAK_PACKAGE_QUERIES` der direktere Weg.

**Objektermittlung:** `TADIR` (`PGMID`, `OBJECT`, `OBJ_NAME`, `DEVCLASS`), Pakethierarchie über
`TDEVC-PARENTCL`.

**Dokumentation:** `DOCU_GET` für klassische Objektdokumentation, ABAP Doc (`"!`) für Klassen und
Interfaces.

Im Zielsystem existiert eine geeignete Testhierarchie: `ZCONS_TRAINEE_INSIGHT` mit den Unterpaketen
`ZCONS_TI_APPS`, `ZCONS_TI_BACKEND`, `ZCONS_TI_GW_SERVICES` und deren Unterpaketen — mehrstufig,
also gut geeignet, um die Rekursion zu prüfen.

### 4.3 Bewertung

Rekursion und Serialisierung sind gelöste Probleme. Was fehlt, ist dasselbe wie auf der IMG-Seite:
die **gegliederte, dokumentationsorientierte Aufbereitung** und der Roundtrip.

Für das XML-Format ist abapGit die beste Vorlage — es serialisiert bewusst ohne systemspezifische
Felder (Benutzer, Zeitstempel, Transportkennzeichen), damit die Dateien zwischen Systemen
vergleichbar bleiben. Dieses Prinzip sollte übernommen werden.

---

## 5. Gemeinsames Fazit

Beide Bereiche zeigen dasselbe Bild: Die **Leseschnittstellen sind vollständig vorhanden und
stabil**, teils seit Release 4.6. Was fehlt, ist die Schicht darüber — Auswahl, Gliederung,
Anreicherung mit Dokumentation, Export in ein wiedereinlesbares Format.

Daraus folgt für die Umsetzung:

1. **Ein gemeinsames Rahmenwerk für beide Reports.** Der Ablauf ist identisch:
   Selektion → rekursiv sammeln → mit Doku anreichern → Kapitelmodell → Export.
   Unterschiedlich sind nur die Collector-Implementierungen.

2. **Standard-APIs statt Direktselektion.** Die Tabellen sind hier dokumentiert, damit das Modell
   nachvollziehbar ist — im Code sollten `STREE_*`, `S_CUS_IMG_ACTIVITY_*` und
   `CL_PAK_PACKAGE_QUERIES` verwendet werden. Sie sind releasestabiler als die Tabellen.

3. **XML über eine eigene Simple Transformation**, nicht über `id`-Serialisierung. Die
   `id`-Variante bricht bei jeder Strukturänderung den Reimport und erzeugt unlesbares XML.

4. **Systemspezifische Felder aus dem Export heraushalten** (abapGit-Prinzip), sonst ist der
   Vergleich zwischen Systemen wertlos.

## 6. Verifikationsprotokoll

Gegen S4H (SAP_BASIS 758) geprüft und bestätigt:

- `TTREE`, `TTREETYPE`, `TTREETYPEN`, `TNODEIMG`, `TNODEIMGT`, `TNODEIMGR`, `TDOKUIMG`, `VSTATIMG`
- `CUS_IMGACH`, `CUS_ACTOBJ`, `CUS_IMGACT`, `CUS_IMGACH_SCOPE`
- `DOKHL` inkl. Dokumentenklasse `HY` und Objektnamensbildung
- `STREE_HIERARCHY_READ` samt Schnittstelle (`FUPARAREF`), Struktur `HIER_IFACE` (53 Felder)
- Funktionsgruppe `S_CUS_IMG_ACTIVITY` mit 40+ Bausteinen
- `CL_PAK_PACKAGE_QUERIES` inkl. `GET_ALL_SUBPACKAGES`
- `TADIR`, `TDEVC`

Nicht im System verifiziert (Marktrecherche): CUSTTOOL, Docu Performer, abapDoc, abap-file-formats.
