# Spezifikation: Documizer — IMG-, Entwickler- und ATC-Dokumentationsreports

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

### 2.3a Der ATC-Report

`ZDOCUMIZER_ATC` benutzt dasselbe Kapitelmodell, denselben XML-Renderer, denselben Parser und
denselben HTML-Renderer wie die beiden anderen — wortgleich, mit derselben Begründung
(siehe 1.2). Er liegt in `ZCONS_DOCUMIZER_CORE`.

**Die Kopfzeile der HTML-Ausgabe kommt aus `doc_type` im Dokument, nicht aus dem Report.** Sie
war anfangs fest verdrahtet, und beim Kopieren des Renderers in den ATC-Report wanderte
prompt „Documizer - IMG-Dokumentation" mit. Eine abgeleitete Überschrift kann das nicht.

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
`P_DOWN` + `P_PATH` (PC), `P_DSRV` + `P_SRV` (Applikationsserver), `P_FNAME` (Dateiname, siehe
6.1).

**Block: BC-Set aus Dokument erzeugen** — die Gegenrichtung des IMG-Reports (siehe 3.8).

| Parameter | Vorbelegung | Bedeutung |
|---|---|---|
| `P_BCS` | | BC-Set erzeugen statt dokumentieren |
| `P_BFILE` / `P_BSRV` | | XML-Datei, wahlweise vom Applikationsserver |
| `P_BID` | | Name des BC-Sets |
| `P_BTEXT` | | Kurztext |
| `P_BPACK` / `P_BTR` | `$TMP` | Paket und Auftrag |
| `P_BTEST` | **X** | Testlauf — es wird nichts angelegt |
| `P_BREQ` / `P_BRFIL` | | Fehlliste schreiben, Zieldatei (siehe 3.9) |

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

### 3.8 BC-Set statt Direktzugriff

Ein Dokument beschreibt Customizing. Die naheliegende Gegenrichtung wäre, die Tabellen im
Zielsystem direkt zu beschreiben — und genau das tut der Report **nicht**.

Stattdessen entsteht ein **Business Configuration Set**. Geschrieben wird damit noch nichts;
das Customizing entsteht erst, wenn jemand das Set in **SCPR20** aktiviert. Das ist der
Unterschied, um den es geht: Aktivierung läuft mit Protokoll, mit Anschluss an den
Transportauftrag, mit der Möglichkeit, vorher hineinzusehen, und mit einem Weg zurück. Ein
Report, der `MODIFY` auf eine Customizing-Tabelle absetzt, hat davon nichts.

Geschrieben wird über `SCPR_PRSET_DB_SAVE_ORIG_TABLES`. Zwei Dinge daran sind nicht
offensichtlich:

- **Der Baustein prüft nichts.** Er schreibt, was er bekommt. Jede Prüfung — gibt es die
  Tabelle hier, trägt ihre Auslieferungsklasse überhaupt Kundencustomizing, ist der Inhalt
  vollständig — muss der Report selbst machen.
- **Alle sieben Tabellen müssen übergeben werden.** `SCPRVALS`, `SCPRVALL`, `SCPRRECA`,
  `SCPRSKEYS`, `SCPRFLDV`, `SCPRTEXT`, `SCPRPPRL`. Eine ausgelassene wird nicht etwa in Ruhe
  gelassen, sondern gelöscht.

Drei Sperren entscheiden, was hineinkommt:

| Sperre | Grund |
|---|---|
| Tabelle im Zielsystem unbekannt | Ein Set auf eine Tabelle, die es nicht gibt, lässt sich nicht aktivieren. |
| Auslieferungsklasse nicht `C`, `G` oder `E` | Alles andere ist keine Customizing-Tabelle. |
| Inhalt beim Export abgeschnitten | **Die wichtigste.** Ein an `P_MAXROW` gekürzter Inhalt sieht im Set aus wie der vollständige. Beim Aktivieren verschwindet, was nicht mitkam. |

Für eine vollständige Übernahme muss der Export deshalb mit `P_MAXROW = 0` gelaufen sein.

Jede Auslassung steht mit Begründung im Protokoll. Entdoppelt wird über die Tabellennamen, und
zwar **hinter** den Sperren: eine wegen Kürzung übersprungene Tabelle darf dieselbe Tabelle
aus einer anderen Aktivität nicht blockieren. An einem echten Kundenexport waren das rund 300
doppelte Sätze von 1472.

Der Feldwert trägt ein Kennzeichen `KEY` oder `USE`. `MANDT` reist als Schlüsselfeld mit
leerem Wert — der Mandant des Zielsystems steht beim Aktivieren fest, nicht beim Anlegen.
Der Katalogeintrag ist `R3TR SCP1`.

### 3.9 Die Fehlliste

Ein BC-Set kann nur Tabellen tragen, die es im Zielsystem gibt. Kundeneigene Customizing-
Tabellen gibt es dort aber gerade nicht — sie sind Entwicklung und müssen erst ankommen.

Der IMG-Report schreibt deshalb auf Wunsch (`P_BREQ`) eine **Arbeitsliste** der übergangenen
Objekte:

```xml
<documizer version="1.0" type="REQUEST">
 <meta>
  <system>S4H</system>
  <source>B4D/010</source>
 </meta>
 <objects>
  <object type="TABL" name="ZBSD_SKIP_IND"  activity="ZBSDV_SKIP_IND"/>
  <object type="VIEW" name="ZBSDV_SKIP_IND" activity="ZBSDV_SKIP_IND"/>
 </objects>
</documizer>
```

Diese Datei liest der **Entwickler-Report im Quellsystem** als Startpunkt-Typ `AL` und
exportiert genau die genannten Objekte. Nach deren Import läuft die BC-Set-Erzeugung auch für
sie durch. Damit schließt sich der Kreis: Customizing braucht die Tabellen, die Tabellen
kommen über den Entwickler-Report, und was fehlt, sagt das Zielsystem selbst.

Angefordert wird je Pflegeobjekt die Tabelle, bei Pflegeart `V`/`S` zusätzlich der View, bei
`C` der View-Cluster, dazu die Pflegetransaktion. Damit das Pflegeobjekt beim Reimport
überhaupt noch bekannt ist, steht es seit Formatversion 1.1 ausdrücklich am `<object>`-Tag
(`objtype`, `objname`) — vorher lebte es nur in einer **übersetzten** Notiz („Basistabelle aus
X." / „Base table from X.") und war maschinell nicht mehr auswertbar. Ältere Dokumente ohne
diese Attribute werden weiterhin gelesen; aus ihnen entstehen dann nur die Tabelleneinträge.

**Angefordert wird nur, was hier wirklich fehlt.** Der erste Lauf verlangte `SM30` — eine
Standardtransaktion, die in jedem System steht. Eine Fehlliste, die Vorhandenes anfordert,
kostet den Entwickler im Quellsystem Zeit und Vertrauen. Geprüft wird je Typ gegen `DD02L`,
`DD25L`, `VCLDIR` bzw. `TSTC`.

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

Ein Code fällt aus der Reihe: **`AL` — Arbeitsliste aus Fehlliste.** Er benennt kein Objekt,
sondern eine Liste davon. Der Startpunkt steht dann in einer Datei (`P_AFILE`, wahlweise vom
Applikationsserver über `P_ASRV`), nicht im Namensfeld; jedes Objekt der Liste wird ein
eigenes Kapitel. Woher die Datei kommt, steht in 3.9.

Der Kapitelaufbau ist deshalb nicht mehr fest verdrahtet: bei einem Einzelobjekt bleibt es bei
Kapitel 1 für das Objekt, 2 für die verwendeten und 3 für die Verwender; bei einer Arbeitsliste
mit *n* Objekten sind es die Kapitel 1 bis *n*, danach *n+1* und *n+2*.

