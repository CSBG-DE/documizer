REPORT zdocumizer_docu.

************************************************************************
* consiness Documizer - Reportdokumentation erzeugen
*
* Legt die SAP-Reportdokumentation zu ZDOCUMIZER_IMG und ZDOCUMIZER_DEV
* an. Dokumentationsobjekte sind eigene Repository-Objekte und kommen beim
* Kopieren des Quelltextes nicht mit; dieser Report erzeugt sie im
* Zielsystem neu.
*
* Nach dem Lauf erscheint der Text in SE38 unter Dokumentation und ueber
* die Sprungmarke im Selektionsbild.
*
* Copyright 2026 consiness GmbH
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
************************************************************************

CLASS lcl_docu DEFINITION.
  PUBLIC SECTION.
    METHODS run.
  PRIVATE SECTION.
    DATA mt_line TYPE STANDARD TABLE OF tline.
    METHODS a IMPORTING iv_f TYPE tdformat
                        iv_t TYPE tdline OPTIONAL.
    METHODS save IMPORTING iv_prog TYPE syrepid.
    METHODS build_img.
    METHODS build_dev.
ENDCLASS.

CLASS lcl_docu IMPLEMENTATION.

  METHOD a.
    APPEND VALUE tline( tdformat = iv_f tdline = iv_t ) TO mt_line.
  ENDMETHOD.

  METHOD save.

    DATA ls_head TYPE thead.

    ls_head-tdid       = 'RE'.
    ls_head-tdspras    = 'D'.
    ls_head-tdname     = iv_prog.
    ls_head-tdobject   = 'DOKU'.
    ls_head-tdform     = 'S_DOCU_SHOW'.
    ls_head-tdstyle    = 'S_DOCUS1'.
    ls_head-tdlinesize = 72.

    CALL FUNCTION 'DOCU_UPDATE'
      EXPORTING
        head    = ls_head
        state   = 'A'
        typ     = 'E'
        version = '0001'
      TABLES
        line    = mt_line.

    WRITE: / iv_prog, lines( mt_line ), 'Zeilen, subrc', sy-subrc.

  ENDMETHOD.

  METHOD build_img.

    CLEAR mt_line.

    a( iv_f = 'U1' iv_t = 'Verwendung' ).
    a( iv_f = 'AS' iv_t = 'Der Report liest einen Strukturbaum des Einfuehrungsleitfadens, ordnet' ).
    a( iv_f = '=' iv_t = 'den Knoten die zugehoerigen IMG-Aktivitaeten zu und erzeugt daraus eine' ).
    a( iv_f = '=' iv_t = 'kapitelweise gegliederte Dokumentation.' ).
    a( iv_f = 'AS' iv_t = 'Je Aktivitaet werden die SAP-Standarddokumentation, die zugeordneten' ).
    a( iv_f = '=' iv_t = 'Customizing-Objekte und auf Wunsch deren Inhalte aufgenommen.' ).
    a( iv_f = 'AS' iv_t = 'Die Ausgabe erfolgt als XML und als HTML. Das XML kann vom Report' ).
    a( iv_f = '=' iv_t = 'wieder eingelesen werden.' ).

    a( iv_f = 'U1' iv_t = 'Voraussetzungen' ).
    a( iv_f = 'AS' iv_t = 'Leseberechtigung fuer die auszuwertenden Tabellen (S_TABU_NAM). Fehlt' ).
    a( iv_f = '=' iv_t = 'sie, erscheint das betroffene Objekt mit einem Vermerk im Dokument.' ).
    a( iv_f = 'AS' iv_t = 'Fuer Download und Anzeige im Browser ist Dialogbetrieb erforderlich.' ).
    a( iv_f = '=' iv_t = 'Im Hintergrund steht nur die Ablage auf dem Applikationsserver zur' ).
    a( iv_f = '=' iv_t = 'Verfuegung.' ).

    a( iv_f = 'U1' iv_t = 'Selektion' ).
    a( iv_f = 'AS' iv_t = 'Auswahl der Struktur' ).
    a( iv_f = 'B1' iv_t = 'Struktur-ID: Einstiegsstruktur. Die Wertehilfe zeigt die Wurzelknoten' ).
    a( iv_f = '=' iv_t = 'mit Text, Knotenzahl, Strukturtyp und Aenderungsdatum.' ).
    a( iv_f = 'B1' iv_t = 'Suchbegriff Wurzel: ohne Struktur-ID laeuft der Report im Suchmodus und' ).
    a( iv_f = '=' iv_t = 'listet passende Strukturen auf. Wirkt zusaetzlich als Filter der' ).
    a( iv_f = '=' iv_t = 'Wertehilfe.' ).
    a( iv_f = 'B1' iv_t = 'Projekt: ueberlagert den Baum mit Status, Fortschritt und Memo aus' ).
    a( iv_f = '=' iv_t = 'einem IMG-Projekt.' ).
    a( iv_f = 'B1' iv_t = 'Nur Projektknoten: beschneidet auf die im Projekt bearbeiteten Knoten.' ).
    a( iv_f = '=' iv_t = 'In diesem Fall wird der Einstieg aus den Projektdaten abgeleitet, die' ).
    a( iv_f = '=' iv_t = 'Struktur-ID und die Kapitelgrenze wirken nicht.' ).

    a( iv_f = 'AS' iv_t = 'Umfang' ).
    a( iv_f = 'B1' iv_t = 'Max. Tiefe und Max. Kapitel begrenzen den Baum. Null bedeutet ohne' ).
    a( iv_f = '=' iv_t = 'Begrenzung.' ).
    a( iv_f = 'B1' iv_t = 'Unterstrukturen aufloesen: im IMG sind die Unterkapitel Verweise auf' ).
    a( iv_f = '=' iv_t = 'eigenstaendige Strukturen. Ohne Aufloesung endet der Lauf nach der' ).
    a( iv_f = '=' iv_t = 'ersten Ebene und findet keine Aktivitaeten.' ).
    a( iv_f = 'B1' iv_t = 'Standarddokumentation: liest die Dokumentation je Aktivitaet. Dies ist' ).
    a( iv_f = '=' iv_t = 'der laufzeitintensivste Teil.' ).
    a( iv_f = 'B1' iv_t = 'Objektzuordnung: nimmt die zugeordneten Customizing-Objekte auf.' ).
    a( iv_f = 'B1' iv_t = 'Customizing-Inhalte lesen: ergaenzt Feldliste und Tabelleninhalte.' ).
    a( iv_f = 'B1' iv_t = 'Nur kundeneigene Eintraege: schraenkt auf Eintraege im Kundennamensraum' ).
    a( iv_f = '=' iv_t = 'oder mit Vorkommen in Transportauftraegen ein. Das angewandte Verfahren' ).
    a( iv_f = '=' iv_t = 'wird am Objekt ausgewiesen.' ).
    a( iv_f = 'B1' iv_t = 'Max. Zeilen: Obergrenze je Tabelle. Die Gesamtzahl bleibt im Dokument' ).
    a( iv_f = '=' iv_t = 'vermerkt, ebenso die Kuerzung.' ).
    a( iv_f = 'B1' iv_t = 'Transport-Historie: fuehrt die Auftraege zur jeweiligen Tabelle auf.' ).
    a( iv_f = 'B1' iv_t = 'Ausgabesprache und Ersatzsprache: alle Texte im Dokument folgen der' ).
    a( iv_f = '=' iv_t = 'Ausgabesprache. Ist dort nichts gepflegt, wird die Ersatzsprache' ).
    a( iv_f = '=' iv_t = 'versucht; welche Sprache geliefert hat, steht am Kapitel.' ).
    a( iv_f = 'B1' iv_t = 'Ausgehende Aufrufe: durchsucht den Quelltext des Programms hinter der' ).
    a( iv_f = '=' iv_t = 'Transaktion nach Bausteinen, Tabellenzugriffen und Klassen. Genommen' ).
    a( iv_f = '=' iv_t = 'werden nur die Transaktionen der zugeordneten Objekte, nicht die des' ).
    a( iv_f = '=' iv_t = 'Aktivitaetskopfes - diese fuehrt ins IMG-Rahmenwerk.' ).
    a( iv_f = 'B1' iv_t = 'SAP-Standard ausschliessen: laesst in der Verweisliste nur Objekte der' ).
    a( iv_f = '=' iv_t = 'Eigenentwicklung stehen.' ).

    a( iv_f = 'U1' iv_t = 'Ausgabe' ).
    a( iv_f = 'B1' iv_t = 'HTML erzeugen/anzeigen: lesbare Fassung mit Inhaltsverzeichnis.' ).
    a( iv_f = '=' iv_t = 'Vorbelegung, weil das Dokument in aller Regel gelesen und nicht' ).
    a( iv_f = '=' iv_t = 'weiterverarbeitet wird.' ).
    a( iv_f = 'B1' iv_t = 'XML erzeugen/ausgeben: fuehrendes Format, wieder einlesbar. Fuer die' ).
    a( iv_f = '=' iv_t = 'Weitergabe und den spaeteren Reimport.' ).
    a( iv_f = 'B1' iv_t = 'HTML einklappen ab Zeilen: laengere Tabellen und Quelltexte stehen im' ).
    a( iv_f = '=' iv_t = 'HTML zugeklappt hinter einer Zeile mit Bezeichnung und Umfang und' ).
    a( iv_f = '=' iv_t = 'lassen sich per Klick oeffnen. 0 schaltet das Einklappen ab.' ).
    a( iv_f = 'B1' iv_t = 'Projektstatus und Projekt-Memo sind einzeln abschaltbar.' ).
    a( iv_f = 'B1' iv_t = 'Roundtrip pruefen: serialisiert, liest wieder ein, serialisiert erneut' ).
    a( iv_f = '=' iv_t = 'und vergleicht. Dient der Pruefung des Importpfades und schreibt nichts' ).
    a( iv_f = '=' iv_t = 'in das System zurueck.' ).
    a( iv_f = 'B1' iv_t = 'Download auf PC und Ablage Appl.-Server schreiben dieselbe Datei in' ).
    a( iv_f = '=' iv_t = 'UTF-8. Der Dateiname enthaelt System, Datum und Uhrzeit.' ).

    a( iv_f = 'U1' iv_t = 'Hinweise' ).
    a( iv_f = 'AS' iv_t = 'Der Referenz-Einfuehrungsleitfaden umfasst mit aufgeloesten' ).
    a( iv_f = '=' iv_t = 'Unterstrukturen mehrere tausend Kapitel. Fuer vollstaendige Laeufe' ).
    a( iv_f = '=' iv_t = 'empfiehlt sich Hintergrundverarbeitung mit Ablage auf dem' ).
    a( iv_f = '=' iv_t = 'Applikationsserver.' ).
    a( iv_f = 'AS' iv_t = 'IMG-Strukturen tragen keinen sprechenden Schluessel; der Zugriff' ).
    a( iv_f = '=' iv_t = 'erfolgt ueber die Struktur-GUID. Im System koennen veraltete' ).
    a( iv_f = '=' iv_t = 'Strukturen gleichen Namens vorhanden sein. Das Aenderungsdatum in der' ).
    a( iv_f = '=' iv_t = 'Wertehilfe hilft bei der Unterscheidung.' ).

  ENDMETHOD.

  METHOD build_dev.

    CLEAR mt_line.

    a( iv_f = 'U1' iv_t = 'Verwendung' ).
    a( iv_f = 'AS' iv_t = 'Der Report erzeugt eine kapitelweise gegliederte' ).
    a( iv_f = '=' iv_t = 'Entwicklerdokumentation. Einstieg ist entweder ein Paket samt' ).
    a( iv_f = '=' iv_t = 'Unterpaketen oder ein einzelnes Objekt - Report, Klasse,' ).
    a( iv_f = '=' iv_t = 'Funktionsbaustein, Tabelle, View, CDS View und weitere.' ).
    a( iv_f = 'AS' iv_t = 'Je Objekt werden Kurztext, Typ, Autor und Paket aufgenommen, auf Wunsch' ).
    a( iv_f = '=' iv_t = 'ergaenzt um Objektdokumentation, Detailinformationen, Quelltext und' ).
    a( iv_f = '=' iv_t = 'Verwendungsnachweis.' ).
    a( iv_f = 'AS' iv_t = 'Die Ausgabe erfolgt als XML und als HTML. Das XML kann vom Report' ).
    a( iv_f = '=' iv_t = 'wieder eingelesen werden.' ).

    a( iv_f = 'U1' iv_t = 'Voraussetzungen' ).
    a( iv_f = 'AS' iv_t = 'Lesender Zugriff auf das Repository. Fuer Download und Anzeige im' ).
    a( iv_f = '=' iv_t = 'Browser ist Dialogbetrieb erforderlich; im Hintergrund steht nur die' ).
    a( iv_f = '=' iv_t = 'Ablage auf dem Applikationsserver zur Verfuegung.' ).

    a( iv_f = 'U1' iv_t = 'Selektion' ).
    a( iv_f = 'AS' iv_t = 'Startpunkt' ).
    a( iv_f = 'B1' iv_t = 'Typ und Name bilden den Einstieg, wie im Object Navigator: K Paket,' ).
    a( iv_f = '=' iv_t = 'P Programm, C Klasse oder Interface, FF Funktionsbaustein,' ).
    a( iv_f = '=' iv_t = 'F Funktionsgruppe, T Tabelle, V View, D Datenelement, DO Domaene,' ).
    a( iv_f = '=' iv_t = 'W CDS View. Beide Felder haben eine Wertehilfe.' ).
    a( iv_f = 'B1' iv_t = 'Bei einem Paket entsteht die Gliederung Paket, Objekttyp, Objekt. Bei' ).
    a( iv_f = '=' iv_t = 'einem Einzelobjekt steht dieses in Kapitel eins, die verwendeten' ).
    a( iv_f = '=' iv_t = 'Objekte folgen in Kapitel zwei.' ).
    a( iv_f = 'B1' iv_t = 'Unterpakete rekursiv: bezieht den gesamten Unterbaum ein, nur im' ).
    a( iv_f = '=' iv_t = 'Paketmodus.' ).
    a( iv_f = 'B1' iv_t = 'Lokale Pakete einbeziehen: beruecksichtigt auch Pakete des' ).
    a( iv_f = '=' iv_t = 'Kurzzeitnamensraums.' ).

    a( iv_f = 'AS' iv_t = 'Umfang' ).
    a( iv_f = 'B1' iv_t = 'Objekttyp und Objektname grenzen die Objektliste ein.' ).
    a( iv_f = 'B1' iv_t = 'Max. Objekte begrenzt die Aufnahme. Die Gesamtzahl der gefundenen' ).
    a( iv_f = '=' iv_t = 'Objekte bleibt im Dokument vermerkt.' ).
    a( iv_f = 'B1' iv_t = 'Objektdokumentation: liest die klassische Objektdokumentation fuer' ).
    a( iv_f = '=' iv_t = 'Programme, Transaktionen und Datenelemente.' ).
    a( iv_f = 'B1' iv_t = 'Details: ergaenzt Feldlisten fuer Tabellen, Basistabellen und' ).
    a( iv_f = '=' iv_t = 'Verknuepfung fuer Views, Komponenten fuer Klassen und Interfaces,' ).
    a( iv_f = '=' iv_t = 'Textelemente fuer Programme, Festwerte fuer Domaenen,' ).
    a( iv_f = '=' iv_t = 'Feldbezeichner fuer Datenelemente, die Schnittstelle fuer' ).
    a( iv_f = '=' iv_t = 'Funktionsbausteine und verwendete Objekte fuer CDS Views.' ).
    a( iv_f = 'B1' iv_t = 'Quelltext ausgeben: nimmt den Quelltext auf. Fuer Funktionsgruppen und' ).
    a( iv_f = '=' iv_t = 'Klassen werden alle zugehoerigen Includes gelesen.' ).
    a( iv_f = 'B1' iv_t = 'Max. Zeilen je Objekt begrenzt den Quelltext. Wird die Grenze' ).
    a( iv_f = '=' iv_t = 'erreicht, steht der Hinweis mit der Gesamtzahl im Quelltext selbst.' ).
    a( iv_f = 'B1' iv_t = 'Verwendungsnachweis: zeigt, wo das Startobjekt verwendet wird, mit' ).
    a( iv_f = '=' iv_t = 'Programmart und - bei einer Tabelle - der Zugriffsart lesend oder' ).
    a( iv_f = '=' iv_t = 'schreibend. Dazu die Fundstellen mit Zeilennummer. Zu einer Tabelle' ).
    a( iv_f = '=' iv_t = 'werden auch die Views und CDS Views genannt, die auf ihr aufsetzen.' ).
    a( iv_f = 'B1' iv_t = 'Ausgehende Aufrufe: die Gegenrichtung. Neben den Querverweistabellen' ).
    a( iv_f = '=' iv_t = 'wird der Quelltext nach CALL FUNCTION, SUBMIT, Tabellenzugriffen und' ).
    a( iv_f = '=' iv_t = 'Klassen durchsucht; Funktionsbausteine stehen in keinem Index.' ).
    a( iv_f = 'B1' iv_t = 'Verweistiefe: wie weit die Verweise verfolgt werden. Null bedeutet' ).
    a( iv_f = '=' iv_t = 'nicht verfolgen, eins die direkten Nachbarn dokumentieren.' ).
    a( iv_f = 'B1' iv_t = 'SAP-Standard ausschliessen: laesst nur Objekte der Eigenentwicklung' ).
    a( iv_f = '=' iv_t = 'stehen. Massstab ist die Auslieferungseinheit des Pakets.' ).
    a( iv_f = 'B1' iv_t = 'Max. Fundstellen je Stelle begrenzt die Quelltextzeilen je Verwendung.' ).
    a( iv_f = 'B1' iv_t = 'Fundstellen im ganzen Quelltext: gibt statt der Trefferzeilen das ganze' ).
    a( iv_f = '=' iv_t = 'Listing aus und hebt die Trefferzeilen hervor.' ).
    a( iv_f = 'B1' iv_t = 'Max. Verwendungen je Objekt begrenzt den Nachweis getrennt von der' ).
    a( iv_f = '=' iv_t = 'Objektgrenze. Auf den Aufbau eines Objekts greift die Grenze nicht:' ).
    a( iv_f = '=' iv_t = 'die Datenelemente einer Tabelle werden immer vollstaendig gesammelt,' ).
    a( iv_f = '=' iv_t = 'sonst laesst sich die Tabelle spaeter nicht aktivieren.' ).
    a( iv_f = 'B1' iv_t = 'Definitionsdaten fuer Reimport: nimmt neben der Beschreibung die' ).
    a( iv_f = '=' iv_t = 'technische Definition mit auf - Tabellenart, Auslieferungsklasse,' ).
    a( iv_f = '=' iv_t = 'technische Einstellungen, Felder, Fremdschluessel, Programmattribute' ).
    a( iv_f = '=' iv_t = 'und Textelemente. Ohne diese Daten kann der Import nichts anlegen.' ).

    a( iv_f = 'U1' iv_t = 'Ausgabe' ).
    a( iv_f = 'B1' iv_t = 'HTML erzeugen/anzeigen: lesbare Fassung mit Inhaltsverzeichnis.' ).
    a( iv_f = '=' iv_t = 'Vorbelegung, weil das Dokument in aller Regel gelesen und nicht' ).
    a( iv_f = '=' iv_t = 'weiterverarbeitet wird.' ).
    a( iv_f = 'B1' iv_t = 'XML erzeugen/ausgeben: fuehrendes Format, wieder einlesbar. Fuer die' ).
    a( iv_f = '=' iv_t = 'Weitergabe und den spaeteren Reimport.' ).
    a( iv_f = 'B1' iv_t = 'HTML einklappen ab Zeilen: laengere Feldlisten, Verweislisten und' ).
    a( iv_f = '=' iv_t = 'Quelltexte stehen im HTML zugeklappt hinter einer Zeile mit' ).
    a( iv_f = '=' iv_t = 'Bezeichnung und Umfang. 0 schaltet das Einklappen ab.' ).
    a( iv_f = 'B1' iv_t = 'Roundtrip pruefen: serialisiert, liest wieder ein, serialisiert erneut' ).
    a( iv_f = '=' iv_t = 'und vergleicht. Schreibt nichts in das System zurueck.' ).
    a( iv_f = 'B1' iv_t = 'Download auf PC und Ablage Appl.-Server schreiben dieselbe Datei in' ).
    a( iv_f = '=' iv_t = 'UTF-8. Der Dateiname enthaelt System, Datum und Uhrzeit.' ).

    a( iv_f = 'U1' iv_t = 'Import in dieses System' ).
    a( iv_f = 'AS' iv_t = 'Der Report kann die Richtung umkehren: eine in einem anderen System' ).
    a( iv_f = '=' iv_t = 'erzeugte XML-Datei einlesen und die darin definierten Objekte hier' ).
    a( iv_f = '=' iv_t = 'anlegen. Voraussetzung ist, dass beim Export die Definitionsdaten' ).
    a( iv_f = '=' iv_t = 'mitgeschrieben wurden.' ).
    a( iv_f = 'B1' iv_t = 'Angelegt werden Domaenen, Datenelemente, Tabellen, Strukturen,' ).
    a( iv_f = '=' iv_t = 'Views, CDS-Quellen, Programme samt Textelementen, Klassen,' ).
    a( iv_f = '=' iv_t = 'Interfaces und Funktionsgruppen mit ihren Bausteinen.' ).
    a( iv_f = 'B1' iv_t = 'Bei einer CDS-Quelle entstehen SQL-View und Strukturobjekt beim' ).
    a( iv_f = '=' iv_t = 'Aktivieren von selbst; sie stehen nicht im Dokument.' ).
    a( iv_f = 'B1' iv_t = 'Sekundaerindizes einer Tabelle reisen mit und werden angelegt,' ).
    a( iv_f = '=' iv_t = 'nachdem die Tabelle aktiv ist.' ).
    a( iv_f = 'B1' iv_t = 'Klassen reisen als quelltextbasierte Fassung - der Text, den SE24' ).
    a( iv_f = '=' iv_t = 'zeigt. Autor, Aenderungsdatum und UUID bleiben im Quellsystem.' ).
    a( iv_f = 'B1' iv_t = 'Testlauf ist vorbelegt: der Report meldet, was er anlegen wuerde, und' ).
    a( iv_f = '=' iv_t = 'legt nichts an. Wer schreiben will, nimmt den Haken heraus.' ).
    a( iv_f = 'B1' iv_t = 'Ein Objekt, das es hier schon gibt, bleibt unangetastet, solange' ).
    a( iv_f = '=' iv_t = 'Bestehende Objekte ueberschreiben nicht gesetzt ist.' ).
    a( iv_f = 'B1' iv_t = 'Die Reihenfolge legt der Report fest: Domaenen, Datenelemente,' ).
    a( iv_f = '=' iv_t = 'Tabellen, Views, CDS-Quellen, Programme, Interfaces, Klassen,' ).
    a( iv_f = '=' iv_t = 'Funktionsgruppen. Eine Tabelle ohne ihre Datenelemente liesse sich' ).
    a( iv_f = '=' iv_t = 'nicht aktivieren.' ).
    a( iv_f = 'B1' iv_t = 'Aktiviert wird gezielt: aus den inaktiven Objekten des Benutzers' ).
    a( iv_f = '=' iv_t = 'nimmt der Import nur die, die zum eben geschriebenen Objekt gehoeren.' ).
    a( iv_f = '=' iv_t = 'Angefangene Arbeit anderer bleibt unberuehrt.' ).
    a( iv_f = 'B1' iv_t = 'Bei einem lokalen Paket wird kein Auftrag angefordert, sonst der' ).
    a( iv_f = '=' iv_t = 'angegebene verwendet.' ).
    a( iv_f = 'B1' iv_t = 'Nach dem Lauf wird jedes Objekt geprueft: DDIC-Objekte auf die' ).
    a( iv_f = '=' iv_t = 'aktive Fassung, Programme mit einem Syntax-Check. Gemeldet wird nur,' ).
    a( iv_f = '=' iv_t = 'was auffaellt. Angelegt heisst nicht brauchbar - einer Struktur kann' ).
    a( iv_f = '=' iv_t = 'ein Datenelement fehlen, und dann aktiviert sie nicht.' ).

    a( iv_f = 'U1' iv_t = 'Hinweise' ).
    a( iv_f = 'AS' iv_t = 'Objektdokumentation und Verwendungsnachweis erzeugen je Objekt eigene' ).
    a( iv_f = '=' iv_t = 'Datenbankzugriffe und bestimmen die Laufzeit. Kurztexte stammen aus' ).
    a( iv_f = '=' iv_t = 'gepufferten Texttabellen und fallen nicht ins Gewicht.' ).
    a( iv_f = 'AS' iv_t = 'Ist in der gewaehlten Sprache kein Kurztext gepflegt, wird auf Englisch' ).
    a( iv_f = '=' iv_t = 'zurueckgegriffen. Objekte ohne Text in jeder Sprache bleiben leer.' ).
    a( iv_f = 'AS' iv_t = 'Pakete ohne Katalogeintrag werden mit einem Vermerk uebergangen; der' ).
    a( iv_f = '=' iv_t = 'Lauf bricht nicht ab.' ).

  ENDMETHOD.

  METHOD run.

    build_img( ).
    save( 'ZDOCUMIZER_IMG' ).

    build_dev( ).
    save( 'ZDOCUMIZER_DEV' ).

    COMMIT WORK AND WAIT.
    WRITE: / 'Dokumentation gesichert.'.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_docu( )->run( ).