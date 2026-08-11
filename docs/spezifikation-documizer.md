# Spezifikation: Documizer — IMG- und Entwicklerdokumentationsreports

**Stand:** 11.08.2026
**Grundlage:** [Recherche](recherche-img-und-entwicklerdoku.md)
**Zielsystem:** S/4HANA On-Premise, SAP_BASIS 758, klassisches ABAP

## 1. Rahmenbedingungen

Aus der Abstimmung festgelegt:

| Punkt | Entscheidung |
|---|---|
| Deployment | **On-Premise** (kein Public Cloud, `SPRO` verfügbar) |
| Programmiermodell | **Klassisches ABAP** (freier `TADIR`-/DDIC-Zugriff, `DOCU_GET` nutzbar) |
| Reimport | **Phase 2**; Rückschreiben über **BC-Sets** (Customizing) und **abapGit** (Repository-Objekte) statt Eigenbau |
| Mengengerüst | Filter und Mengengrenzen als Selektionsparameter; **Vollexport ganzer Tabellen muss möglich sein** |
| Ausgabeformate | **XML** (führend, transportabel) + **HTML oder Markdown** (lesbar) |

### 1.1 Phasenschnitt

- **Phase 1** — beide Reports, Export nach XML und HTML/MD, Reimport nur als *Anzeige/Rendern*
  der XML-Datei.
- **Phase 2** — Rückschreiben ins System: Customizing über BC-Sets (`SCPR3`/`SCPR20`),
  Repository-Objekte über abapGit. Der Documizer erzeugt bzw. konsumiert dabei deren Formate,
  statt eigene Schreiblogik aufzubauen.

Diese Aufteilung vermeidet Doppelentwicklung: BC-Sets und abapGit lösen das Zurückschreiben
bereits vollständig und sind im Fehlerfall belastbarer als eine Eigenentwicklung.

---

## 2. Architektur

### 2.1 Gemeinsames Rahmenwerk

Beide Reports haben denselben Ablauf. Nur der Collector unterscheidet sich.

```
Selektionsbild
     │
     ▼
┌──────────────────┐     ┌──────────────────────────┐
│  Collector       │────▶│  Kapitelmodell (generisch)│
│  IMG | Package   │     │  ZCL_DOCU_CHAPTER         │
└──────────────────┘     └────────────┬─────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              XML (ST-Trafo)      HTML            Markdown
```

### 2.2 Klassen

| Klasse / Interface | Aufgabe |
|---|---|
| `ZIF_DOCU_COLLECTOR` | Schnittstelle: `COLLECT` liefert Kapitelbaum |
| `ZCL_DOCU_COLLECTOR_IMG` | IMG-Collector |
| `ZCL_DOCU_COLLECTOR_PACKAGE` | Paket-Collector |
| `ZCL_DOCU_CHAPTER` | Kapitelknoten (Baum, generisch) |
| `ZCL_DOCU_CONTENT_BLOCK` | Inhaltsblock innerhalb eines Kapitels |
| `ZIF_DOCU_RENDERER` | Schnittstelle: `RENDER` liefert Datei-Inhalt |
| `ZCL_DOCU_RENDERER_XML` | Export/Import über Simple Transformation |
| `ZCL_DOCU_RENDERER_HTML` | HTML mit Inhaltsverzeichnis |
| `ZCL_DOCU_RENDERER_MD` | Markdown |
| `ZCL_DOCU_FILE_SERVICE` | Ablage: Frontend (`GUI_DOWNLOAD`), Applikationsserver, optional MIME-Repository |

Reports: `ZDOCU_IMG` und `ZDOCU_PACKAGE`, beide dünn — nur Selektion und Aufruf.

Paketvorschlag: `ZCONS_DOCUMIZER` mit Unterpaketen `..._CORE`, `..._IMG`, `..._DEV`.
Im System existiert bereits `ZCONS_DOC_EXTRACTION` — vor Anlage prüfen, ob dort angedockt wird.

### 2.3 Grundsätze

1. **Standard-APIs verwenden**, nicht direkt selektieren. `STREE_*`, `S_CUS_IMG_ACTIVITY_*`,
   `CL_PAK_PACKAGE_QUERIES`. Die Tabellen aus der Recherche dienen dem Verständnis und dem
   gezielten Nachschlagen, nicht als primärer Zugriffsweg.