Ein **Funktionsbaustein** hat keinen eigenen `TADIR`-Satz und läuft deshalb unter dem
Pseudotyp `FUNC`: Kurztext aus `TFTIT`, Doku über Dokuklasse `FU`, Schnittstelle aus
`FUPARAREF`, Quelltext aus seinem Include.

### 4.2 Selektionsbild

**Block: Startpunkt** — `P_STYPE`, `P_SVAL`, `P_AFILE` + `P_ASRV` (nur bei `AL`),
`P_RECUR` (Unterpakete rekursiv, nur Paket), `P_LOCAL` (lokale Pakete einbeziehen).
Typen: `K` Paket, `P` Programm, `C` Klasse/Interface,
`FF` Baustein, `F` Funktionsgruppe, `T` Tabelle, `V` View, `D` Datenelement, `DO` Domäne,
`W` CDS View, `MX` Metadata Extension, `BD` Verhaltensdefinition, `SD` Service-Definition,
`SB` Service-Binding, `IS` IDoc-Segmenttyp, `IT` IDoc-Basistyp, `U5` UI5-Anwendung,
`AL` Arbeitsliste aus Fehlliste.

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
| `P_USEALL` | | Verwendungsnachweis auch für die verwendeten Objekte, nicht nur fürs Startobjekt (siehe 4.6) |
| `P_MAXHIT` | 40 | Maximale Fundstellen je Stelle |
| `P_FSRC` | | Fundstellen im ganzen Quelltext |
| `P_DEF` | X | Definitionsdaten für den Reimport (siehe 5.5) |

**Block: Ausgabe** — wie Report A, einschließlich `P_FNAME` (siehe 6.1).

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

