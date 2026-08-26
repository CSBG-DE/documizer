# Spezifikation: Documizer — IMG- und Entwicklerdokumentationsreports

**Stand:** 26.08.2026
**Grundlage:** [Recherche](recherche-img-und-entwicklerdoku.md)
**Zielsystem:** S/4HANA On-Premise, SAP_BASIS 758, klassisches ABAP

Dieses Dokument beschreibt den **umgesetzten** Stand. Wo etwas geplant, aber noch nicht gebaut
ist, steht es unter [9. Offene Punkte](#9-offene-punkte).

## 1. Rahmenbedingungen

| Punkt | Entscheidung |
|---|---|
| Deployment | **On-Premise** (kein Public Cloud, `SPRO` verfügbar) |
| Programmiermodell | **Klassisches ABAP** (freier `TADIR`-/DDIC-Zugriff, `DOCU_GET` nutzbar) |
| Reimport | Repository-Objekte legt der DEV-Report selbst an (siehe 5.6); Customizing bleibt bei **BC-Sets** |
| Mengengerüst | Filter und Mengengrenzen als Selektionsparameter; **Vollexport ganzer Tabellen muss möglich sein** |
| Ausgabeformate | **XML** (führend, transportabel) + **HTML** (lesbar) |
| Verteilung | Jeder Report ist **eine einzige Quelle**, per Copy/Paste in SE38 lauffähig |

### 1.1 Phasenschnitt

- **Phase 1** — beide Reports, Export nach XML und HTML. *Erledigt.*
- **Phase 2** — Rückschreiben ins System. *Für Repository-Objekte erledigt, für Customizing
  bewusst nicht vorgesehen.*

Für **Customizing** bleibt es bei der ursprünglichen Abgrenzung: das lösen BC-Sets
(`SCPR3`/`SCPR20`), und sie sind im Fehlerfall belastbarer als eine Eigenentwicklung. Der
Documizer schreibt nicht in Customizing-Tabellen.

Für **Repository-Objekte** hat sich die Abgrenzung verschoben. abapGit setzt eine Installation
im Zielsystem voraus — genau das, was in einem fremden Kundensystem oft nicht geht und weshalb
der Documizer aus einer einzigen Quelle besteht. Der DEV-Report legt die Objekte deshalb selbst
an, aus Definitionsdaten im XML (5.5) über die `DDIF_*_PUT`-Bausteine (5.6). Was er nicht
originalgetreu anlegen kann, sagt er, statt es halb zu tun.

### 1.2 Die Copy/Paste-Bedingung

Beide Reports müssen sich per Zwischenablage in ein beliebiges System bringen lassen. Daraus
folgt alles Weitere in der Architektur:

- **Keine globalen Klassen.** Kapitelmodell, Renderer und Parser liegen als lokale Klassen in
  jedem der beiden Reports — bewusst doppelt.
- **Keine Textelemente.** Alle Bildschirmtexte stehen im Quelltext und werden in
  `INITIALIZATION` in `SELECTION-SCREEN COMMENT`-Felder geschrieben. Textelemente sind ein
  eigener Programmbestandteil und kommen beim Kopieren des Quelltextes nicht mit.
- **Keine eigenen Repository-Objekte.** Keine Z-Tabellen, keine Simple Transformation, keine
  Nachrichtenklasse.

Der Preis ist die Verdopplung des Rahmenwerks. Der Gegenwert ist ein Report, der in einem
fremden System ohne Transport und ohne Nacharbeit läuft.

---

## 2. Architektur

### 2.1 Gemeinsamer Ablauf

Beide Reports haben denselben Ablauf. Nur der Collector unterscheidet sich.

```
Selektionsbild
     │
     ▼
┌──────────────────┐     ┌────────────────────────────┐
│  Collector       │────▶│  Kapitelmodell (generisch)  │
│  IMG | DEV       │     │  lcl_chapter / lcl_object   │
└──────────────────┘     └────────────┬───────────────┘
                                      │
                          ┌───────────┴───────────┐
                          ▼                       ▼
                    XML (sXML)                  HTML
                          │
                          ▼
                    Parser → Modell → XML   (Roundtrip-Selbsttest)
```

Der DEV-Report kann die Kette umkehren. Dann steht am Anfang die Datei und am Ende das
Zielsystem — dazwischen liegt dasselbe Modell:

```
XML-Datei (PC | Appl.-Server)
     │
     ▼
lcl_parser_xml ──▶ Kapitelmodell ──▶ lcl_importer ──▶ DDIC / Repository
                   mit <definition>                    (Testlauf: nur Protokoll)
```

### 2.2 Lokale Klassen je Report

| Klasse / Interface | Aufgabe |
|---|---|
| `lcl_t` | Texte: `t( )` folgt der Ausgabesprache, `ui( )` der Anmeldesprache |
| `lif_docu_collector` | Schnittstelle: `collect` liefert das Dokument |
| `lcl_collector_img` / `lcl_collector_dev` | Der jeweilige Collector |
| `lcl_chapter` | Kapitelknoten (Baum), trägt auch die Definitionsdaten |
| `lcl_object` | Objektblock innerhalb eines Kapitels (Felder, Zeilen, Vermerk) |
| `lcl_document` | Wurzel mit `<meta>` |
| `lif_docu_renderer` | Schnittstelle: `render` liefert den Dateiinhalt |
| `lcl_renderer_xml` | Serialisierung über `cl_sxml_string_writer` |
| `lcl_parser_xml` | Rücklesen über `cl_sxml_string_reader` |
| `lcl_renderer_html` | HTML mit Inhaltsverzeichnis, CSS eingebettet |
| `lcl_cust` (nur IMG) | Auflösung und Lesen des Customizings |
| `lcl_attr` (nur DEV) | DDIC-Struktur ↔ Name/Wert-Paare, per RTTI (siehe 5.5) |
| `lcl_importer` (nur DEV) | Legt die Objekte im Zielsystem an (siehe 5.6) |

**sXML statt Simple Transformation.** Die ursprüngliche Planung sah eine eigene ST vor. Eine ST
ist ein Repository-Objekt und hätte die Copy/Paste-Bedingung gebrochen. `cl_sxml_string_writer`
und `cl_sxml_string_reader` sind Kernelklassen, erzeugen dasselbe lesbare XML und kosten keinen
Transport.

### 2.3 Reports und Pakete

| Report | Inhalt |
|---|---|
| `ZDOCUMIZER_IMG` | IMG-/Customizing-Dokumentation |
| `ZDOCUMIZER_DEV` | ABAP-Paket-/Entwicklerdokumentation |
| `ZDOCUMIZER_CORE_DEMO` | Selbsttest des Kernmodells, Regressionstest |
| `ZDOCUMIZER_DOCU` | erzeugt die SAP-Reportdokumentation der drei anderen |

Pakete im System S4H (Auftrag `S4HK901757`):

| Paket | Inhalt |
|---|---|
| `ZCONS_DOCUMIZER` | Wurzelpaket, Transportschicht `SAP`, Softwarekomponente `HOME` |
| `ZCONS_DOCUMIZER_CORE` | Rahmenwerk, Kapitelmodell, Export |
| `ZCONS_DOCUMIZER_IMG` | IMG- und Customizing-Collector |
| `ZCONS_DOCUMIZER_DEV` | Paket- und Entwicklungs-Collector |

### 2.4 Grundsätze

1. **Standard-APIs bevorzugen.** `STREE_*`, `DOCU_GET`, `CL_PAK_PACKAGE_QUERIES`. Direkte
   Tabellenzugriffe nur dort, wo keine API existiert oder die API zu teuer ist.
2. **Keine systemspezifischen Felder im Export.** Erzeuger, Zeitstempel und Mandant stehen
   ausschließlich in `<meta>`, nie in den Kapiteldaten. Sonst ist ein Vergleich DEV/QAS/PRD
   wertlos. Prinzip von abapGit übernommen.
3. **Zwei Sprachen, zwei Zwecke.** Das Dokument folgt der **Ausgabesprache**, das
   Laufprotokoll am Bildschirm der **Anmeldesprache**. Das Dokument geht an einen Leser, das
   Protokoll bleibt bei dem, der den Report gestartet hat.
4. **Nie stillschweigend unvollständig.** Greift eine Mengengrenze, steht das im Dokument.

### 2.5 Sprachbehandlung

- **Ausgabesprache** (`P_LANGU`, Vorbelegung `sy-langu`) steuert alle Texte im Dokument:
  Überschriften, Spaltentitel, Vermerke und die gelesenen SAP-Texte.
- **Ersatzsprache** (`P_FALB`, `P_FLANG`, Vorbelegung EN) greift, wenn in der Ausgabesprache
  kein Text gepflegt ist. Bei SAP-Standard und oft auch bei Kundenobjekten ist Englisch die
  Pflegesprache; ohne Rückfall bliebe die Zeile leer. Welche Sprache tatsächlich geliefert hat,
  steht am Kapitel (`lang`-Attribut) — sonst wäre nicht erkennbar, warum ein Abschnitt englisch
  ist.
- **Selektionsbild** ist zweisprachig: Englisch als Normalfall, Deutsch nur bei deutscher
  Anmeldesprache.

---

## 3. Report A — IMG-/Customizing-Dokumentation (`ZDOCUMIZER_IMG`)

### 3.1 Selektionsbild

**Block: Auswahl der Struktur**

| Parameter | Bedeutung |
|---|---|
| `P_TREE` | Struktur-ID (GUID), Wertehilfe über die Wurzelknoten mit Text |
| `P_SRCH` | oder Suchbegriff für die Wurzel — listet passende Strukturen mit GUID auf |
| `P_PROJ` | Projekt (Status/Memo), Wertehilfe über `TPROJECT` |
| `P_ONLYPR` | nur Projektknoten |

**Block: Umfang**

| Parameter | Vorbelegung | Bedeutung |
|---|---|---|
| `P_LANGU` | `sy-langu` | Ausgabesprache |
| `P_FALB` / `P_FLANG` | X / EN | Ersatzsprache verwenden |
| `P_DEPTH` | 0 | Maximale Tiefe, 0 = alle |
| `P_MAXNOD` | 300 | Maximale Kapitelzahl, 0 = alle |
| `P_SUBS` | X | Unterstrukturen auflösen |
| `P_DOKU` | X | SAP-Standarddokumentation übernehmen |
| `P_OBJ` | X | Objektzuordnung ermitteln |
| `P_DATA` | | Customizing-Inhalte lesen |
| `P_CUST` | X | nur kundeneigene Einträge |
| `P_MAXROW` | 500 | Maximale Zeilen je Tabelle, 0 = alle |
| `P_HIST` | | Transport-Historie je Objekt |
| `P_CALLS` | | Ausgehende Aufrufe (Quelltext-Scan, siehe 3.6) |
| `P_NOSAP` | | SAP-Standard ausschließen |
| `P_PSTAT` / `P_PMEMO` | X / X | Projektstatus bzw. Projekt-Memo ausgeben |

**Block: Ausgabe**

`P_XML`, `P_HTML`, `P_FOLD` (HTML einklappen ab Zeilen, 0 = nie), `P_RTEST` (Roundtrip prüfen),
`P_DOWN` + `P_PATH` (PC), `P_DSRV` + `P_SRV` (Applikationsserver).

### 3.2 Ablauf

1. **Struktur lesen** — `STREE_HIERARCHY_READ_ALL_SUBS`, nicht `STREE_HIERARCHY_READ`. Im IMG
   sind die Unterkapitel REF-Knoten auf eigenständige Strukturen; ohne Auflösung endet der Lauf
   nach der ersten Ebene und findet keine einzige Aktivität.
2. **Knoten klassifizieren** — Knoten mit Verweis `REF_TYPE = 'COBJ'` in `TNODEIMGR` sind
   Aktivitätskapitel, alle anderen Gliederungskapitel.
3. **Je Aktivität anreichern:**
   - Kopfdaten aus `CUS_IMGACH` (`DOCU_ID`, `TCODE`)
   - Titel aus `TNODEIMGT`, ersatzweise `CUS_IMGACT`
   - Standarddoku über `DOCU_GET` mit **`id = 'HY'`**
   - Objektzuordnung aus `CUS_ACTOBJ`
4. **Customizing-Inhalte lesen** — siehe 3.3.
5. **Projektdaten überlagern** — siehe 3.5.
6. **Kapitelbaum an den Renderer übergeben.**

Die Dokumentationsklasse ist **`HY`**, nicht `SIMG`. `SIMG` ist das Namenspräfix des
Dokuobjekts, nicht die Klasse — eine Verwechslung, die in der Recherche zunächst zu leeren
Ergebnissen geführt hat.

### 3.3 Customizing-Inhalte

`CUS_ACTOBJ-OBJECTTYPE` steuert die Auflösung:

| Typ | Bedeutung | Vorgehen |
|---|---|---|
| `V` | View | auf Basistabellen auflösen (`DD25L`/`DD26S`) |
| `C` | View-Cluster | über `VCLSTRUC` in Views zerlegen, dann wie `V` |
| `T` | Tabelle | direkt lesen |
| `S` | Sicht/Pflegedialog | wie `V` |
| `D` | Dummy | keine Daten, nur die Transaktion |

Views und View-Cluster werden **immer** auf ihre Basistabellen aufgelöst. Ein Pflegeview lässt
sich nicht per `SELECT` lesen, ein Datenbankview schon — die Unterscheidung entfällt, wenn
grundsätzlich aus den transparenten Tabellen gelesen wird.

### 3.4 Mengensteuerung

Customizing-Tabellen reichen von drei Zeilen bis zu Millionen. Dreistufig:

1. **`P_DATA` aus** → nur Struktur, keine Daten. Immer verwendbar.
2. **`P_CUST` = X** → nur kundeneigene Einträge. Zwei Verfahren zugleich, verknüpft mit ODER:
   - **Namensraum** — erstes fachliches Schlüsselfeld beginnt mit Y, Z oder `/`
   - **Transport** — Schlüssel taucht in `E071K` zu dieser Tabelle auf

   Der Namensraum findet auch nie transportiertes Customizing, der Transportweg auch Schlüssel
   außerhalb des Kundennamensraums. **Welches Verfahren gegriffen hat, steht am Objekt**
   (`NAMENSRAUM`, `TRANSPORT`, `NAMENSRAUM+TRANSPORT`, `ALLE`, `GESPERRT`).
3. **`P_MAXROW`** → harte Obergrenze je Tabelle. Wird sie erreicht, steht die Gesamtzeilenzahl
   im Dokument, damit nie der Eindruck von Vollständigkeit entsteht.

Fehlt die Leseberechtigung (`S_TABU_NAM`), erscheint das Objekt mit Vermerk und dem Filter
`GESPERRT` — nicht stillschweigend ausgelassen.

### 3.5 Projektmodus

Ein Projekt-IMG (`P_PROJ`) überlagert die Knoten mit Status und Memo:

- `CUSSTAT` verbindet Projekt und IMG-Knoten über die Status-GUID
- `TSTAHTPR` hält darunter das Memo in fünf Kommentarfeldern
- Status und Memo sind getrennt abschaltbar (`P_PSTAT`, `P_PMEMO`)

Bei `P_ONLYPR` wird der Einstieg **aus den Projektdaten abgeleitet** statt aus dem
Selektionsbild: es wird genau über die Strukturen gelaufen, in denen Projektknoten liegen. Zwei
Fallstricke, beide behoben:

- Die **Unterstrukturauflösung ist im Projektmodus abgeschaltet.** Unter den Projektknoten ist
  auch der Wurzelknoten des Projekts, und dessen Struktur ist der komplette
  Einführungsleitfaden — mit Auflösung liefe der Lauf wieder über den ganzen IMG.
- Die **Kapitelgrenze ist während der Traversierung ausgesetzt.** Projektknoten liegen oft tief
  im Baum; was vorher abgeschnitten wird, kann das Beschneiden hinterher nicht mehr finden.

Gliederungskapitel bleiben erhalten, solange unter ihnen noch ein Projektknoten hängt — sonst
zerfällt der Baum.

### 3.6 Ausgehende Aufrufe

Hinter einer Customizing-Aktivität steht eine Transaktion und dahinter ein Programm. Mit
`P_CALLS` wird dessen Quelltext gescannt und im Dokument vermerkt, was die Aktivität technisch
anfasst: Funktionsbausteine, Tabellenzugriffe, Klassen.

Genommen werden **nur die Transaktionen der zugeordneten Objekte**, nie die auf dem
Aktivitätskopf. Letztere ist bei fast jeder Aktivität eine Parametertransaktion ins
IMG-Rahmenwerk und zöge `SAPLS_CUS_IMG_ACTIVITY` mitsamt `BM_*`, `CTO_*` und `DDIF_*` in jedes
Kapitel. Parametertransaktionen der Objekte werden über `TSTCP` einen Schritt weit verfolgt.

Mit `P_NOSAP` bleiben nur Objekte der Eigenentwicklung übrig (siehe 4.7).

### 3.7 Kapitelaufbau

```
1  <Wurzelknoten>                          Gliederungskapitel
   1.1 <Unterknoten>                       Gliederungskapitel
       1.1.1 <IMG-Aktivität>               Aktivitätskapitel
             ├─ Beschreibung               aus DOCU_GET (Klasse HY), ITF aufgelöst
             ├─ Technische Zuordnung       Aktivität, TCode, Dokuobjekt
             ├─ Projektstatus / Memo       bei Projektmodus
             ├─ Objekt je Zuordnung        Feldliste, Auswahlverfahren, Zeilenzahl
             ├─ Customizing-Inhalt         Daten gemäß Mengensteuerung
             ├─ Transport-Historie         bei P_HIST
             └─ Verwendete Objekte         bei P_CALLS
```

---

## 4. Report B — ABAP-Paket-/Entwicklerdokumentation (`ZDOCUMIZER_DEV`)

### 4.1 Startpunkt

Der Einstieg ist ein Paar aus **Typ und Wert**, wie im Object Navigator:

| Code | Startpunkt | Code | Startpunkt |
|---|---|---|---|
| `K` | Paket (Vorbelegung) | `T` | Tabelle / Struktur |
| `P` | Programm / Report | `V` | View |
| `C` | Klasse / Interface | `D` | Datenelement |
| `FF` | Funktionsbaustein | `DO` | Domäne |
| `F` | Funktionsgruppe | `W` | CDS View |

F4 auf beiden Feldern; der Klartext zum Code steht daneben. Bei `C` entscheidet der Katalog, ob
es eine Klasse oder ein Interface ist — ein Feld für beides, wie in SE80.

Ein **Funktionsbaustein** hat keinen eigenen `TADIR`-Satz und läuft deshalb unter dem
Pseudotyp `FUNC`: Kurztext aus `TFTIT`, Doku über Dokuklasse `FU`, Schnittstelle aus
`FUPARAREF`, Quelltext aus seinem Include.

### 4.2 Selektionsbild

**Block: Startpunkt** — `P_STYPE`, `P_SVAL`, `P_RECUR` (Unterpakete rekursiv, nur Paket),
`P_LOCAL` (lokale Pakete einbeziehen).

**Block: Umfang**

| Parameter | Vorbelegung | Bedeutung |
|---|---|---|
| `S_OBJTYP` / `S_OBJNAM` | | Objekttyp- und Namensfilter |
| `P_LANGU`, `P_FALB`, `P_FLANG` | | Sprache wie in 2.5 |
| `P_MAXOBJ` | 2000 | Maximale Objektzahl, 0 = alle |
| `P_DOKU` | X | Objektdokumentation |
| `P_DETAIL` | X | Details (Felder, Methoden, Textelemente …) |
| `P_SRC` / `P_MAXSRC` | / 300 | Quelltext ausgeben, Zeilen je Objekt |
| `P_USED` | | Verwendungsnachweis |
| `P_CALLS` | | Ausgehende Aufrufe |
| `P_RDEP` | 1 | Verweistiefe, 0 = keine |
| `P_NOSAP` | | SAP-Standard ausschließen |
| `P_MAXUSE` | 50 | Maximale **Verwendungen** je Objekt — greift nicht auf den Aufbau, siehe 4.5 |
| `P_UDEP` | 0 | Verwendungstiefe — dokumentiert die gefundenen Verwender selbst mit |
| `P_MAXHIT` | 40 | Maximale Fundstellen je Stelle |
| `P_FSRC` | | Fundstellen im ganzen Quelltext |
| `P_DEF` | X | Definitionsdaten für den Reimport (siehe 5.5) |

**Block: Ausgabe** — wie Report A.

**Block: Import in dieses System** — schaltet den Report auf die Gegenrichtung (siehe 5.6).
Ist `P_IMP` gesetzt, werden `P_STYPE` und `P_SVAL` inaktiv gesetzt; ein Importlauf hat keinen
Startpunkt. Beide sind deshalb **nicht** `OBLIGATORY` deklariert: die Laufzeit prüft das
Mussfeld im PAI, und zwar bei *jedem* Roundtrip — auch bei dem, der das Importkennzeichen
setzt. Der Benutzer käme sonst nie an das Ankreuzfeld, ohne vorher ein Feld zu füllen, das der
Import gar nicht verwendet. Aus demselben Grund setzt das PBO auch kein `SCREEN-REQUIRED`.
Geprüft wird stattdessen in `AT SELECTION-SCREEN`, und nur wenn der Lauf wirklich startet
(`SY-UCOMM` = `ONLI`, `SJOB`, `PRIN`). Umgekehrt sind die Importfelder
inaktiv, solange dokumentiert wird. `P_IFILE` hat eine Wertehilfe mit Dateidialog — außer bei
`P_ISRV`, denn ein Pfad auf dem Applikationsserver lässt sich vom Frontend nicht durchsuchen.

| Parameter | Vorbelegung | Bedeutung |
|---|---|---|
| `P_IMP` | | Importieren statt dokumentieren |
| `P_IFILE` | | XML-Datei |
| `P_ISRV` | | Datei liegt auf dem Applikationsserver |
| `P_ITEST` | **X** | Testlauf — es wird nichts angelegt |
| `P_IOVER` | | Bestehende Objekte überschreiben |
| `P_IACT` | X | Nach dem Anlegen aktivieren |
| `P_IPACK` | `$TMP` | Zielpaket |
| `P_ITR` | | Auftrag (bei nicht-lokalem Paket) |

### 4.3 Ablauf

**Paketmodus** (`P_STYPE = K`): Pakete über
`CL_PAK_PACKAGE_QUERIES=>GET_ALL_SUBPACKAGES`, Objekte je Paket über
`GET_DEV_OBJECT_TADIR_KEYS`, gruppiert nach Objekttyp.

Beide Methoden arbeiten mit **klassischen Ausnahmen**. Ohne `EXCEPTIONS`-Zusatz im Aufruf führt
jede davon zum Kurzdump — `TRY...CATCH` greift dort nicht. Pakete ohne `TDEVC`- oder
`TADIR`-Satz sind im Bestand durchaus vorhanden; sie erscheinen mit Vermerk im Dokument, statt
den Lauf abzubrechen.

**Einzelobjektmodus** (alle anderen Typen): Kapitel 1 ist das gewählte Objekt. Ist
„Ausgehende Aufrufe" angehakt und die Verweistiefe > 0, folgt in Kapitel 2 alles, was es
verwendet — nach Objekttyp gruppiert und mit denselben Details.

### 4.4 Aufbereitung je Objekttyp

| Typ | Inhalt |
|---|---|
| `PROG` | Titel, **Textelemente** (Titel, Selektionstexte, Textsymbole, Überschriften), Objektdoku, optional Quelltext |
| `CLAS` / `INTF` | Komponenten mit Art (Attribut, Methode, Ereignis, Typ) |
| `FUGR` | Bausteinliste mit Kurztexten |
| `FUNC` | Schnittstelle aus `FUPARAREF` (Import, Export, Changing, Tabellen, Ausnahmen) |
| `TABL` | Feldliste mit Datenelement und Schlüsselkennzeichen |
| `VIEW` | Feldliste **und Basistabellen mit Join** (`DD26S`: Reihenfolge, Fremdschlüssel) |
| `DDLS` | Verwendete Objekte aus `DDLDEPENDENCY` |
| `DTEL` | Feldbezeichner kurz/mittel/lang/Überschrift aus `DD04T` |
| `DOMA` | Festwerte aus `DD07T` |

### 4.5 Ausgehende Aufrufe

Was ein Objekt verwendet, steht in zwei Quellen — und beide sind für sich unvollständig:

| Quelle | Liefert | Lücke |
|---|---|---|
| `WBCROSSGT` | Methodenaufrufe (`ME`), globale Typen (`TY`), Datenobjekte (`DA`) | kennt keine Funktionsbausteine, keinen `SELECT` |
| `CROSS` | klassische Verweise | auf S/4 ohne `SAPRSEUB`-Lauf **leer** |
| Quelltext | `CALL FUNCTION`, `SUBMIT`, Tabellenzugriffe, Klassen, Namen in Literalen | zusammengesetzte Namen nicht auflösbar |

Deshalb wird zusätzlich der **Quelltext gescannt**. Jeder Treffer wird gegen den Katalog
geprüft, bevor er ins Dokument kommt: Bausteine gegen `TFDIR`, Tabellen und Klassen gegen
`TADIR`, je mit einer Abfrage statt einer je Treffer. Lokale Klassen, Arbeitsbereiche und zur
Laufzeit zusammengesetzte Namen fallen damit heraus. Dynamische Zugriffe wie `FROM (lv_tab)`
passen nicht auf das Muster. Kommentare werden vorher abgeschnitten.

**Namen in Zeichenliteralen.** Ein Objekt kann verwendet werden, ohne dass irgendein Verweis
darauf existiert:

```abap
MOVE 'ZBLE_S0211' TO lv_structure_name.   " ALV-Feldkatalog
```

Die Struktur wird zur Laufzeit gebraucht, statisch aber nirgends genannt. Kein Index kennt sie,
und auch der Verwendungsnachweis der Werkbank führt dieses Programm nicht als Verwender. Das
Literal ist die einzige Spur. Der Scan sammelt deshalb jedes Literal, das ein Objektname sein
könnte, und prüft es gegen `TADIR` — was es dort nicht gibt, fällt weg. Ein Literal mit
Leerzeichen passt nicht auf das Muster, gewöhnlicher Text fällt also von selbst heraus.
Gefundene Objekte tragen den Vermerk **„dynamisch verwendet"**.

Das ist eine Vermutung, keine Feststellung — und sie ist der Unterschied zwischen einem
Dokument, das sich importieren lässt, und einem, dem beim Aktivieren ein Objekt fehlt.

**Includes.** `INCLUDE ZBBC_ZAI0003.` ist ein statischer Verweis, steht aber in keinem
Querverweisindex und passt auf keins der Aufrufmuster. Ohne das Include übersetzt das Programm
nicht. Ermittelt wird aus dem **Quelltext**, nicht über `RS_GET_ALL_INCLUDES`: der Baustein
antwortet aus `D010INC`, und die Tabelle wird beim Generieren gefüllt — ein transportiertes,
aber noch nie gelaufenes Programm meldet dort gar keine Includes. `D010INC` führt umgekehrt
auch die generierten Einheiten jeder benutzten Klasse (`CL_…====CU`), die für den Übersetzer
Includes sind und sonst für niemanden. `INCLUDE TYPE` und `INCLUDE STRUCTURE` sind etwas
anderes und werden ausgenommen. Includes sind Aufbau, nicht Verwendung — also keine Grenze.

Beim Filter „SAP-Standard ausschließen" ist ein Include ein Sonderfall: es hat oft **gar keinen
Katalogeintrag**, und dann steht kein Paket zur Verfügung, um zu entscheiden. Es kam aus dem
Quelltext eines Objekts, das bereits im Dokument steht, also gehört es dorthin — was niemand
katalogisiert hat, ist kein SAP-Standard. SAP-eigene Includes haben einen `TADIR`-Eintrag und
werden ganz normal gefiltert.

Die Liste ist nach Art sortiert — Bausteine und Reports, Tabellenzugriffe, Methodenaufrufe,
Typen, Datenobjekte. Greift die Mengengrenze, bleibt oben stehen, was der Leser zuerst sucht.

Querverweise werden **unter dem Include** geführt, nicht unter dem Objektnamen. Für Baustein
(`L<gruppe>U<nn>`) und Funktionsgruppe (`L<gruppe>`) ist das nicht dasselbe.

Die Aufrufliste wird nur für Objekte gezogen, deren Verweise auch verfolgt wurden. Für die
Blätter des Baums wäre sie totes Gewicht und kostet je Objekt einen Scan über `WBCROSSGT`.

**Verwendung ist begrenzt, Aufbau nicht.** `P_MAXUSE` deckelt, wie viele *Verwendungen* je
Objekt gesammelt werden — dort ist die Zahl offen und der Scan teuer. Woraus ein Objekt
*besteht*, wird dagegen vollständig gesammelt: die Datenelemente einer Tabelle, die Domäne
eines Datenelements, die Basisobjekte einer CDS-Quelle. Diese Zahl ist durch das Objekt selbst
begrenzt.

Das war anfangs anders und hat einen Fehler erzeugt, der schwer zu sehen ist: eine Struktur mit
53 verschiedenen Datenelementen gegen eine Grenze von 50 — drei fielen weg, und da ein `SELECT`
ohne `ORDER BY` keine verlässliche Reihenfolge hat, entschied die Datenbank, welche. Im Dokument
stand die Struktur vollständig, nur eines ihrer Datenelemente fehlte. Beim Import ließ sie sich
dann nicht aktivieren.

### 4.6 Verwendungsnachweis

Nur für das **Startobjekt**. Die Frage „wer benutzt das" gilt dem Einstiegspunkt, nicht seiner
Nachbarschaft — ein Datenelement wie `CHAR255` wird in tausenden SAP-Programmen verwendet und
würde das Dokument unter seiner eigenen Verwendungsliste begraben. Im Paketmodus bleibt es beim
Nachweis je Objekt, dort ist jedes Objekt selbst Gegenstand des Dokuments.

Je Treffer steht:

- die **Programmart** aus `TRDIR-SUBC` — Report, Funktionsgruppe, Klassenpool, Modulpool,
  Unterprogrammpool, Typgruppe. Bei einer Funktionsgruppe mit ihrem Namen, der sagt mehr als
  das Rahmenprogramm `SAPL<gruppe>`.
- bei einer Tabelle die **Zugriffsart**: lesend, schreibend oder beides. Der Index weiß nur,
  *dass* die Tabelle vorkommt. Gescannt wird das Include, auf das der Index zeigt, nicht dessen
  Rahmenprogramm — in einer Funktionsgruppe steht das `SELECT` in `LZ..F00`, während
  `SAPL<gruppe>` nur die Includeliste enthält.
- die **Fundstellen** mit Zeilennummer und Anweisung, wie SE11 sie neben seiner Trefferliste
  zeigt. Mit `P_FSRC` stattdessen der komplette Quelltext, die Trefferzeilen darin fett.

Ein Include kann zu **mehreren** Rahmenprogrammen gehören. Nur ein eindeutiges Rahmenprogramm
wird genannt; sonst steht das Include für sich. Eine Vermutung als Tatsache darzustellen wäre
schlechter als keine Angabe.

Zu einer **Tabelle** zeigt der Nachweis zusätzlich die Views und CDS Views, die auf ihr
aufsetzen. Der Querverweisindex weiß davon nichts, das DDIC schon: `DD26S` nennt die
Basistabellen eines Views, `DDLDEPENDENCY` die Objekte hinter einem CDS View.

### 4.7 SAP-Standard ausschließen

Maßstab ist die **Auslieferungseinheit des Pakets** (`TDEVC-DLVUNIT`): `HOME` und `LOCAL` sind
Eigenentwicklung, alles andere wurde ausgeliefert. Das ist die Linie, die SAP selbst zieht, und
sie trifft anders als eine Namensprüfung auf Z/Y auch Kundenobjekte in reservierten
Namensräumen und SAP-Objekte, die mit Z anfangen. Bei einem Funktionsbaustein entscheidet seine
Funktionsgruppe.

Was **keinen Katalogeintrag** hat, gilt als nicht eigen: Konstanten einer Typgruppe wie
`ABAP_TRUE`, Kernel-Typen. Sonst wären genau die das einzige, was in einer gefilterten Liste
übrig bleibt.

Gefiltert wird die Verweisliste, nicht der Gegenstand des Dokuments.

### 4.8 Kapitelaufbau

**Paketmodus**

```
1  Paket <Startpaket>
2  Paket <Unterpaket>
   2.1 Programme
       2.1.1 <Objekt>                       Doku, Details, Aufrufe, Quelltext
   2.2 Klassen
   …
```

**Einzelobjektmodus**

```
1  <Startobjekt>                             Doku, Details, Verwendungsnachweis,
                                             Fundstellen, ausgehende Aufrufe
2  Verwendete Objekte
   2.1 Klassen
   2.2 Datenelemente
   2.3 Funktionsbausteine
   …
```

---

## 5. XML-Format und Roundtrip

### 5.1 Grundsatz

Serialisierung über **sXML** (`cl_sxml_string_writer`), Rücklesen über
`cl_sxml_string_reader`. Beides Kernelklassen, kein Repository-Objekt nötig.

### 5.2 Aufbau

```xml
<documizer version="1.1" type="IMG">
  <meta>
    <system>S4H</system>
    <client>100</client>
    <created_by>GATHMANN</created_by>
    <created_at>2026-08-20 10:00:00</created_at>
    <language>D</language>
    <truncated>false</truncated>
    <node_limit>300</node_limit>
    <node_total>10</node_total>
  </meta>
  <chapters>
    <chapter id="1" level="1" type="STRUCTURE">
      <title>Vorbereitende Aktivitäten</title>
      <chapter id="1.1" level="2" type="ACTIVITY">
        <title>Einstellungen definieren</title>
        <reference activity="FINS_MIG_KNKK_CUST" docu_id="SIMGFINS_MIG_KNKK_CUST"
                   tcode="S_ER9_11000075"/>
        <documentation format="ITF" lang="D">&amp;USE&amp; …</documentation>
        <object type="T" name="T001" tcode="OBDI" note="" rows="42" truncated="false">
          <structure>
            <field name="MANDT" rollname="MANDT" key="X"/>
          </structure>
          <data>
            <row><cell name="MANDT">100</cell></row>
          </data>
        </object>
      </chapter>
    </chapter>
  </chapters>
</documizer>
```

Für `type="DEV"` sind `meta` und `chapters` identisch; unterschiedlich sind die Objektarten
(`CALLS`, `USAGE`, `SOURCE`, `FUNC`, …) und das zusätzliche Element `<definition>` je
Objektkapitel (siehe 5.5).

### 5.3 Regeln

- **Attribut `version`** von Anfang an. Ohne Versionskennzeichen ist eine spätere
  Formatänderung nicht sauber behandelbar.
- **`truncated` und `rows`** an jedem Datenblock. Ein Dokument darf nie unbemerkt unvollständig
  sein.
- **Dokumentation im ITF-Rohformat**, Umsetzung nach HTML erst beim Rendern. So bleibt der
  Reimport verlustfrei.
- **Keine Zeitstempel oder Benutzer in den Kapiteldaten** — ausschließlich in `<meta>`.
- **Erweitern statt ändern.** Ein neues Attribut an einem bestehenden Element bricht jedes
  bisher geschriebene Dokument. Die Fundstellenmarkierung nutzt deshalb das vorhandene
  Feldkennzeichen `key` statt eines eigenen Attributs. Wo eine Erweiterung unvermeidlich war —
  die Definitionsdaten in 5.5 — steht sie in **neuen, eigenen Elementen**, die ein älterer
  Parser überliest, und die Formatversion ist auf 1.1 gegangen.
- **Quelltext gehört in Elemente, nicht in Attribute.** XML normalisiert Zeilenumbrüche
  innerhalb eines Attributwerts zu Leerzeichen. Ein Quelltext im Attribut käme einzeilig
  zurück — ohne Fehlermeldung. Deshalb `<source>`, `<defsource>` und `<src>`.

### 5.4 Roundtrip-Selbsttest

`P_RTEST` rendert das Modell nach XML, liest es zurück, rendert erneut und vergleicht
zeichenweise. Das Ergebnis steht im Protokoll (`IDENTISCH - bestanden` / `ABWEICHUNG`).

Der Test ist die Absicherung des Reimports: geht beim Hin- und Rückweg etwas verloren, fällt es
hier auf und nicht erst im Zielsystem. Jede Formaterweiterung — Definitionsdaten,
Quelltext je Zeile — wurde erst nach einem bestandenen Roundtrip weitergebaut.

Nebenwirkung: das XML wird auch dann erzeugt, wenn `P_XML` aus ist — sonst gäbe es nichts zu
prüfen.

### 5.5 Definitionsdaten

Bis Formatversion 1.0 trug das XML die *Beschreibung* eines Objekts, nicht seine *Definition*.
Eine Feldliste mit Name, Datenelement und Schlüsselkennzeichen liest sich gut, reicht aber
nicht, um eine Tabelle anzulegen: Auslieferungsklasse, Tabellenart, technische Einstellungen
und Fremdschlüssel fehlen, und die Listen sind im Dokument nur durch einen **übersetzten**
Vermerk („Feldliste" / „Field list") unterschieden.

Ab Version 1.1 steht deshalb neben der Beschreibung ein eigenes Element:

```xml
<definition kind="TABL">
  <attr name="TABNAME"  value="ZSCANTEST"/>
  <attr name="TABCLASS" value="TRANSP"/>
  <attr name="CONTFLAG" value="A"/>
  <row tag="DD09V"/>
  <row tag="DD03P">
    <attr name="FIELDNAME" value="MANDT"/>
    <attr name="POSITION"  value="0001"/>
    <attr name="KEYFLAG"   value="X"/>
    <attr name="ROLLNAME"  value="MANDT"/>
  </row>
  <defsource>…</defsource>
</definition>
```

Drei Entscheidungen dahinter:

- **Dieselben Strukturen in beide Richtungen.** Der Export liest, was `DDIF_TABL_GET` liefert,
  der Import gibt es an `DDIF_TABL_PUT` zurück — `DD02V`, `DD09V`, `DD03P`, `DD05M`, `DD08V`,
  `DD35V`, `DD36M`, für Domänen `DD01V`/`DD07V`, für Datenelemente `DD04V`. Eine Feldliste, die
  zwischen zwei Releases auseinanderlaufen könnte, gibt es nicht.
- **Name/Wert statt Struktur je Objekttyp.** Die Struktur wird zur Laufzeit über RTTI
  durchlaufen. Renderer und Parser bleiben ohne Typwissen, ein neuer Objekttyp kostet je eine
  Methode im Sammler und im Importer. Ein Feld, das das Zielrelease nicht kennt, wird beim
  Import übergangen statt zum Abbruch zu führen.
- **Eigener Quelltext.** `<defsource>` steht neben dem Quelltext für den Leser, den `P_MAXSRC`
  gekürzt haben kann. Ein halber Report liest sich noch, einspielen lässt er sich nicht.

Initiale Felder werden weggelassen; der Importer beginnt mit einer initialen Struktur, ein
fehlendes Feld bedeutet also auf beiden Seiten dasselbe.

**`.INCLUDE` auflösen, nicht überspringen.** Der RTTI-Durchlauf nimmt
`get_included_view( )`, nicht `get_components( )`. Letzteres liefert ein `.INCLUDE` als **eine
verschachtelte Komponente**; die Prüfung „nur elementare Felder" wirft sie weg, und alles darin
ist verloren — ohne Meldung, mit weiterhin gezählter Zeile. Die DDIF-Schnittstellenstrukturen
sind flach und haben das nie gezeigt. `DD09V`, die technischen Einstellungen einer Tabelle, hat
dagegen **eine** Komponente gegenüber **21** im aufgelösten Bild: Pufferung, Protokollierung,
Tabellenart, Row/Column Store reisten überhaupt nicht mit. Aufgefallen ist es erst an
`RSMPE_FUNT`, das aus drei Includes und fast nichts sonst besteht und mit lauter leeren Feldern
ankam.

Geschrieben wird das Ganze nur mit `P_DEF` (Vorbelegung an).

### 5.6 Reimport

Der DEV-Report kann **importieren statt dokumentieren** (`P_IMP`): Datei lesen — vom PC oder vom
Applikationsserver —, über denselben Parser ins Modell, dann die Objekte anlegen.

| Objekttyp | Weg | Stand |
|---|---|---|
| Domäne | `DDIF_DOMA_PUT` + `DDIF_DOMA_ACTIVATE` | umgesetzt |
| Datenelement | `DDIF_DTEL_PUT` + `DDIF_DTEL_ACTIVATE` | umgesetzt |
| Tabelle, Struktur | `DDIF_TABL_PUT` + `DDIF_TABL_ACTIVATE` | umgesetzt |
| Sekundärindex | `DDIF_INDX_PUT` + `DDIF_INDX_ACTIVATE` | umgesetzt |
| View | `DDIF_VIEW_PUT` + `DDIF_VIEW_ACTIVATE` | umgesetzt |
| CDS-Quelle | `IF_DD_DDL_HANDLER` (`save`, `write_tadir`, `activate`) | umgesetzt |
| Report, Include | `INSERT REPORT … DIRECTORY ENTRY`, `INSERT TEXTPOOL` | umgesetzt |
| GUI-Status eines Programms | `RS_CUA_INTERNAL_FETCH` / `_WRITE` | umgesetzt |
| Interface, Klasse | `SEO_*_CREATE_COMPLETE` + `IF_OO_CLIF_SOURCE` | umgesetzt |
| Funktionsgruppe, Funktionsbaustein | `RS_FUNCTION_POOL_INSERT`, `RPY_FUNCTIONMODULE_INSERT` | umgesetzt |
| Objektdokumentation | `DOCU_UPDATE` | umgesetzt für Report und Datenelement |

**Views** laufen wie Tabellen: `DDIF_VIEW_GET` liefert `DD25V`, `DD09V`, `DD26V`, `DD27P`,
`DD28J`, `DD28V`, `DD35V` und `DD36M`, `DDIF_VIEW_PUT` nimmt dieselben Strukturen wieder an.

**Sekundärindizes** sind eigene Objekte: `DDIF_TABL_GET` gibt sie als `DD12V`/`DD17V` heraus,
aber `DDIF_TABL_PUT` nimmt sie nicht an — dafür gibt es `DDIF_INDX_PUT`. Sie reisen deshalb
als Zeilen der Tabellendefinition mit und werden angelegt, **nachdem** die Tabelle aktiv ist;
ein Index auf einer Tabelle, die es noch nicht gibt, lässt sich nicht aktivieren. Das Feld
`DBINDEX` bleibt dabei leer: es enthält den Namen auf der Datenbank, der aus dem Tabellennamen
gebildet wird, und würde unverändert übernommen noch die Tabelle des Quellsystems nennen.

**Der GUI-Status** ist ein eigener Programmbestandteil. `INSERT REPORT` trägt den Quelltext und
sonst nichts; Menüs, Funktionstasten, Drucktastenleiste und Titel bleiben zurück. Ein Report,
der seinen eigenen Status setzt, läuft im Zielsystem dann in `CX_SALV_OBJECT_NOT_FOUND` oder
kurz dahinter in einen Abbruch. `RS_CUA_INTERNAL_FETCH` und `_WRITE` sind ein symmetrisches
Paar über elf Tabellen — `STA`, `FUN`, `MEN`, `MTX`, `ACT`, `BUT`, `PFK`, `SET`, `DOC`, `TIT`,
`BIV` — plus den Kopfsatz `RSMPE_ADM`. Jede Tabelle wird ein Zeilen-Tag (`CUA_STA`, `CUA_FUN`,
…), der Kopf `CUA_ADM`; dieselbe Form wie die Feldliste einer Tabelle, dieselbe RTTI-Abbildung.
Ein Programm ohne Status ist der Normalfall und keine Meldung wert.

**Rückgabecodes der Aktivierung.** Die `DDIF_*_ACTIVATE`-Bausteine bewerten ihr Ergebnis: 0 ist
sauber, 4 heißt „aktiviert mit Warnung", ab 8 hat es nicht geklappt. Nur ab 8 bleibt das Objekt
inaktiv. Die 4 als Fehler zu behandeln hieße, den Lauf an einer Tabelle abzubrechen, die
einwandfrei benutzbar ist — und die Folgeschritte, etwa die Indizes, auszulassen.

**CDS-Quellen** haben keinen `DDIF_*`-Baustein. Der einzige Weg führt über
`CL_DD_DDL_HANDLER_FACTORY=>CREATE( )` und läuft in drei Schritten: Quelle sichern, Objekt in
den Katalog hängen, aktivieren. Beim Sichern ist `PUT_STATE = 'N'` zu setzen — die neue, noch
inaktive Fassung; `'M'` ist ein Lesezustand, den der Handler an dieser Stelle ablehnt. Die
Aktivierung erzeugt den SQL-View und das Strukturobjekt von selbst. Der DDL-Text ist ein
String und reist deshalb wie jeder Quelltext als eigenes Element, nicht als Attribut. Das ist
die einzige Stelle, an der der Importer eine SAP-interne Klasse verwendet statt eines
Funktionsbausteins — anders ist eine CDS-Quelle nicht anzulegen.

**Klassen und Interfaces** wandern als **quelltextbasierte Fassung** — der eine Text, den SE24
und ADT zeigen, mit Definition und Implementierung zusammen. Gelesen und geschrieben wird er
über `CL_OO_FACTORY` und `IF_OO_CLIF_SOURCE`. Der Weg über die generierten Includes des
Klassenpools führt nicht zum Ziel: aus ihnen lässt sich keine Klasse rekonstruieren. Der Kopf
(`VSEOCLASS` bzw. `VSEOINTERF`) reist getrennt mit; Autor, Änderungsdatum und **UUID** bleiben
dabei im Quellsystem — die UUID kennzeichnet genau diese eine Klasse, eine Kopie unter anderem
Namen dürfte sie nicht führen.

**Funktionsgruppen** bestehen aus mehr als einem Quelltext, deshalb trägt im XML jede Zeile
ihren eigenen `<src>`: das TOP-Include und alle selbst geschriebenen Includes, dazu je
Funktionsbaustein der Rumpf. Die Includes, die beim Anlegen der Bausteine entstehen
(`L…U01`, `L…UXX`), werden beim Export übergangen — sonst entstünden sie beim Import zweimal.
Die Schnittstelle kommt aus `RPY_FUNCTIONMODULE_READ` in genau den Strukturen, die
`RPY_FUNCTIONMODULE_INSERT` annimmt; da diese kein Feld für den Bausteinnamen haben, bindet
ein zusätzliches Attribut `_FUNC` sie an ihren Baustein.

Ein Detail, das beim Testen auffiel: `RPY_FUNCTIONMODULE_READ` liefert den **ganzen** Include
samt `FUNCTION`-Anweisung, Schnittstellenkommentar und `ENDFUNCTION`, während
`RPY_FUNCTIONMODULE_INSERT` diese drei selbst erzeugt und nur den Rumpf erwartet. Der Importer
schneidet sie deshalb ab; ohne das steht am Ende zweimal `ENDFUNCTION`.

**Aktivierung.** DDIC-Objekte aktivieren ihre eigenen `DDIF_*_ACTIVATE`. Für Klassen und
Funktionsgruppen dient `RS_WORKING_OBJECTS_ACTIVATE` — und zwar mit einer Liste, die der
Importer selbst zusammenstellt: aus den inaktiven Objekten des Benutzers werden nur die
genommen, die zum eben geschriebenen Objekt gehören. Die Liste der inaktiven Objekte enthält
im Regelfall angefangene Arbeit dessen, der den Import startet; sie pauschal zu aktivieren
würde fremde halbfertige Stände scharf schalten.

Der Objektkatalogeintrag entsteht über `TR_TADIR_INTERFACE`; bei einem lokalen Paket (`$*`)
ohne Auftrag, sonst mit dem angegebenen.

**Die Reihenfolge ist festgelegt** — Domänen, dann Datenelemente, dann Tabellen, dann
Programme. Eine Tabelle, deren Datenelemente noch nicht existieren, lässt sich nicht
aktivieren; die Arbeit vorher zu sortieren ist billiger, als sie zu wiederholen.

**Zwei Schutzregeln:**

- `P_ITEST` (Vorbelegung **an**) legt nichts an. Jeder Schritt meldet, was er getan hätte.
  Wer schreiben will, muss den Haken bewusst entfernen.
- Ein vorhandenes Objekt bleibt unangetastet, solange `P_IOVER` nicht gesetzt ist. Ein
  Dokumentationswerkzeug darf keine Tabelle stillschweigend ersetzen.

Das Protokoll nennt je Objekt Typ, Name, was geschehen ist (angelegt, geändert, übersprungen,
Fehler, nicht möglich) und den Grund.

**Prüfung nach dem Lauf.** Angelegt heißt nicht brauchbar. Eine Struktur, der ein Datenelement
fehlt, wird geschrieben und aktiviert dann nicht; ein Programm, das früh geschrieben wurde, kann
von einem später geschriebenen Objekt gebrochen werden. Deshalb geht der Importer am Ende die
Arbeitsliste noch einmal durch und stellt fest, was tatsächlich im System steht:

| Objekttyp | Prüfung |
|---|---|
| Domäne, Datenelement, Tabelle, View | aktive Fassung vorhanden (`AS4LOCAL = 'A'`) |
| CDS-Quelle | `DDLDEPENDENCY` mit `STATE = 'A'` |
| Klasse, Interface | `SEOCLASSDF` mit `VERSION = '1'` |
| Funktionsgruppe | nichts von ihr steht mehr in `DWINACTIV` |
| Report, Include | `SYNTAX-CHECK` — der merkt als einziger, wenn etwas fehlt, das das Programm benutzt |

Gemeldet wird nur, was auffällt; am Ende steht eine Zeile mit der Zahl der geprüften und der
beanstandeten Objekte. Im Testlauf entfällt die Prüfung — es wurde nichts geschrieben.

**Nicht umgesetzt und bewusst nicht:** Customizing-Inhalte. Dafür gibt es BC-Sets; der
Documizer schreibt nicht in Customizing-Tabellen.

---

## 6. HTML-Ausgabe

Eine in sich geschlossene Datei ohne externe Abhängigkeiten: CSS eingebettet, kein JavaScript.
Die Datei soll auch in Jahren noch ohne Nacharbeit zu öffnen sein.

Enthalten sind Inhaltsverzeichnis mit Sprungmarken (zwei Ebenen — sonst wird das Verzeichnis
länger als das Dokument), nummerierte Kapitel, Datentabellen, Quelltext in Codeblöcken.

**Große Blöcke einklappen.** Ein Quelltext von 2000 Zeilen oder eine Tabelle mit 800 Einträgen
schiebt alles Übrige aus dem Blick. Blöcke oberhalb der Schwelle `P_FOLD` (Vorbelegung 100)
stehen deshalb in `<details>` mit einer Kopfzeile aus Bezeichnung und Umfang — zugeklappt, per
Klick aufzuklappen. `<details>` ist gewöhnliches HTML; das Dokument bleibt ohne JavaScript, und
ein Anzeigeprogramm, das das Element nicht kennt, zeigt den Inhalt einfach ausgeklappt.
`P_FOLD = 0` schaltet das Einklappen ab.

**ITF-Umsetzung.** Die Dokumentation kommt als ITF. Abschnittsmarken wie `&DEFINITION&`,
`&USE&` oder `&EXAMPLE&` werden zu Zwischenüberschriften, Auszeichnungen (`<ZH>`, `<LS>`,
`<DS:…>`) zu Fettdruck. Die Auszeichnung wird je Zeile ausgeglichen — im ITF laufen Marken über
Zeilengrenzen, und ohne Ausgleich färbt eine offene Marke den Rest des Dokuments ein.

**Ablage.** Wahlweise Download auf den PC (`P_DOWN`) oder Ablage auf dem Applikationsserver
(`P_DSRV`). Im Hintergrundbetrieb steht der Frontend-Download nicht zur Verfügung; dort ist der
Applikationsserver der einzige Weg. Geschrieben wird in beiden Fällen binär in UTF-8 — ein
Textdownload würde die Zeichen in die Frontend-Codepage umsetzen, und genau dort gehen Umlaute
verloren.

Markdown ist noch nicht umgesetzt (siehe 9).

---

## 7. Berechtigungen und Betrieb

- Berechtigungsprüfung `S_TABU_NAM` je gelesener Customizing-Tabelle. Nicht lesbare Tabellen
  erscheinen mit Vermerk, nicht stillschweigend ausgelassen.
- Größere Läufe im Hintergrund, Ablage dann auf dem Applikationsserver.
- Anwendungsprotokoll (`BAL`) ist **noch nicht umgesetzt** (siehe 9); das Laufprotokoll steht
  bisher nur in der Liste.

### 7.1 Berechtigungen beim Import

Der Import ist die einzige Stelle, an der der Documizer schreibt. Die gerufenen APIs prüfen
`S_DEVELOP` gegen Objekt und Paket, und **diese Prüfung bleibt eingeschaltet**: `AUTH_CHK`
bzw. `AUTHORITY_CHECK` steht überall auf `X`. Fehlen die Rechte, weigert sich der Baustein,
und der Lauf schreibt die Ablehnung ins Protokoll.

Das ist bewusst so und nicht der bequemste Weg. Die Prüfung abzuschalten wäre eine Zeile und
würde den Report zu einem Werkzeug machen, mit dem jemand Repository-Objekte anlegt, die er
von Hand nicht anlegen dürfte.

Was der Report **nicht** tut: eine eigene Prüfung vor dem Lauf. Wer keine Rechte hat, erfährt
das objektweise aus dem Protokoll statt einmal vorab (siehe 9).

### 7.2 Laufzeit

Zwei Stellen kosten spürbar und sind entsprechend gedeckelt:

- **`LIKE`-Scans über `WBCROSSGT`.** Für die Richtung „was verwendet dieses Objekt" gibt es
  keinen Index. Deshalb ist „Ausgehende Aufrufe" per Vorbelegung aus, und die Aufrufliste wird
  nur für Objekte gezogen, deren Verweise auch verfolgt wurden.
- **Quelltextlesen.** Je Objekt ein `READ REPORT`, im Verwendungsnachweis je Fundstelle eines.
  `P_MAXUSE` und `P_MAXHIT` begrenzen die Zahl.

Namensauflösungen gegen `TADIR` laufen gebündelt, nicht mit einem `SELECT SINGLE` je Verweis.

---

## 8. Umsetzungsstand

| Schritt | Inhalt | Stand |
|---|---|---|
| 1 | Kapitelmodell, Schnittstellen | erledigt |
| 2 | XML-Renderer, Parser, Roundtrip | erledigt |
| 3 | IMG-Collector ohne Dateninhalte | erledigt |
| 4 | Customizing-Inhalte inkl. Mengensteuerung | erledigt |
| 5 | Paket-Collector, Objekttypen | erledigt |
| 6 | HTML-Renderer | erledigt |
| 6a | Projektmodus (Status, Memo) | erledigt |
| 6b | Sprachsteuerung, Ersatzsprache, zweisprachiges Bild | erledigt |
| 6c | Startpunkt wählbar, Verweistiefe | erledigt |
| 6d | Verwendungsnachweis, ausgehende Aufrufe, Quelltext-Scan | erledigt |
| 6e | SAP-Standard-Filter | erledigt |
| 6f | Große Blöcke im HTML einklappbar (`P_FOLD`) | erledigt |
| 7 | Definitionsdaten im XML, Formatversion 1.1 | erledigt |
| 7a | Reimport: Domänen, Datenelemente, Tabellen, Reports | erledigt |
| 7b | Reimport: Klassen, Interfaces, Funktionsgruppen | erledigt |
| 7c | Reimport: Views, CDS-Quellen | erledigt |
| 7d | Reimport: Sekundärindizes | erledigt |
| 8 | Markdown-Renderer | offen |
| 9 | Anzeigen ohne Anlegen | offen |
| 10 | BAL-Protokoll, `S_DEVELOP` | offen |

## 9. Offene Punkte

1. **Markdown-Ausgabe** — geplant war ATX-Überschriften, Pipe-Tabellen, Codefences mit
   Sprachkennzeichen `abap`. Bisher nur XML und HTML.
2. **Anzeigen ohne Anlegen** — eine XML-Datei nur einlesen und nach HTML rendern, ohne
   Systemzugriff. Parser und Renderer sind da, es fehlt der Schalter.
3. **BAL-Anwendungsprotokoll** — gelesene Knoten/Objekte, übersprungene wegen Berechtigung,
   abgeschnittene Tabellen, Laufzeit.
4. **`S_DEVELOP` vorab prüfen** — beim Import prüfen die gerufenen APIs selbst (siehe 7.1),
   aber erst je Objekt. Eine Prüfung vor dem Lauf würde einen aussichtslosen Import gar nicht
   erst starten.
5. **Funktionsbausteine im Verwendungsnachweis** — für die Richtung „welcher Baustein wird von
   wem gerufen" gibt es keinen Index; ein Quelltext-Scan über alle Programme wäre zu teuer.
6. **Mandantenabhängiges Customizing** — der Export bezieht sich auf den Anmeldemandanten.
   Mandantenübergreifendes Customizing ist noch nicht gesondert gekennzeichnet.
7. **Dokumentationsobjekte im Transport** — die von `ZDOCUMIZER_DOCU` erzeugte
   Reportdokumentation liegt nicht im Transportauftrag.