2. **Keine systemspezifischen Felder im Export.** Erzeuger, Zeitstempel, Transportkennzeichen und
   Mandant gehören nicht in die XML-Nutzdaten, sondern ausschließlich in den Kopfbereich
   (`<meta>`). Sonst ist ein Vergleich DEV/QAS/PRD wertlos. Prinzip von abapGit übernommen.
3. **Sprache ist Parameter**, Voreinstellung `sy-langu`, mit Rückfall auf EN, wenn kein Text in
   der Anforderungssprache existiert.

---

## 3. Report A — IMG-/Customizing-Dokumentation (`ZDOCU_IMG`)

### 3.1 Selektionsbild

**Block: Bereichsauswahl**

| Parameter | Typ | Bedeutung |
|---|---|---|
| `P_TREEID` | `TTREE-ID` | Struktur-GUID; Vorschlag über Wertehilfe auf Referenz-IMG |
| `P_NODE` | `HIER_GUID` | Startknoten (leer = Wurzel) |
| `P_PROJ` | `CUS_PROJ` | Alternativ: Projekt-IMG (`CUSPR`/`CUSPV`) |
| `P_SCOPE` | Checkbox | Nur Knoten mit `IN_SCOPE` |
| `P_DEPTH` | `I` | Maximale Tiefe, 0 = unbegrenzt |

**Block: Ausprägungsfilter**

`S_LAND` (Länder), `S_BRANCH` (Branchen), `S_REL` (Releases) — wirken über die
Ein-/Ausschlusstabellen `TTREECOUIN`/`EX`, `TTREEBRAIN`/`EX`, `TTREERELIN`/`EX`.

**Block: Inhaltsumfang**

| Parameter | Vorbelegung | Bedeutung |
|---|---|---|
| `P_DOKU` | X | SAP-Standarddokumentation übernehmen |
| `P_OBJ` | X | Zugeordnete Customizing-Objekte ermitteln |
| `P_DATA` | X | Customizing-**Inhalte** lesen |
| `P_CUSTOM` | X | Nur kundeneigene Einträge (siehe 3.4) |
| `P_MAXROW` | 500 | Maximale Zeilen je Tabelle, **0 = alle** |
| `P_META` | | Nur Metadaten, keine Inhalte |

**Block: Ausgabe**

`P_XML`, `P_HTML`, `P_MD` (Mehrfachauswahl), `P_PATH`, `P_LANGU`.

### 3.2 Ablauf

1. **Struktur lesen** — `STREE_HIERARCHY_READ` mit `STRUCTURE_ID` = `P_TREEID`,
   `READ_ALSO_TEXTS = 'X'`. Ergebnis: `LIST_OF_NODES` (`HIER_IFACE`), `LIST_OF_TEXTS`,
   `LIST_OF_REFERENCES`.
2. **Teilbaum eingrenzen** — ab `P_NODE` über `PARENT_ID` absteigen. Die Geschwisterreihenfolge
   ergibt sich aus der `BROTHER_ID`-Kette und **muss** verfolgt werden; eine Sortierung nach GUID
   liefert eine falsche Kapitelreihenfolge.
3. **Filter anwenden** — Ausprägung, Scope, Tiefe.
4. **Knoten klassifizieren:**
   - Knoten ohne `COBJ`-Verweis → **Gliederungskapitel**, Titel aus `TNODEIMGT`
   - Knoten mit `COBJ`-Verweis → **Aktivitätskapitel**
5. **Je Aktivitätskapitel anreichern:**
   - Aktivität aus `TNODEIMGR-REF_OBJECT` (`REF_TYPE = 'COBJ'`)
   - Kopfdaten über `S_CUS_IMG_ACTIVITY_READ` (`DOCU_ID`, `TCODE`)
   - Titel über `S_CUS_IMG_ACT_GET_DESC` bzw. `CUS_IMGACT`
   - Standarddoku über `DOCU_GET` mit **`id = 'HY'`**, `object = DOCU_ID`
   - Objektzuordnung über `S_CUS_IMG_ACTIVITY_GET_OBJECTS` bzw. `CUS_ACTOBJ`
6. **Customizing-Inhalte lesen** — siehe 3.3.
7. **Kapitelbaum an Renderer übergeben.**

### 3.3 Customizing-Inhalte

`CUS_ACTOBJ-OBJECTTYPE` steuert die Auflösung:

| Typ | Bedeutung | Vorgehen |
|---|---|---|
| `V` | View | View-Definition (`DD25L`/`DD27S`) → Basistabellen → Daten lesen |
| `C` | View-Cluster | Cluster auflösen (`VCLDIR`/`VCLSTRUC`) → enthaltene Views je einzeln |
| `T` | Tabelle | direkt lesen |
| `S` | Sicht/Pflegedialog | wie `V` |