**Zwei Appserver-Kennzeichen, zwei Dateien.** `P_ASRV` im Block Startpunkt gehört zur
Fehlliste, `P_ISRV` im Importblock zur XML-Datei. Beide hießen anfangs fast gleich („File is on
the app server"), und prompt kam die Frage, warum der Import-Schalter im falschen Block steht.
Er stand nie dort. Die Beschriftungen nennen jetzt ihre Datei — *Fehlliste liegt auf
Appl.-Server* und *XML-Datei liegt auf Appl.-Server*. Verschoben wird nichts: die Fehlliste ist
ein Startpunkt, das Quellsystem liest sie und exportiert, was darin steht (siehe 3.9).

| Parameter | Vorbelegung | Bedeutung |
|---|---|---|
| `P_IMP` | | Importieren statt dokumentieren |
| `P_IFILE` | | XML-Datei |
| `P_ISRV` | | XML-Datei liegt auf dem Applikationsserver |
| `P_ITEST` | **X** | Testlauf — es wird nichts angelegt |
| `P_IOVER` | | Bestehende Objekte überschreiben |
| `P_IACT` | X | Nach dem Anlegen aktivieren |
| `P_IPACK` | `$TMP` | Zielpaket |
| `P_ITR` | | Auftrag (bei nicht-lokalem Paket) |
| `P_ITASK` | X | Aufgabe unter dem Auftrag anlegen, wenn keine offene da ist (siehe 5.6) |
| `P_IKEEP` | | Quellpaket beibehalten |
| `P_IOLD1..4` / `P_INEW1..4` | | Paketregeln alt → neu (siehe 5.7) |

### 4.3 Ablauf

**Paketmodus** (`P_STYPE = K`): Pakete über
`CL_PAK_PACKAGE_QUERIES=>GET_ALL_SUBPACKAGES`, Objekte je Paket über
`GET_DEV_OBJECT_TADIR_KEYS`, gruppiert nach Objekttyp.

Beide Methoden arbeiten mit **klassischen Ausnahmen**. Ohne `EXCEPTIONS`-Zusatz im Aufruf führt
jede davon zum Kurzdump — `TRY...CATCH` greift dort nicht. Pakete ohne `TDEVC`- oder
`TADIR`-Satz sind im Bestand durchaus vorhanden; sie erscheinen mit Vermerk im Dokument, statt
den Lauf abzubrechen.

**Gelöschte Objekte.** Wird ein Objekt gelöscht, bleibt sein `TADIR`-Satz mit `DELFLAG = 'X'`
stehen, bis der Auftrag mit der Löschung freigegeben ist — und `GET_DEV_OBJECT_TADIR_KEYS`
liefert ihn mit. Im Dokument stand dann eine Klasse, die es nicht mehr gibt, mit leerem
Kurztext und ohne Details (gefunden an `ZCONS_GRC_PROBE_SRCH` in `ZCONS_GRC_MAILER`). Die
Paketschleife liest die gelöschten Einträge des Pakets einmal vorab und überspringt sie; die
Namensauflösungen gegen `TADIR` fragen `DELFLAG` an elf Stellen mit ab.

**Die Paketgrenze bleibt.** Im Paketmodus ist der Gegenstand das Paket. Was dessen Objekte
außerhalb verwenden, steht mit „Ausgehende Aufrufe" in der Aufrufliste, wird aber nicht als
eigenes Kapitel dokumentiert. Wer eine Anwendung samt ihrer Nachbarschaft braucht, startet
vom tragenden Objekt — bei einer RAP-Anwendung der Root-View (`W`) — mit Verweistiefe 2.

**Einzelobjektmodus** (alle anderen Typen): Kapitel 1 ist das gewählte Objekt. Ist
„Ausgehende Aufrufe" angehakt und die Verweistiefe > 0, folgt in Kapitel 2 alles, was es
verwendet — nach Objekttyp gruppiert und mit denselben Details.

### 4.4 Aufbereitung je Objekttyp

| Typ | Inhalt |
|---|---|
| `PROG` | Titel, **Textelemente** (Titel, Selektionstexte, Textsymbole, Überschriften), Objektdoku, optional Quelltext |
| `CLAS` / `INTF` | Oberklasse und Schnittstellen, Komponenten mit Art (Attribut, Methode, Ereignis, Typ), implementierte Schnittstellenmethoden, lokale Klassen mit ihren Methoden |
| `FUGR` | Bausteinliste mit Kurztexten |
| `FUNC` | Schnittstelle aus `FUPARAREF` (Import, Export, Changing, Tabellen, Ausnahmen) |
| `TABL` | Feldliste mit Datenelement und Schlüsselkennzeichen; bei einem IDoc-Segment aus `EDSAPPL` |
| `VIEW` | Feldliste **und Basistabellen mit Join** (`DD26S`: Reihenfolge, Fremdschlüssel) |
| `DDLS` | **Feldliste** der Entität aus `DD03ND`, verwendete Objekte aus `DDLDEPENDENCY`, optional Quelltext |
| `BDEF` / `SRVD` / `DDLX` | optional Quelltext über den Workbench-Operator |
| `IDOC` | Segmenthierarchie (WE60), Nachrichtentypen (WE82), verarbeitende Bausteine (WE57) |
| `DTEL` | Feldbezeichner kurz/mittel/lang/Überschrift aus `DD04T` |
| `DOMA` | Festwerte aus `DD07T` |

**Klassen.** `SEOCOMPO` führt nur, was die Klasse selbst deklariert. Eine Klasse, die nichts tut
als eine Schnittstelle zu implementieren — ein RAP-Query-Provider etwa —, hat dort keinen
einzigen Satz, und der Detailblock brach ab. Dazu kommen jetzt drei Quellen:

| Was | Woher |
|---|---|
| Oberklasse, Schnittstellen | `SEOMETAREL`, `RELTYPE` 2 bzw. 1 |
| implementierte Schnittstellenmethoden | `TMDIR`, Methodenname `SCHNITTSTELLE~METHODE` |
| lokale Klassen und deren Methoden | Quelltext des `…CCIMP`-Includes |

Die lokalen Klassen kennt kein Katalog. Ein Behavior-Pool ist nach außen leer; die Handler, die
die Logik tragen (`lhc_<entität>`), stehen dort. Gelesen wird der Include mit `READ REPORT` und
nach `CLASS … DEFINITION` und `METHODS` durchsucht — `DEFERRED` und `LOAD` sind keine
Definition.

**IDoc-Basistyp.** Jede der drei Sichten ist nach der Transaktion benannt, in der SAP dasselbe
zeigt. Die Hierarchie kommt aus `IDOCTYPE_READ`, derselben Schnittstelle wie die
Definitionsdaten; Ebene und Wiederholbereich werden ohne führende Nullen ausgegeben, wie WE60
es tut (`1..9999`). Die Nullen fallen **textuell** weg: `OCCMAX` ist `NUMC(10)`, und
`9999999999`, die Marke für unbegrenzte Wiederholung, passt in kein `TYPE I` — der erste Versuch
endete in `BCD_OVERFLOW`. WE82 kommt aus `EDIMSG` (Nachrichtentyp, Erweiterung, Release), WE57
aus `EDIFCT` (Baustein, Richtung, Nachrichtentyp, Objekttyp). WE57 ist die Stelle, an der ein
IDoc auf Code trifft.

**IDoc-Segment.** Die erzeugte DDIC-Struktur ist eine flache Zeichenstruktur: `DD03L` führt jedes
Feld als `CHAR` **ohne** `ROLLNAME`. Das Datenelement, das WE31 zeigt, steht allein in
`EDSAPPL` unter dem Segmenttyp. Feldliste und Verweissammlung nehmen deshalb für Segmente
`EDSAPPL`, sonst `DD03L`.

**CDS-View.** `DD03L` kennt höchstens den SQL-View, eine View Entity oder Custom Entity hat gar
keinen. Die Elemente stehen in `DD03ND` unter dem Entitätsnamen, den `DDLDEPENDENCY` als
`STOB` nennt. Ein Feld ohne Datenelement zeigt Datentyp und Länge.

**Kurztexte.** Für die CDS- und RAP-Schicht fehlten sie anfangs ganz:

| Typ | Texttabelle |
|---|---|
| `DDLS`, `STOB` | `DDDDLSRCT` (bei `STOB` über die zugehörige DDL-Quelle) |
| `MSAG` | `T100T` |
| `SRVD` | `SRVDSRCT` |
| `SRVB` | `SRVB_HEAD_T` |
| `IWSV`, `IWMO`, `IWVB` | `/IWBEP/I_MGW_SRT`, `_OHT`, `_VOT` — Name und Version stehen im Katalog in einem Feld |
| `BDEF`, `DDLX` | keine lesbare Tabelle; `GET_DESCRIPTION( )` am Workbench-Operator |

Die Tabellen für `SRVD`, `SRVB` und die Gateway-Objekte gibt es nicht auf jedem Stand; sie werden
dynamisch gelesen und abgefangen. Ein fehlender Text beendet den Lauf nicht. Bei `IWMO` und
`IWVB` ist der Text oft schlicht nicht gepflegt — das ist der Zustand im System.

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

Bei einem **IDoc-Segment** stehen die Datenelemente nicht in `DD03L`, sondern in `EDSAPPL`
(siehe 4.4). Solange die Verweissammlung nur `DD03L` las, enthielt ein Export die Segmente, aber
kein einziges ihrer Datenelemente, und im Zielsystem scheiterte `SEGMENT_CREATE`. Gemessen an
`ZSRA001` mit Definitionsdaten:

| Verweistiefe | im Dokument |
|---|---|
| 1 | Basistyp, 7 Segmente |
| 2 | dazu 32 Datenelemente |
| 3 | dazu 23 Domänen |

### 4.6 Verwendungsnachweis

Nur für das **Startobjekt**. Die Frage „wer benutzt das" gilt dem Einstiegspunkt, nicht seiner
Nachbarschaft — ein Datenelement wie `CHAR255` wird in tausenden SAP-Programmen verwendet und
würde das Dokument unter seiner eigenen Verwendungsliste begraben. Im Paketmodus bleibt es beim
Nachweis je Objekt, dort ist jedes Objekt selbst Gegenstand des Dokuments.

**Auf Wunsch auch für die verwendeten Objekte** (`P_USEALL`). Bei einem IDoc-Basistyp kehrt sich
die Abwägung um: den Basistyp typisiert niemand, seine Segmente werden dauernd gelesen — die
Frage gilt gerade der Nachbarschaft. Mit dem Kennzeichen wird der Nachweis zu jedem Objekt
gezogen, das ins Dokument kommt. Vorbelegt ist es aus, damit sich für bestehende Varianten
nichts ändert; `P_MAXUSE` gilt weiter je Objekt.

**Drei Schalter, zwei Richtungen.** `P_RDEP` folgt dem, was ein Objekt verwendet, und dem, was
das wiederum verwendet. `P_UDEP` geht in die Gegenrichtung und dokumentiert die gefundenen
Verwender selbst als Kapitel. `P_USEALL` ist keine Tiefe, sondern entscheidet, zu welchen
Objekten der Nachweis überhaupt gezogen wird.

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
- bei einer Tabelle oder Struktur die **angefassten Felder**. `WBCROSSGT` führt eine
  Feldverwendung unter `<Struktur>\TY:<Feld>`; die Suche nach dem bloßen Strukturnamen findet
  davon keine einzige. Gesucht wird mit `LIKE … ESCAPE '#'` — der Unterstrich im Strukturnamen
  wäre sonst ein Platzhalter. Die Treffer werden in die vorhandene Liste eingeschmolzen, in
  einem Durchlauf über die sortierte Liste: je Fundstelle eine Zeile, die Felder dahinter
  (an `E1MAKTM` etwa „Felder MAKTX, SPRAS"). Das ist die Liste, die SE11 unter
  *Verwendungsnachweis Strukturfeld* zeigt.

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

## 4a. Report C — ATC-/Code-Inspector-Prüfkonfiguration (`ZDOCUMIZER_ATC`)

Die dritte Sicht neben Customizing und Entwicklung: nicht was im System steht, sondern **woran
es gemessen wird**. Welche Prüfvarianten es gibt, welche Checks darin stecken, mit welcher
Priorität deren Meldungen laufen und mit welchem Pseudokommentar oder Pragma sich eine Meldung
unterdrücken lässt.

### 4a.1 Selektionsbild

**Block: Auswahl**

| Parameter | Vorbelegung | Bedeutung |
|---|---|---|
| `P_MODE` | `V` | `V` Prüfvariante, `K` Katalog aller aktivierten Checks |
| `P_VAR` | `DEFAULT` | Prüfvariante, F4 über die nicht-versteckten |
| `P_VUSR` | | Eigentümer; leer heißt globale Variante |
| `P_ALLV` | | alle Varianten statt einer |
| `P_HIDE` | | versteckte Varianten einbeziehen |

**Block: Umfang** — `P_LANGU`, `P_MSG` (Meldungen je Check), `P_PRIO` (Kundenpriorisierung),
`P_PCOM` (Pseudokommentar und Pragma), `P_EXMP` (erteilte Ausnahmen zählen), `P_CAT` (nach
Kategorie gliedern).

**Block: Ausgabe** — wie Report A, einschließlich `P_FNAME`.

### 4a.2 Woher die Daten kommen

| Quelle | Inhalt |
|---|---|
| `SCICHKV_HD` / `SCICHKV_TX` | Kopf und Text der Prüfvarianten |
| `CL_CI_CHECKVARIANT=>GET_REF` + `GET_INFO` | die Checkliste der Variante |
| `CL_CI_TESTS=>GET_TESTS` | alle aktivierten Checks (Katalogmodus) |
| `CL_CI_TESTS=>GET_TEST_REF` | Instanz einer Checkklasse: Beschreibung, Kategorie, Version, `SCIMESSAGES` |
| `CL_CI_TESTS=>GET_MESSAGE_TEXT` | Meldungstext in der Ausgabesprache |
| `SCIPRIORITIES` | kundeneigene Priorisierung je Check und Code |
| `SATC_CI_EXEMPT` | erteilte Ausnahmen |

**Die Checkliste einer Variante steht nicht lesbar in der Datenbank.** `SCICHKV_PA` ist ein
INDX-Cluster; der Weg führt deshalb über die API und nicht über `SELECT`. Das ist der Grund,
warum dieser Report als einziger ohne einen einzigen Direktzugriff auf seine Kerndaten
auskommt.

**`GET_TEST_REF` meldet einen unbekannten Check nicht**, sondern gibt eine initiale Referenz
zurück — das steht so in der Dokumentation der Methode. Der Aufrufer muss selbst prüfen. Ein
Check, den die Variante nennt und den es hier nach einem Upgrade nicht mehr gibt, bekommt
trotzdem ein Kapitel mit dem Vermerk „nicht ladbar": eine Lücke in der Konfiguration zu
verschweigen wäre schlimmer, als sie zu zeigen.

**Die Ausnahmen werden als „es gibt eine Ausnahme dazu" gezählt, nicht als „sie ist
genehmigt".** Der Schlüssel des Genehmigungsstands wechselt zwischen Ständen; gefiltert wird
nur auf nicht gelöscht. Das Dokument sagt es so.

### 4a.3 Kapitelaufbau

```
1     Prüfvariante            (Kopfdaten als Objekt: Eigentümer, transportierbar, versteckt)
1.1     Kategorie
1.1.1     Check               (ein Objekt: Meldungen mit Code, Priorität, Kundenprio,
                               Pseudokommentar, Pragma, Ausnahmen, Text)
```

Im Katalogmodus entfällt die Variantenebene. Ohne `P_CAT` entfällt die Kategorieebene.

Gemessen auf S4H an der Variante `DEFAULT`: 17 Checks, 1198 Meldungen, Roundtrip identisch.

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

**Feldnamen, die kein XML-Attributname sein können.** Der RTTI-Durchlauf nimmt den
Komponentennamen und schreibt ihn als Attributnamen — das ging gut, solange nur
DDIF-Strukturen durchliefen. `RPY_DYFATC`, die Feldliste eines Dynpros, hat die Felder
`*_ENTRY` und `2_DIMENS`: ein Stern ist im XML-Namen verboten, eine führende Ziffer auch. Ohne
Umschrift käme kein Dynpro durch den Writer.

Umgeschrieben wird über eine feste Tabelle (`*` → `_xas_`, `/` → `_xsl_`, `-` → `_xmi_`,
`.` → `_xdt_`, führende Ziffer → Präfix `_n`), nicht über eine Codepage-Klasse. Die Marken sind
kleingeschrieben und kommen in DDIC-Feldnamen nicht vor, also ist die Umschrift umkehrbar; der
Parser dreht sie beim Zuweisen wieder zurück. Ein Zeichen, für das es keine Marke gibt, führt
dazu, dass das **Feld weggelassen** wird — lieber ein fehlendes Feld als ein unlesbares
Dokument.

**Textelemente und Objektdokumentation in allen Sprachen.** Wie Nachrichten (siehe 5.6) sind sie
Definitionsdaten, keine Beschreibung. Der Textpool wurde anfangs nur in der Ausgabesprache
gelesen und beim Import in die Anmeldesprache des Importierenden geschrieben: ein englisch
gepflegter Report, von einem deutsch angemeldeten Benutzer importiert, hatte danach deutsche
Selektionstexte mit englischem Inhalt und englische gar keine. Jetzt kommen die Textelemente
aller Sprachen aus `REPOTEXT` ins Dokument, jede `TPOOL`-Zeile mit dem Attribut `_SPRSL`.

Die Objektdokumentation von Programmen (`RE`) und Datenelementen (`DE`) reist als eigene
`DOCU`-Zeile je Sprache aus `DOKHL`, mit dem Attribut `LANGU` — unabhängig von `P_DOKU`. Das
Kapitel zeigt die Dokumentation dem Leser nur mit angehaktem Kennzeichen und nur in einer
Sprache; die Definitionsdaten tragen sie immer. Inhalt ist das ITF aus `DOCU_GET`, je Zeile
Format und Text durch einen Tabulator getrennt.

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
| Report, Include | `INSERT REPORT … DIRECTORY ENTRY`, `INSERT TEXTPOOL` je Sprache | umgesetzt |
| GUI-Status eines Programms | `RS_CUA_INTERNAL_FETCH` / `_WRITE` | umgesetzt |
| Nachrichtenklasse | `T100A` / `T100` direkt, Katalogeintrag über `TR_TADIR_INTERFACE` | umgesetzt |
| Verhaltensdefinition, Service-Definition, Metadata Extension | `CL_WB_OBJECT_OPERATOR_FACTORY` + `IF_WB_OBJECT_DATA_MODEL` | umgesetzt |
| Service-Binding | `CL_SRVB_OBJECT_DATA` über denselben Operator | umgesetzt |
| IDoc-Segmenttyp | `SEGMENT_READ` / `SEGMENT_CREATE` | umgesetzt |
| IDoc-Basistyp | `IDOCTYPE_READ` / `IDOCTYPE_CREATE` / `_UPDATE` | umgesetzt |
| UI5-Anwendung (BSP) | `/UI5/CL_UI5_REP_DT` (`GET_FILE` / `PUT_FILE`, `CREATE_REPOSITORY`) | umgesetzt |
| Interface, Klasse | `SEO_*_CREATE_COMPLETE` + `IF_OO_CLIF_SOURCE` | umgesetzt |
| Funktionsgruppe, Funktionsbaustein | `RS_FUNCTION_POOL_INSERT`, `RPY_FUNCTIONMODULE_INSERT` | umgesetzt |
| Dynpro | `RPY_DYNPRO_READ` / `RPY_DYNPRO_INSERT` | umgesetzt |
| Pflegeeintrag (TVDIR, TVIMF, TDDAT) | direkt geschrieben, siehe unten | umgesetzt |
| Transaktion | `RPY_TRANSACTION_READ` / `_INSERT` | umgesetzt |
| View-Cluster | `VIEWCLUSTER_GET_DEFINITION` / `_SAVE_DEFINITION` | umgesetzt |
| Objektdokumentation | `DOCU_UPDATE` je Sprache | umgesetzt für Report und Datenelement |
| ICF-Knoten, MIME-Objekte, Gateway-Registrierung, Berechtigungsvorschlagswerte | — | **nicht umgesetzt**, siehe 9 |

**Nicht angelegt** werden `SICF`, `SMIM`, `SUSH` sowie `IWSV`/`IWMO`/`IWVB`. Sie erscheinen im
Dokument als Objekt mit Namen — ein Paketlauf einer Fiori-Anwendung führt sie auf —, aber der
Importer kennt für sie keinen Weg. Das Protokoll sagt es je Objekt, damit niemand sie im
Zielsystem sucht.

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

**Der Pflegeapparat.** Bis hierher kam im Zielsystem ein View an, den **SM30 nicht kennt**.
Der Dialog dahinter ist kein Teil des Views, sondern steckt an drei Stellen, auf die kein
Querverweis zeigt:

| Teil | Wo er steht |
|---|---|
| Funktionsgruppe und Bildnummern | `TVDIR` |
| Formroutinen zu den Pflegeereignissen | `TVIMF` |
| Berechtigungsgruppe | `TDDAT` |
| Bilder mit Ablauflogik | Dynpros der Funktionsgruppe |
| Einstieg | Pflegetransaktion, meist Parametertransaktion auf SM30 |

Alle fünf reisen jetzt mit. Funktionsgruppe und Pflegetransaktion zieht der Sammler über
`TVDIR` von selbst nach; sie stehen in keinem Index, und ohne diesen Umweg käme der Dialog nie
zustande.

`TVDIR`, `TVIMF` und `TDDAT` werden im Zielsystem **direkt geschrieben**. Erzeugen ließen sie
sich nur über SE54, und `VIEW_MAINTENANCE_GENERATE` ist nichts als ein `CALL TRANSACTION
'SE55'` — ein Dialog, und damit für einen Report ohne Bedienung unbrauchbar. Die drei Tabellen
sind mandantenunabhängig und hängen nicht am Transportauftrag; das Protokoll weist es aus,
damit niemand den Eintrag im Auftrag sucht. Vor dem Schreiben wird geprüft, ob die
Funktionsgruppe steht — ein Eintrag, der ins Leere zeigt, führt in SM30 zum Kurzdump statt zu
einer Meldung.

**Die Ablauflogik ist als `DYN_FLOWLIST` typisiert, nicht als `RPY_DYFLOW`** — obwohl die
Schnittstelle von `RPY_DYNPRO_READ` und `RPY_DYNPRO_INSERT` genau das deklariert. Beide
Bausteine reichen die Tabelle unverändert an ihr NATIVE-Gegenstück weiter, und dessen Parameter
ist mit dem Tabellentyp `DYN_FLOWLIST` typisiert. `RPY_DYFLOW` ist doppelt so lang wie dessen
Zeilentyp `D022S`; ein nicht typkompatibler Aktualparameter endet dort im Kurzdump
`CALL_FUNCTION_CONFLICT_TAB_TYP`. Die deklarierte Typangabe ist an dieser Stelle irreführend.

**Ein vorhandenes Dynpro wird nicht überschrieben.** `RPY_DYNPRO_INSERT` kennt dafür keinen Weg
ohne SE51; das Protokoll meldet es je Bild. Beim Erstimport spielt das keine Rolle, beim
Nachliefern geänderter Bilder schon.

**Parametertransaktionen** — SM30 mit vorbelegtem `VIEWNAME` — stehen in `TSTCP` als eine
Zeile: hinter `/*` die gerufene Transaktion, dahinter `NAME=WERT`, getrennt durch Semikolon.
Das führende `/*` heißt „erstes Bild überspringen". Der Import baut daraus wieder
`CALLED_TRANSACTION`, `CALLED_TRANSACTION_SKIP` und die Parameterwerte auf. Die GUI-Kennzeichen
(`TSTCC`) nimmt `RPY_TRANSACTION_INSERT` nicht entgegen und werden hinterher geschrieben.

**View-Cluster** liest `VIEWCLUSTER_GET_DEFINITION` am Stück. Kopf und Struktur kommen als
Pflegeviews `V_VCLDIR` und `V_VCLSTRUC` heraus, die den Text schon enthalten — die Texte
brauchen also keinen eigenen Weg. Angelegt wird ein Cluster nur, wenn **jeder** Knoten
vorhanden ist; ein Cluster mit einem fehlenden View läuft in SM34 beim Aufklappen in einen
Fehler, und ein nicht angelegter Cluster mit einer klaren Meldung ist besser als ein kaputter.

**BDEF, SRVD und DDLX** — die Backend-Schichten einer Fiori-Anwendung — sind alle drei reine
Quelltextobjekte und hängen am **generischen Workbench-Objektoperator**. Ein `def_`/`put_`-Paar
bedient alle drei; der Unterschied zwischen ihnen ist eine Zuordnungstabelle:

| Typ | `wbobjtype` | Datenmodell |
|---|---|---|
| Verhaltensdefinition | `BDEF` / `BDO` | `CL_BLUE_SOURCE_OBJECT_DATA` |
| Service-Definition | `SRVD` / `SRV` | `CL_SRVD_WB_OBJECT_DATA` |
| Metadata Extension | `DDLX` / `EX` | `CL_DDLX_WB_OBJECT_DATA` |

Gelesen wird mit `read( data_selection = c_data_content )` — das liefert bei allen dreien einen
String. Geschrieben wird über ein Datenmodell, das per `CREATE OBJECT … TYPE (klassenname)`
entsteht, mit Name, Beschreibung und Quelltext gefüllt und an `create( )` bzw. `update( )`
übergeben wird, gefolgt von `activate( )`.

Drei Punkte sind daran nicht offensichtlich:

- **Der Katalog beweist hier nichts.** Auf S4H stehen reihenweise `BDEF`- und `DDLX`-Einträge in
  `TADIR`, deren Inhalt sich nicht laden lässt („Error while importing object from the
  database"). Existenzprüfung und Prüfung nach dem Lauf fragen deshalb `check_existence( )` am
  Operator, nicht den Katalog — und jeder Zugriff ist abgefangen, sonst reißt eine Karteileiche
  den ganzen Lauf mit.
- **Die Beschreibung kommt bei SRVD aus dem Quelltext.** Das Datenmodell liefert dort nichts,
  die Bezeichnung steht als `@EndUserText.label` in der Quelle selbst. Ohne Beschreibung lehnt
  `create( )` ab, also wird sie von dort geholt; notfalls dient der Objektname.
- **Nur Name und Beschreibung im Kopf.** UUID, Änderer, Zeitstempel und Quellsystem stehen zwar
  im Metadatensatz, sind aber systemspezifisch und bleiben nach Grundsatz 2 draußen.

**Service-Bindings** sind etwas anderes: kein Quelltext, sondern eine verschachtelte Struktur.
`get_datatype_name( )` meldet für sie gar nichts, der Zugriff läuft deshalb typisiert über
`cl_srvb_object_data=>ty_object_data`. Zwei Tabellenebenen werden zu zwei Zeilenarten:

```xml
<definition kind="SRVB">
  <attr name="BIND_TYPE"          value="ODATA"/>
  <attr name="BIND_TYPE_VERSION"  value="V2"/>
  <attr name="PUBLISHED"          value="true"/>
  <row tag="SRVB_SRV"><attr name="SERVICE_NAME" value="…"/></row>
  <row tag="SRVB_VER">
    <attr name="SERVICE_NAME"    value="…"/>   <!-- Rueckverweis -->
    <attr name="SERVICE_VERSION" value="0001"/>
    <attr name="SRVD_NAME"       value="…"/>
  </row>
</definition>
```

Zeilen sind im Dokument eine flache Liste. Der **Servicename steht deshalb in jeder
Versionszeile mit** — ohne diesen Rückverweis ließe sich beim Import nicht sagen, zu welchem
Service eine Version gehört. Von der Objektreferenz auf die Service-Definition wandert nur der
Name mit; URI und Paket sind systemspezifisch.

**Veröffentlicht wird nicht.** Ob das Binding im Quellsystem veröffentlicht ist, steht als
Information im Dokument, aber der Import legt es grundsätzlich *unveröffentlicht* an. Ein
Binding anzulegen ist eine Entwicklungsaufgabe; einen OData-Dienst nach außen bereitzustellen
ist eine andere, und die sollte niemand nebenbei treffen.

**Was nicht mitkommt:** die Bezeichnung des Bindings. `get_description( )` liefert nichts, der
Metadatensatz beim Lesen der aktiven Fassung auch nicht — ADT zeigt sie, holt sie also
woanders her. Beim Import tritt der Objektname an ihre Stelle. Das Binding ist damit
vollständig, nur seine Bezeichnung nicht.

**UI5-Anwendungen** sind der einzige Objekttyp, bei dem XML und HTML bewusst auseinanderlaufen.

Der Rahmen ist eine BSP-Anwendung, die Dateien sind ihre Seiten — `Component.js`,
`manifest.json`, `i18n/i18n.properties` und was sonst dazugehört, mit Verzeichnispfad und
Groß-/Kleinschreibung im Namen.

**Die Seiten-API ist die falsche Ebene, und sie sagt es nicht.** `CL_O2_API_PAGES->GET_PAGE`
liefert einen `xstring`, der wie der Dateiinhalt aussieht. Er ist es nicht: er enthält den
XML-Rahmen der Seite (`<?xml …?><so2:page o="0" x="0" …>`), für `Component.js` gemessene
365 Bytes. Ein Import, der diesen Rahmen zurückschreibt, legt Seiten mit richtigen Namen,
richtigen Attributen und leerem Inhalt an — 22 davon, ohne eine einzige Fehlermeldung. Beide
Seiten des Rundlaufs melden dieselbe Bytezahl, weil beide dieselbe Hülle zählen.

Aufgefallen ist es erst an einer anderen Stelle: SE80 fand die importierte Anwendung nicht
(„Objekt als Teil der Adresse `/SAP/BC/BSP/SAP/…` nicht gefunden"), und die ADT-Ressource
`/sap/bc/adt/filestore/ui5-bsp/objects/<app>/<datei>/content` antwortete mit 404, obwohl alle
22 Seiten in `O2PAGDIR` standen.

**Der Weg ist die UI5-Repository-API**, `/UI5/CL_UI5_REP_DT` über `/UI5/IF_UI5_REP_DT`. Sie
kennt zweierlei, was den O2-Tabellen fehlt:

* **Den Pfadbaum.** Er steht nicht in den Seitennamen, sondern in einer eigenen Zuordnungsdatei
  `UI5RepositoryPathMapping.xml`; lange Pfade liegen als Seite unter einem Hashnamen
  (`UI556BC4A63F…`). Ohne Eintrag in dieser Datei existiert eine Datei für die Anwendung nicht —
  `CHECK_OBJECT_EXISTENCE` fragt genau dort nach.
* **Den vollständigen Anlegevorgang.** `CREATE_REPOSITORY` erzeugt BSP-Anwendung, MIME-Ordner,
  ICF-Knoten und Katalogeintrag; `CREATE_FOLDER` und `PUT_FILE` pflegen die Zuordnungsdatei mit.

Der Export geht den Baum ab (`GET_FOLDER_CHILDREN`, `CHECK_IS_FOLDER`) und holt jede Datei über
`GET_FILE` als `xstring`. Der Import legt erst Ordner (`WAPA_DIR`), dann Dateien (`WAPA_FILE`)
an, gerahmt von `LOCK` und `UNLOCK`. Es reisen die Bytes, **Base64**-kodiert — eine Regel für
Text und Binäres, ohne Raten über Kodierungen.

ADT nimmt denselben Weg. Das ist kein Zufall, sondern der Prüfstein: was ADT anzeigen kann, ist
angekommen.

**Base64 gehört ins XML, nicht ins HTML.** Das ist keine Absicht, die man einhalten muss,
sondern eine Eigenschaft des Aufbaus: der HTML-Renderer fasst Definitionsdaten grundsätzlich
nicht an — nachgezählt, null Verweise gegen acht im XML-Renderer. Der `<definition>`-Block
erreicht das HTML nicht. Wer das ändern will, muss den Renderer aktiv umbauen.

**Was das kostet.** Base64 bläht um rund ein Drittel auf. Die gemessene App hat 21 Dateien und
100.905 Bytes Inhalt; das Dokument wurde 139.190 Zeichen groß. Eine Freestyle-App mit
Bibliotheken landet im zweistelligen Megabyte-Bereich. Das ist der bewusst gezahlte Preis
dafür, die App überhaupt übertragen zu können.

21 Dateien, nicht 22: die Zuordnungsdatei selbst reist nicht mit. Sie ist Buchhaltung des
Zielsystems und entsteht dort neu.

**Gemessener Rundlauf.** Export von `ZCONS_TI_M_TASK`, Import unter neuem Namen, Gegenprobe
über ADT: derselbe Verzeichnisbaum (11 Einträge in der Wurzel, Ordner wie Dateien), und
`manifest.json` sowie `i18n/i18n.properties` kommen Zeichen für Zeichen zurück.

**IDoc-Segmenttypen** waren die unangenehmste Sorte Lücke: keine, die auffällt, sondern eine,
die falsch aussieht. Ein Segmenttyp trägt im Objektkatalog **`TABL`**, weil SAP zu jedem
Segment eine gleichnamige DDIC-Struktur erzeugt. Der Sammler nahm ihn deshalb als Struktur auf,
und beim Import wäre im Zielsystem eine Struktur mit den richtigen Feldern entstanden, die WE31
nicht als Segment kennt — Segmentdefinition und Freigabestände fehlten, ohne dass es jemandem
aufgefallen wäre.

Die Definitionsermittlung prüft deshalb bei jedem `TABL`, ob der Name in `EDISEGMENT` steht,
und behandelt ihn dann als `SEGM`. `SEGMENT_READ` und `SEGMENT_CREATE` sind das Paar; letzteres
legt Segmenttyp, Segmentdefinition und die Struktur in einem Zug an. Der Kopf ist `EDISEGMHD`
(ohne Anlage- und Änderungsstempel), die Felder sind `EDISEGSTRU`-Zeilen.

Ein **bestehendes Segment wird nicht angefasst**, auch nicht mit „Bestehende überschreiben".
`SEGMENT_MODIFY` hängt eine neue Segmentdefinition an, und welche Version gilt, ist eine
Entscheidung des Entwicklers, nicht eines Importlaufs.

`SEGMENT_CREATE` hat `DEVCLASS` und `ORDER` als **`CHANGING`**-Parameter, nicht als `EXPORTING` —
der Baustein gibt beide auch wieder heraus. Im falschen Block übergeben endet der Aufruf in
`CALL_FUNCTION_PARM_UNKNOWN`. Dass das lange nicht auffiel, liegt an der Sprache: `CALL FUNCTION`
mit einem Literal wird zur **Laufzeit** aufgelöst, der Report aktiviert also fehlerfrei mit
einem Aufruf, der nie laufen kann. Nach dem Fund wurden alle 13 schreibenden Bausteine des
Importers gegen `FUPARAREF` abgeglichen — 48 Parameter, keine weitere Abweichung.

**Damit ein Basistyp im Zielsystem entsteht**, muss das Dokument alles tragen, worauf er steht:
die Segmente, deren Datenelemente und die Domänen dahinter, soweit es eigene sind. Das heißt
Export mit Definitionsdaten und **Verweistiefe 3** (siehe 4.5). Mit Verweistiefe 2 fehlen die
Domänen; das eigene Datenelement aktiviert nicht, das Segment scheitert daran und der Basistyp
am Segment.

**IDoc-Basistypen** haben mit `IDOCTYPE_READ` / `IDOCTYPE_CREATE` / `IDOCTYPE_UPDATE` ein
sauberes Tripel. Kopfdaten sind `EDI_IAPI05`, die Segmenthierarchie — der Baum, den WE30 zeigt —
kommt als `EDI_IAPI02`-Zeilen mit Vatersegment, Ebene, Muss-Kennzeichen und Wiederholbereich.
Gelesen wird in `EDI_IAPI01` und nach `EDI_IAPI05` umkopiert: die Schreibseite will genau die
sechs Felder, die einen Basistyp ausmachen, und Paket, Anleger und Zeitstempel fallen beim
Umkopieren von selbst weg.

**Geprüft wird über die API, nicht über `EDISYN`.** Dort steht nur die *freigegebene* Syntax;
ein frisch angelegter Basistyp ist nicht freigegeben, und die Tabelle bleibt leer, obwohl der
Typ vollständig ist. Das kostete einen Fehlalarm.

**Nachrichtenklassen** waren bis dahin dokumentiert, aber nicht anlegbar — sie standen in der
Objektliste und trugen keine Definitionsdaten. Ein Report, dessen Klasse im Zielsystem fehlt,
zeigt statt des Textes den nackten Schlüssel: `S:ZBLE_0001:006`.

Drei Punkte sind daran nicht offensichtlich:

- **Der Baustein ist unbrauchbar.** `RPY_MESSAGE_ID_INSERT` wäre die API, öffnet aber den Dialog
  „Objektkatalogeintrag anlegen" — auch mit `$TMP` als Paket. Ein unbeaufsichtigter Importlauf
  kann keinen Dialog beantworten; dieselbe Falle wie seinerzeit `RS_WORKING_OBJECT_ACTIVATE`.
  Geschrieben wird deshalb direkt in `T100A` und `T100`, wo SE91 die Klasse ohnehin ablegt, und
  der Katalogeintrag über denselben Helfer wie bei jedem anderen Objekttyp. Gelesen wird aus
  denselben Tabellen — ein Paar, das anders liest als es schreibt, ist keins.
- **Alle Sprachen, nicht die Ausgabesprache.** Dies sind Definitionsdaten, keine Beschreibung.
  Eine nur englisch gepflegte Klasse, in ein deutsches Dokument exportiert, käme sonst ohne eine
  einzige Nachricht an. Genau dieser Fall ist der Normalfall: gemessen an einer Kundenklasse mit
  194 Nachrichten, alle nur `EN`.
- **Bestehende Texte bleiben.** Fehlende Nummern und fehlende Sprachen werden ergänzt, schon
  vorhandene nicht angefasst. Sie können hier übersetzt oder korrigiert worden sein.

Die Klasse ist **kein** Sprachproblem: ist sie da, aber in der Anmeldesprache nicht gepflegt,
fällt die Laufzeit auf Englisch zurück. Auf S4H nachgemessen — `SY-LANGU` = DE, nur ein
`EN`-Text in `T100`, angezeigt wird der englische Text. Die Schlüsselform bedeutet immer, dass
Klasse oder Nummer überhaupt nicht da sind.

**Gefunden** wird eine Nachrichtenklasse aus dem Quelltext. Sie steht in keinem Querverweis-
index, und die beiden Formen, auf die es ankommt, sind nicht in Anführungszeichen — der
`MESSAGE-ID`-Zusatz des Programmkopfs und die Klammerform hinter der Nummer (`MESSAGE s006(zble_0001)`).
Die Literalsuche greift dort nicht.

**Nicht mitgenommen** wird `T100U`: wer eine Nummer angelegt hat und ob sie selbsterklärend
ist. Das erste ist systemspezifisch, das zweite betrifft nur, ob SE91 einen Langtext erwartet.

**Rückgabecodes der Aktivierung.** Die `DDIF_*_ACTIVATE`-Bausteine bewerten ihr Ergebnis: 0 ist
sauber, 4 heißt „aktiviert mit Warnung", ab 8 hat es nicht geklappt. Nur ab 8 bleibt das Objekt
inaktiv. Die 4 als Fehler zu behandeln hieße, den Lauf an einer Tabelle abzubrechen, die
einwandfrei benutzbar ist — und die Folgeschritte, etwa die Indizes, auszulassen.

Ab 8 nennt `act_reason( )` den wahrscheinlichen Grund, statt nur den Code zu melden: das Objekt,
auf dem das gescheiterte steht und das es nicht im **aktiven** Stand gibt — die Domäne unter
einem Datenelement, die Datenelemente unter Tabelle und View, höchstens drei. Ein inaktiv
angelegter Vorgänger trägt die Aktivierung nicht, deshalb wird gezielt nach `AS4LOCAL = 'A'`
gefragt. Ohne diese Angabe standen vier Fehlerzeilen im Protokoll — Datenelemente, Segment,
Basistyp — und die Ursache in keiner davon:

```
DTEL ZBLE_BALACTION   angelegt, inaktiv
     DDIF_DTEL_ACTIVATE rc 8 fehlt oder inaktiv: Domaene ZBLE_BALACTION_D
```

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

**Textelemente und Dokumentation** werden je Sprache geschrieben: ein `INSERT TEXTPOOL …
LANGUAGE` je Sprache, ein `DOCU_UPDATE` je `DOCU`-Zeile. Das Protokoll nennt beides mit Sprache
und Anzahl — `TEXT … Textelemente gesetzt D:5 E:8`, `DOKU … Dokumentation gesetzt Sprachen D`.
Ein Dokument aus einer älteren Fassung trägt weder `_SPRSL` noch `DOCU`-Zeilen; dann bleibt es
beim bisherigen Verhalten — Textpool in die Anmeldesprache, Dokumentationstext des Kapitels in
dessen Sprache. Nachgemessen mit einem Kundenreport als umbenannte Kopie in `$TMP`:
`REPOTEXT` D und E aktiv, `DOKHL` D aktiv.

**Auftrag und Aufgabe.** Ein Objekt landet nicht im Auftrag, sondern in einer Aufgabe darunter,
und eine freigegebene nimmt nichts mehr auf. Fehlt eine offene Aufgabe für den Anmeldebenutzer,
fragt das Korrektursystem im Dialog nach. Ohne Dialog lehnt es ab — bei
`SEO_*_CREATE_COMPLETE` mit `NO_ACCESS` (5), was nach Berechtigung aussieht. Die eigentliche
Meldung lautet *No matching task exists under request … for user …*.

`FORM ensure_task` prüft deshalb vor dem Lauf, ob unter `P_ITR` eine Aufgabe des Benutzers im
Status `D` oder `L` steht, und legt sie sonst über `TR40_TASK_ADD` an. Der Baustein ist
dialogfrei. Angelegt wird nur unter dem Auftrag vom Bild und nie im Testlauf. Wer `P_ITASK`
abwählt, bekommt vor dem Lauf eine Warnung statt eines Abbruchs mittendrin; wer gleich eine
Aufgabe einträgt, wird erkannt und in Ruhe gelassen.

**`COMMIT WORK AND WAIT`.** Der Korrektursystem-Teil läuft über die Verbuchung; Auftragseintrag
und Aufgabe entstehen erst mit dem Commit. Ohne ihn meldete der Lauf eine angelegte Aufgabe, und
im Transport Organizer stand keine. Committet wird am Ende des Laufs, vor der Prüfung nach dem
Lauf, und nur außerhalb des Testlaufs.

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

Zu einem Fehler gehören **der echte Rückgabecode und die SAP-Meldung**. Beides war nicht
selbstverständlich:

- ABAP wertet die Parameter eines Methodenaufrufs in der Reihenfolge der **Schnittstelle** aus,
  nicht der des Quelltexts. In `log( )` steht `iv_action` vor `iv_text`; `lcl_t=>ui( )` läuft
  also zuerst und setzt `sy-subrc` zurück, bevor das String-Template ihn liest. Gemeldet wurde
  durchgehend `subrc 0` — in einem Zweig, den man nur mit einem Wert ungleich 0 erreicht. Auf
  S4H nachgestellt: 4 vor dem Aufruf, 0 im Text. Der Code wird jetzt unmittelbar nach dem
  Aufruf in eine Variable gemerkt, an 19 Stellen. Die Reihenfolge im Aufruf zu tauschen hilft
  nicht.
- Die gerufenen Bausteine setzen vor ihrem `RAISE` eine Meldung ab (`MESSAGE … RAISING`). Sie
  steht in `SY-MSGID`, `SY-MSGNO` und `SY-MSGV1..4`, wird aus demselben Grund sofort gelesen
  (`last_message( )`) und an die Fehlerzeile gehängt. Eine `5` sagt nicht, ob Berechtigung,
  Sperre oder Korrektursystem; die Meldung schon.

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

### 5.7 Paket beim Import

Bis hierher landete beim Import alles in **einem** Zielpaket. Das Quellpaket steht dabei längst
im Dokument — der Export schreibt es in die Objektreferenz —, es wurde beim Import nur nicht
gelesen.

Vier Regelzeilen **alt → neu** und ein Kennzeichen *Quellpaket beibehalten* ändern das. Die
Reihenfolge je Objekt:

1. eine Regel auf das Quellpaket
2. sonst das Quellpaket selbst, wenn `P_IKEEP` gesetzt ist
3. sonst `P_IPACK` — das bisherige Verhalten, unverändert als Vorbelegung

Umgesetzt über `set_pack( )`, das vor jedem Objekt `mv_pack` und `mv_tr` umsetzt. Die rund
zwanzig Stellen, die `mv_pack` lesen, bleiben dadurch unberührt; die Eingabe vom Bild steht in
`mv_pack0` und `mv_tr0`.

Zwei Dinge hängen daran:

- **Ein Paket, das es im Zielsystem nicht gibt, wird nicht angelegt.** Das ist eine
  Entscheidung, die dem Entwickler gehört. Es bleibt beim Zielpaket vom Bild, und das
  Protokoll sagt warum.
- **Der Auftrag hängt am Paket dieses Objekts, nicht an der Eingabe.** Ein lokales Paket kennt
  keinen Auftrag, ein transportfähiges braucht einen. Wer `$TMP` nach `ZBLE_WM` umlenkt,
  bekommt den Auftrag also auch dann angehängt, wenn `P_IPACK` lokal war — sonst liefe der
  Import in die Auftragsabfrage.

Gemeldet wird eine Zeile je Regel, nicht je Objekt.

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

### 6.1 Dateiname

`P_FNAME` trägt den Dateinamen **ohne Endung**: XML und HTML entstehen aus demselben Lauf und
unterscheiden sich nur darin. Derselbe Name gilt für den PC-Download und für die Serverablage.

Vorbelegt wird er aus Systemkürzel, Startobjekt, Datum und Uhrzeit —
`documizer_dev_S4H_zscantestv2_20260901_083000`. Der Objektname ist neu: bisher hießen alle
Dokumente eines Systems gleich und ließen sich in einem Verzeichnis nur am Zeitstempel
unterscheiden.

Der Vorschlag wird bei **jedem Bildaufbau** neu gebildet, damit er dem Startobjekt folgt. Wer
den Objektnamen ändert, sieht den Dateinamen sofort mitwandern. Überschrieben wird das Feld
aber nur, solange darin noch genau der vorige Vorschlag steht; ein selbst gewählter Name
bleibt. Der Report merkt sich den zuletzt selbst gebildeten Wert dafür in einer eigenen
Variablen — der Vergleich gegen das Feld allein würde einen von Hand eingetragenen Namen beim
nächsten Enter wieder wegwerfen.

Zwei Randfälle:

- **Namensräume.** Ein Objektname wie `/BOBF/OBJ` bringt Schrägstriche mit, und die trennen im
  Dateisystem Verzeichnisse. Sie werden zu Unterstrichen.
- **Hintergrund und `SUBMIT`.** Dort läuft kein PBO, das den Vorschlag gefüllt hätte. Ist das
  Feld leer, bildet der Report den Namen beim Schreiben selbst — eine Datei ohne Namen darf
  daraus nicht werden.

Bei der Arbeitsliste (`P_STYPE = AL`) entfällt der Objektteil: es gibt kein einzelnes
Startobjekt. Im IMG-Report tritt an dessen Stelle die Struktur-ID, ersatzweise das Projekt;
der Suchbegriff bleibt draußen, denn er ist Prosa und kein Name.

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

Hinzugekommen sind zwei Zugriffe je Objekt: die Feldverwendungen sind ein zweiter `LIKE`-Scan
über `WBCROSSGT` je Tabelle oder Struktur, gedeckelt durch `P_MAXUSE`; und je Klasse wird der
`CCIMP`-Include gelesen, um die lokalen Klassen zu finden.

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
| 7e | Reimport: UI5-Anwendungen über die Repository-API | erledigt |
| 7f | Reimport: IDoc-Segmenttypen und -Basistypen | erledigt |
| 7g | BC-Set aus Dokument (`SCPR_PRSET_DB_SAVE_ORIG_TABLES`) | erledigt |
| 7h | Fehlliste im IMG-Report, Arbeitsliste im DEV-Report | erledigt |
| 7i | Pflegeapparat: Dynpros, `TVDIR`, Transaktion, View-Cluster | erledigt |
| 7j | Dateiname vorgebbar (`P_FNAME`) | erledigt |
| 7k | Basistyp zieht seine Segmenttypen nach | erledigt |
| 7l | Paket beim Import umlenkbar (`P_IKEEP`, Regeln) | erledigt |
| 7m | `ZDOCUMIZER_ATC`: Prüfkonfiguration dokumentieren | erledigt |
| 7n | Importprotokoll: echter Rückgabecode, SAP-Meldung, Grund der gescheiterten Aktivierung | erledigt |
| 7o | Import: Aufgabe unter dem Auftrag anlegen, `COMMIT WORK AND WAIT` | erledigt |
| 7p | IDoc-Basistyp: WE60, WE82, WE57; Datenelemente der Segmente aus `EDSAPPL` | erledigt |
| 7q | Verwendungsnachweis: Feldverwendungen, `P_USEALL` | erledigt |
| 7r | CDS-/RAP-Schicht: Kurztexte, Quelltext, Feldlisten; Klassenbeziehungen, lokale Klassen | erledigt |
| 7s | Textelemente und Objektdokumentation je Sprache übertragen; gelöschte Katalogeinträge übergehen | erledigt |
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
8. **Vorhandene Dynpros überschreiben** — `RPY_DYNPRO_INSERT` lehnt ein bestehendes Bild ab,
   und einen dialogfreien Weg zum Ersetzen gibt es nicht. Beim Nachliefern geänderter Bilder
   bleibt nur SE51.
9. **Pflegeeintrag im Transportauftrag** — `TVDIR`, `TVIMF` und `TDDAT` werden lokal
   geschrieben. Sie in den Auftrag zu hängen hieße, Tabellenschlüssel als `E071K` einzutragen;
   das ist noch nicht umgesetzt.
10. **IDoc-Erweiterungstypen (CIMTYPE)** — `IDOCTYPE_READ` kennt nur `PI_IDOCTYP`;
    Erweiterungen brauchen ein eigenes Paar Bausteine und einen eigenen Startpunkt-Typ.
11. **Fehlende Pakete beim Import anlegen** — eine Paketregel auf ein Paket, das es im
    Zielsystem nicht gibt, greift nicht. Das Anlegen wäre ein eigenes Kennzeichen wert.
12. **Objektdokumentation weiterer Typen übertragen** — gelesen wird sie für Report,
    Transaktion, Datenelement, Baustein und Nachrichtenklasse, übertragen nur für Report und
    Datenelement.
13. **`STOB` als eigenes Kapitel** — im Paketmodus steht das Strukturobjekt einer CDS-View als
    eigenes Kapitel neben seiner DDL-Quelle, mit demselben Text. Es entsteht beim Aktivieren von
    selbst und bräuchte keins.
14. **Lokale Klassen zeilenweise erkannt** — eine über zwei Zeilen umbrochene
    `CLASS … DEFINITION` wird nicht gefunden, und bei `METHODS: a, b.` nur die erste Methode der
    Zeile.
15. **Die Umgebung einer Fiori-Anwendung** — die UI5-Anwendung selbst reist mit, das Drumherum
    nicht: der **ICF-Knoten** (`SICF`), die **MIME-Objekte** (`SMIM`) und die
    **Gateway-Registrierung** des OData-Service (`IWSV`, `IWMO`, `IWVB`). Sie stehen mit Namen im
    Dokument, angelegt werden sie nicht; im Zielsystem bleiben SICF und
    `/IWFND/MAINT_SERVICE` Handarbeit. Aufgefallen an einem Paketlauf mit vier `SICF`-Knoten,
    zwei `SMIM`-Objekten und drei Gateway-Einträgen.
16. **Berechtigungsvorschlagswerte (`SUSH`)** — stehen als Objekt im Dokument, aber ohne Inhalt
    und ohne Weg ins Zielsystem. Gepflegt werden sie in SU22/SU24.
