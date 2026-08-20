# Spezifikation: Documizer — IMG- und Entwicklerdokumentationsreports

**Stand:** 20.08.2026
**Grundlage:** [Recherche](recherche-img-und-entwicklerdoku.md)
**Zielsystem:** S/4HANA On-Premise, SAP_BASIS 758, klassisches ABAP

Dieses Dokument beschreibt den **umgesetzten** Stand. Wo etwas geplant, aber noch nicht gebaut
ist, steht es unter [9. Offene Punkte](#9-offene-punkte).

## 1. Rahmenbedingungen

| Punkt | Entscheidung |
|---|---|
| Deployment | **On-Premise** (kein Public Cloud, `SPRO` verfügbar) |
| Programmiermodell | **Klassisches ABAP** (freier `TADIR`-/DDIC-Zugriff, `DOCU_GET` nutzbar) |
| Reimport | **Phase 2**; Rückschreiben über **BC-Sets** (Customizing) und **abapGit** (Repository-Objekte) statt Eigenbau |
| Mengengerüst | Filter und Mengengrenzen als Selektionsparameter; **Vollexport ganzer Tabellen muss möglich sein** |
| Ausgabeformate | **XML** (führend, transportabel) + **HTML** (lesbar) |
| Verteilung | Jeder Report ist **eine einzige Quelle**, per Copy/Paste in SE38 lauffähig |

### 1.1 Phasenschnitt

- **Phase 1** — beide Reports, Export nach XML und HTML, Reimport nur als *Anzeige/Rendern*.
- **Phase 2** — Rückschreiben ins System: Customizing über BC-Sets (`SCPR3`/`SCPR20`),
  Repository-Objekte über abapGit.

Diese Aufteilung vermeidet Doppelentwicklung: BC-Sets und abapGit lösen das Zurückschreiben
bereits vollständig und sind im Fehlerfall belastbarer als eine Eigenentwicklung.

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
┌──────────────────┐     ┌───────────────────────────┐
│  Collector       │────▶│  Kapitelmodell (generisch) │
│  IMG | DEV       │     │  lcl_chapter / lcl_object  │
└──────────────────┘     └────────────┬──────────────┘
                                      │
                          ┌───────────┴───────────┐
                          ▼                       ▼
                    XML (sXML)                  HTML
                          │
                          ▼
                    Parser → Modell → XML   (Roundtrip-Selbsttest)
```

### 2.2 Lokale Klassen je Report

| Klasse / Interface | Aufgabe |
|---|---|
| `lcl_t` | Texte: `t( )` folgt der Ausgabesprache, `ui( )` der Anmeldesprache |
| `lif_docu_collector` | Schnittstelle: `collect` liefert das Dokument |
| `lcl_collector_img` / `lcl_collector_dev` | Der jeweilige Collector |
| `lcl_chapter` | Kapitelknoten (Baum) |
| `lcl_object` | Objektblock innerhalb eines Kapitels (Felder, Zeilen, Vermerk) |
| `lcl_document` | Wurzel mit `<meta>` |
| `lif_docu_renderer` | Schnittstelle: `render` liefert den Dateiinhalt |
| `lcl_renderer_xml` | Serialisierung über `cl_sxml_string_writer` |
| `lcl_parser_xml` | Rücklesen über `cl_sxml_string_reader` |
| `lcl_renderer_html` | HTML mit Inhaltsverzeichnis, CSS eingebettet |
| `lcl_cust` (nur IMG) | Auflösung und Lesen des Customizings |

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
| `P_MAXUSE` | 50 | Maximale Verwendungen je Objekt |
| `P_MAXHIT` | 40 | Maximale Fundstellen je Stelle |
| `P_FSRC` | | Fundstellen im ganzen Quelltext |

**Block: Ausgabe** — wie Report A.

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
| Quelltext | `CALL FUNCTION`, `SUBMIT`, Tabellenzugriffe, Klassen | Laufzeitnamen nicht auflösbar |

Deshalb wird zusätzlich der **Quelltext gescannt**. Jeder Treffer wird gegen den Katalog
geprüft, bevor er ins Dokument kommt: Bausteine gegen `TFDIR`, Tabellen und Klassen gegen
`TADIR`, je mit einer Abfrage statt einer je Treffer. Lokale Klassen, Arbeitsbereiche und zur
Laufzeit zusammengesetzte Namen fallen damit heraus. Dynamische Zugriffe wie `FROM (lv_tab)`
passen nicht auf das Muster. Kommentare werden vorher abgeschnitten.

Die Liste ist nach Art sortiert — Bausteine und Reports, Tabellenzugriffe, Methodenaufrufe,
Typen, Datenobjekte. Greift die Mengengrenze, bleibt oben stehen, was der Leser zuerst sucht.

Querverweise werden **unter dem Include** geführt, nicht unter dem Objektnamen. Für Baustein
(`L<gruppe>U<nn>`) und Funktionsgruppe (`L<gruppe>`) ist das nicht dasselbe.

Die Aufrufliste wird nur für Objekte gezogen, deren Verweise auch verfolgt wurden. Für die
Blätter des Baums wäre sie totes Gewicht und kostet je Objekt einen Scan über `WBCROSSGT`.

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
<documizer version="1.0" type="IMG">
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

Für `type="DEV"` sind `meta` und `chapters` identisch; unterschiedlich sind nur die Objektarten
(`CALLS`, `USAGE`, `SOURCE`, `FUNC`, …).

### 5.3 Regeln

- **Attribut `version`** von Anfang an. Ohne Versionskennzeichen ist eine spätere
  Formatänderung nicht sauber behandelbar.
- **`truncated` und `rows`** an jedem Datenblock. Ein Dokument darf nie unbemerkt unvollständig
  sein.
- **Dokumentation im ITF-Rohformat**, Umsetzung nach HTML erst beim Rendern. So bleibt der
  Reimport verlustfrei.
- **Keine Zeitstempel oder Benutzer in den Kapiteldaten** — ausschließlich in `<meta>`.
- **Modellerweiterungen nur innerhalb des bestehenden Schemas.** Die Fundstellenmarkierung
  nutzt deshalb das vorhandene Feldkennzeichen `key`; ein neues Attribut hätte jedes bisher
  geschriebene Dokument gebrochen.

### 5.4 Roundtrip-Selbsttest

`P_RTEST` rendert das Modell nach XML, liest es zurück, rendert erneut und vergleicht
zeichenweise. Das Ergebnis steht im Protokoll (`IDENTISCH - bestanden` / `ABWEICHUNG`).

Der Test ist die Absicherung für Phase 2: geht beim Hin- und Rückweg etwas verloren, fällt es
hier auf und nicht erst beim Zurückspielen. Er ist auch der Grund, warum Modellerweiterungen
mit dem bestehenden Schema auskommen müssen.

Nebenwirkung: das XML wird auch dann erzeugt, wenn `P_XML` aus ist — sonst gäbe es nichts zu
prüfen.

### 5.5 Reimport

**Phase 1** (offen) — XML zurück ins Modell lesen und nach HTML rendern, ohne Systemzugriff.
Der Parser dafür existiert bereits; es fehlt nur der Report.

**Phase 2** (offen) — Customizing über BC-Sets, Repository-Objekte über abapGit. Der Documizer
schreibt nicht selbst in Customizing-Tabellen oder ins Repository. Diese Abgrenzung hält ihn
auf der Leseseite und damit risikoarm.

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
- `S_DEVELOP` für den Entwicklerreport ist **noch nicht geprüft** (siehe 9).
- Größere Läufe im Hintergrund, Ablage dann auf dem Applikationsserver.
- Anwendungsprotokoll (`BAL`) ist **noch nicht umgesetzt** (siehe 9); das Laufprotokoll steht
  bisher nur in der Liste.

### 7.1 Laufzeit

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
| 7 | Markdown-Renderer | offen |
| 8 | Reimport Phase 1 (Anzeige) | offen |
| 9 | BAL-Protokoll, `S_DEVELOP` | offen |

## 9. Offene Punkte

1. **Markdown-Ausgabe** — geplant war ATX-Überschriften, Pipe-Tabellen, Codefences mit
   Sprachkennzeichen `abap`. Bisher nur XML und HTML.
2. **Reimport-Report (Phase 1)** — der Parser existiert, der Report, der eine XML-Datei einliest
   und rendert, fehlt.
3. **BAL-Anwendungsprotokoll** — gelesene Knoten/Objekte, übersprungene wegen Berechtigung,
   abgeschnittene Tabellen, Laufzeit.
4. **`S_DEVELOP`-Prüfung** im Entwicklerreport.
5. **Funktionsbausteine im Verwendungsnachweis** — für die Richtung „welcher Baustein wird von
   wem gerufen" gibt es keinen Index; ein Quelltext-Scan über alle Programme wäre zu teuer.
6. **Mandantenabhängiges Customizing** — der Export bezieht sich auf den Anmeldemandanten.
   Mandantenübergreifendes Customizing ist noch nicht gesondert gekennzeichnet.
7. **Dokumentationsobjekte im Transport** — die von `ZDOCUMIZER_DOCU` erzeugte
   Reportdokumentation liegt nicht im Transportauftrag.