Je Objekt werden ausgegeben: technischer Name, Kurztext, Feldliste mit Datenelement und
Feldbezeichner, Schlüsselkennzeichen sowie die Dateninhalte gemäß Mengensteuerung.

### 3.4 Mengensteuerung

Der Punkt entscheidet über die Brauchbarkeit. Customizing-Tabellen reichen von drei Zeilen
(`T001`-Ausprägungen) bis zu Millionen (Konditionen).

Vierstufig:

1. **`P_META` = X** → nur Struktur, keine Daten. Immer verwendbar, auch beim Vollausbau.
2. **`P_CUSTOM` = X** → nur kundeneigene Einträge. Ermittlung über den Namensraum des
   Schlüsselfelds (Kundennamensraum) bzw. über `E071K`-Auswertung der Transportaufträge des
   Mandanten. Fällt auf „alle Einträge" zurück, wenn keine Eingrenzung möglich ist — das wird
   im Protokoll vermerkt, nicht stillschweigend gemacht.
3. **`P_MAXROW`** → harte Obergrenze je Tabelle. Wird sie erreicht, erscheint im Dokument ein
   sichtbarer Hinweis mit Gesamtzeilenzahl (`SELECT COUNT(*)`), damit im Dokument nie der
   Eindruck von Vollständigkeit entsteht, wo abgeschnitten wurde.
4. **`P_MAXROW` = 0** → Vollexport. Zulässig und ausdrücklich gewünscht, aber:
   - Verarbeitung paketweise (`PACKAGE SIZE 10000`), Ergebnis strömend in die Datei schreiben,
     nicht komplett im Hauptspeicher halten
   - Ab geschätzt > 100.000 Zeilen Gesamtumfang **Hinweis mit Abbruchmöglichkeit** im Dialog;
     im Hintergrundbetrieb nur Protokolleintrag
   - Empfehlung im Selektionsbild: Vollexport im Hintergrund einplanen

### 3.5 Kapitelaufbau

```
1  <Wurzelknoten>                          Gliederungskapitel
   1.1 <Unterknoten>                       Gliederungskapitel
       1.1.1 <IMG-Aktivität>               Aktivitätskapitel
             ├─ Beschreibung               aus DOCU_GET (Klasse HY)
             ├─ Technische Zuordnung       Aktivität, TCode, Objekttyp/-name
             ├─ Struktur des Objekts       Feldliste
             └─ Customizing-Inhalt         Daten gemäß Mengensteuerung
```

---

## 4. Report B — ABAP-Paket-/Entwicklerdokumentation (`ZDOCU_PACKAGE`)

### 4.1 Selektionsbild

| Parameter | Typ | Bedeutung |
|---|---|---|
| `P_PACK` | `TDEVC-DEVCLASS` | Startpaket (Pflicht) |
| `P_RECUR` | Checkbox, X | Unterpakete rekursiv |
| `P_DEPTH` | `I` | Maximale Pakettiefe, 0 = unbegrenzt |
| `S_OBJTYP` | Select-Option | Objekttypen (`PROG`, `CLAS`, `FUGR`, `TABL`, `DDLS`, `INTF`, `DTEL`, `DOMA`, …) |
| `S_OBJNAM` | Select-Option | Objektnamensfilter |
| `P_SRC` | Checkbox | Quelltext mit ausgeben |
| `P_DOKU` | Checkbox, X | Objektdokumentation und ABAP Doc |
| `P_USED` | Checkbox | Verwendungsnachweis (teuer, daher aus) |

### 4.2 Ablauf

1. **Pakete ermitteln** — `CL_PAK_PACKAGE_QUERIES=>GET_ALL_SUBPACKAGES`. Kein Eigenbau der
   Rekursion; die Methode liefert den kompletten Unterbaum und behandelt Zyklen.
2. **Paketattribute** — `GET_PACKAGE_ATTRIBUTES` bzw. `GET_MULTI_PACKAGE_ATTRIBUTES`
   (Beschreibung, Softwarekomponente, Transportschicht, Sichtbarkeit).
3. **Objekte je Paket** — `GET_DEV_OBJECT_TADIR_KEYS`, gefiltert über `S_OBJTYP`/`S_OBJNAM`.
4. **Typspezifisch aufbereiten** — siehe 4.3.
5. **Kapitelbaum bilden** — Pakethierarchie = Kapitelhierarchie, Objekttypen als Untergliederung.

### 4.3 Aufbereitung je Objekttyp

| Typ | Inhalt |
|---|---|
| `PROG` | Titel, Typ, Selektionsparameter mit Texten, Includes, Textelemente, Objektdoku, optional Quelltext |
| `CLAS` | Oberklasse, Interfaces, Sichtbarkeiten, Methodensignaturen, Attribute, Events, ABAP Doc je Methode |
| `INTF` | Methodensignaturen, Konstanten, ABAP Doc |
| `FUGR` | Bausteinliste, je Baustein Schnittstelle (`FUPARAREF`) und Objektdoku |
| `TABL` | Feldliste mit Datenelement/Domäne, Schlüssel, Fremdschlüssel, Indizes, technische Einstellungen, Auslieferungsklasse |
| `DDLS` | CDS-Quelltext, Annotationen, Assoziationen, Abhängigkeiten, verwendete Basisobjekte |
| `DTEL`/`DOMA` | Datentyp, Länge, Feldbezeichner, Festwerte, Wertehilfe |
| `TRAN` | Transaktionstyp, Startobjekt, Berechtigungsobjekt |

CDS ist bei `abapDoc` nicht abgedeckt und damit ein echter Mehrwert dieser Entwicklung — in
einem S/4HANA-System der wichtigste Objekttyp überhaupt.

### 4.4 Kapitelaufbau

```
1  Paket <Startpaket>
   1.1 Paketübersicht                      Attribute, Objektstatistik
   1.2 Klassen
       1.2.1 ZCL_...                       Signaturen, ABAP Doc
   1.3 Tabellen und Strukturen
   1.4 CDS Views
   1.5 Funktionsgruppen
   1.6 Programme
2  Paket <Unterpaket 1>
   …
```

---

## 5. XML-Format und Roundtrip

### 5.1 Grundsatz

Serialisierung über eine **eigene Simple Transformation** (`ZDOCU_ST`), nicht über die
`id`-Transformation. `id` bildet ABAP-interne Typen ab, erzeugt schwer lesbares XML und bricht bei
jeder Feldänderung den Reimport.

### 5.2 Aufbau

```xml
<documizer version="1.0" type="IMG">
  <meta>
    <system>S4H</system>
    <client>100</client>
    <created_at>2026-08-11T10:00:00</created_at>
    <created_by>GATHMANN</created_by>
    <language>DE</language>
    <selection>
      <tree_id>...</tree_id>
      <node_id>...</node_id>
      <max_rows>500</max_rows>
      <customer_only>X</customer_only>
    </selection>
  </meta>
  <chapters>
    <chapter id="1" level="1" type="STRUCTURE">
      <title>Finanzwesen</title>
      <chapter id="1.1" level="2" type="ACTIVITY">
        <title>Steuerkennzeichen definieren</title>
        <reference>
          <activity>SIMG_CFMENUORFBOBDI</activity>
          <docu_id>SIMGSIMG_CFMENUORFBOBDI</docu_id>
          <tcode>OBDI</tcode>
        </reference>
        <documentation format="ITF"><![CDATA[ ... ]]></documentation>
        <customizing_object type="V" name="V_T007Z">
          <structure>
            <field name="MANDT" key="X" rollname="MANDT"/>
            <!-- ... -->
          </structure>
          <data row_count="42" truncated="false">
            <row><f n="MANDT">100</f><!-- ... --></row>
          </data>
        </customizing_object>
      </chapter>
    </chapter>
  </chapters>
</documizer>
```

Für `type="DEV"` bleibt `meta` und `chapters` identisch; unterschiedlich sind nur die
Inhaltsblöcke (`<object type="CLAS">` statt `<customizing_object>`).

### 5.3 Regeln

- **Attribut `version`** von Anfang an. Ohne Versionskennzeichen ist eine spätere Formatänderung
  nicht mehr sauber behandelbar.
- **`truncated`-Kennzeichen** an jedem Datenblock, zusammen mit `row_count`. Ein Dokument darf nie
  unbemerkt unvollständig sein.
- **Dokumentation als CDATA** im ITF-Rohformat, plus Umsetzung nach HTML/MD beim Rendern. So
  bleibt der Reimport verlustfrei.
- **Keine Zeitstempel oder Benutzer in den Kapiteldaten** — ausschließlich in `<meta>`.

### 5.4 Reimport Phase 1

`ZDOCU_IMPORT` liest die XML-Datei über dieselbe ST zurück in das Kapitelmodell und rendert sie
nach HTML/MD. Kein Systemzugriff, damit auch außerhalb des Ursprungssystems verwendbar — z. B. um
den Stand aus PRD in DEV zu betrachten.

### 5.5 Reimport Phase 2

- **Customizing:** aus dem Kapitelbaum eine BC-Set-Definition erzeugen (`SCPR3`) und über die
  Standardfunktionen einspielen. Der Documizer schreibt nicht selbst in Customizing-Tabellen.
- **Repository-Objekte:** abapGit-Serialisierung nutzen; der Documizer liefert die Dokumentation,
  abapGit den Code.

Bewusste Abgrenzung: Schreibende Zugriffe auf Customizing und Repository bleiben bei den
Standardwerkzeugen. Das hält den Documizer auf der Leseseite und damit risikoarm.

---

## 6. HTML- und Markdown-Ausgabe

**HTML:** eine in sich geschlossene Datei ohne externe Abhängigkeiten (CSS eingebettet),
Inhaltsverzeichnis mit Sprungmarken, nummerierte Kapitel, Datentabellen mit fixierter Kopfzeile,
druckfreundlich. Kein JavaScript — die Datei soll auch in Jahren noch öffnen.

**Markdown:** ATX-Überschriften entsprechend Kapitelebene, Pipe-Tabellen für Daten, Quelltext in
Codefences mit Sprachkennzeichen `abap`. Geeignet für Ablage in Git oder Confluence-Import.

Beide entstehen aus demselben Kapitelmodell, nicht aus dem XML — das vermeidet einen zweiten
Parserpfad.

---

## 7. Berechtigungen und Betrieb

- Berechtigungsprüfung `S_TABU_DIS`/`S_TABU_NAM` je gelesener Tabelle. Ein Dokumentationsreport
  darf keine Leseberechtigungen umgehen. Nicht lesbare Tabellen werden mit Vermerk übersprungen,
  nicht stillschweigend ausgelassen.
- `S_DEVELOP` (Aktivität 03) für den Development-Report.
- Vollexporte und größere Läufe im Hintergrund; Ablage dann auf dem Applikationsserver.
- Anwendungsprotokoll (`BAL`) mit: gelesene Knoten/Objekte, übersprungene wegen Berechtigung,
  abgeschnittene Tabellen, Laufzeit.

---

## 8. Umsetzungsschritte

| Schritt | Inhalt | Ergebnis |
|---|---|---|
| 1 | Paket, Kapitelmodell, `ZIF_DOCU_COLLECTOR`, `ZIF_DOCU_RENDERER` | Gerüst |
| 2 | Simple Transformation + XML-Renderer + Reimport | Roundtrip nachweisbar |
| 3 | IMG-Collector ohne Dateninhalte (`P_META`) | Kapitelstruktur mit Doku |
| 4 | Customizing-Inhalte inkl. Mengensteuerung | Report A vollständig |
| 5 | Paket-Collector, Objekttypen schrittweise | Report B |
| 6 | HTML- und MD-Renderer | Lesbare Ausgabe |
| 7 | Protokoll, Berechtigungen, Hintergrundbetrieb | Produktivreife |

Schritt 2 vor Schritt 3: Der Roundtrip ist die Anforderung mit dem höchsten Risiko und dem
größten Einfluss auf das Datenmodell. Er sollte an einem kleinen Beispiel stehen, bevor die
Collector-Logik daraufhin gebaut wird.

## 9. Offene Punkte

1. **Ablageort der Exporte** — Frontend, Applikationsserver oder beides? Bei Hintergrundverarbeitung
   ist Frontend-Download nicht möglich; Vorschlag: beides, gesteuert über `P_PATH`.
2. **Kundeneigene Einträge erkennen** — die Ermittlung über Namensraum funktioniert nicht bei
   Tabellen mit numerischen oder technischen Schlüsseln. Alternative über `E071K` ist genauer,
   erfasst aber nur transportiertes Customizing. Vorschlag: beide Verfahren anbieten, Vorbelegung
   Namensraum, Verfahren im Protokoll und im Dokument ausweisen.
3. **Mandantenabhängiges Customizing** — Vollexport bezieht sich auf den Anmeldemandanten.
   Mandantenübergreifendes Customizing ist gesondert zu kennzeichnen.
4. **Bestehendes Paket `ZCONS_DOC_EXTRACTION`** — Überschneidung prüfen, bevor ein neues Paket
   angelegt wird.
