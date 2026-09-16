REPORT zdocumizer_docu.

************************************************************************
* consiness Documizer - Reportdokumentation erzeugen
*
* Legt die SAP-Reportdokumentation zu ZDOCUMIZER_IMG, ZDOCUMIZER_DEV und
* ZDOCUMIZER_ATC an. Dokumentationsobjekte sind eigene Repository-Objekte und kommen beim
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
    METHODS build_atc.
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
    a( iv_f = '=' iv_t = 'UTF-8.' ).
    a( iv_f = 'B1' iv_t = 'Dateiname: vorbelegt mit System, Startknoten, Datum und Uhrzeit,' ).
    a( iv_f = '=' iv_t = 'ohne Endung - XML und HTML entstehen aus demselben Lauf und' ).
    a( iv_f = '=' iv_t = 'unterscheiden sich nur darin. Das Feld ist ueberschreibbar; der' ).
    a( iv_f = '=' iv_t = 'Vorschlag wandert mit dem Startknoten mit, solange niemand ihn' ).
    a( iv_f = '=' iv_t = 'geaendert hat. Ein selbst gewaehlter Name bleibt stehen.' ).

    a( iv_f = 'U1' iv_t = 'BC-Set aus Dokument erzeugen' ).
    a( iv_f = 'AS' iv_t = 'Der Report kann die Richtung umkehren: ein zuvor erzeugtes Dokument' ).
    a( iv_f = '=' iv_t = 'einlesen und daraus ein Business Configuration Set anlegen. Das Set' ).
    a( iv_f = '=' iv_t = 'traegt das Customizing, das im Dokument steht.' ).
    a( iv_f = 'B1' iv_t = 'Geschrieben wird damit noch nichts. Das Customizing entsteht erst,' ).
    a( iv_f = '=' iv_t = 'wenn jemand das Set in SCPR20 aktiviert - mit Protokoll,' ).
    a( iv_f = '=' iv_t = 'Auftragsanschluss und der Moeglichkeit, vorher hineinzusehen. Ein' ).
    a( iv_f = '=' iv_t = 'Report, der Customizing-Tabellen direkt beschreibt, hat davon' ).
    a( iv_f = '=' iv_t = 'nichts.' ).
    a( iv_f = 'B1' iv_t = 'Voraussetzung ist ein Dokument, das mit Customizing-Inhalte lesen' ).
    a( iv_f = '=' iv_t = 'erzeugt wurde. Ohne Inhalte gibt es nichts aufzunehmen.' ).
    a( iv_f = 'B1' iv_t = 'Aufgenommen wird nur, was vollstaendig vorliegt. Eine Tabelle, die' ).
    a( iv_f = '=' iv_t = 'beim Export an Max. Zeilen abgeschnitten wurde, bleibt draussen -' ).
    a( iv_f = '=' iv_t = 'ein halbes Set sieht aus wie ein ganzes und loescht beim' ).
    a( iv_f = '=' iv_t = 'Aktivieren, was nicht mitkam. Fuer eine vollstaendige Uebernahme' ).
    a( iv_f = '=' iv_t = 'muss der Export mit Max. Zeilen = 0 gelaufen sein.' ).
    a( iv_f = 'B1' iv_t = 'Ebenfalls draussen bleiben Tabellen, die es hier nicht gibt, und' ).
    a( iv_f = '=' iv_t = 'Auslieferungsklassen, die kein Kundencustomizing tragen. Jede' ).
    a( iv_f = '=' iv_t = 'Auslassung steht mit Begruendung im Protokoll.' ).
    a( iv_f = 'B1' iv_t = 'Testlauf ist vorbelegt: der Report meldet, was in das Set kaeme,' ).
    a( iv_f = '=' iv_t = 'und legt nichts an.' ).
    a( iv_f = 'B1' iv_t = 'Fehlliste schreiben: die uebergangenen Objekte werden zusaetzlich' ).
    a( iv_f = '=' iv_t = 'als XML-Arbeitsliste ausgegeben. Diese Datei liest der' ).
    a( iv_f = '=' iv_t = 'Entwickler-Report im Quellsystem als Startpunkt-Typ AL und' ).
    a( iv_f = '=' iv_t = 'exportiert genau die fehlenden Objekte - Tabelle, View,' ).
    a( iv_f = '=' iv_t = 'View-Cluster und Pflegetransaktion. Nach deren Import laeuft die' ).
    a( iv_f = '=' iv_t = 'BC-Set-Erzeugung auch fuer sie durch.' ).
    a( iv_f = 'B1' iv_t = 'Angefordert wird nur, was hier wirklich fehlt. Eine' ).
    a( iv_f = '=' iv_t = 'Standardtransaktion wie SM30 steht in jedem System und gehoert' ).
    a( iv_f = '=' iv_t = 'nicht auf die Liste.' ).

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
    a( iv_f = '=' iv_t = 'W CDS View, MX Metadata Extension, BD Verhaltensdefinition,' ).
    a( iv_f = '=' iv_t = 'SD Service-Definition, SB Service-Binding, IS IDoc-Segmenttyp,' ).
    a( iv_f = '=' iv_t = 'IT IDoc-Basistyp, U5 UI5-Anwendung, AL Arbeitsliste aus' ).
    a( iv_f = '=' iv_t = 'Fehlliste. Beide Felder haben eine Wertehilfe.' ).
    a( iv_f = 'B1' iv_t = 'Bei einem Paket entsteht die Gliederung Paket, Objekttyp, Objekt. Bei' ).
    a( iv_f = '=' iv_t = 'einem Einzelobjekt steht dieses in Kapitel eins, die verwendeten' ).
    a( iv_f = '=' iv_t = 'Objekte folgen in Kapitel zwei.' ).
    a( iv_f = 'B1' iv_t = 'Unterpakete rekursiv: bezieht den gesamten Unterbaum ein, nur im' ).
    a( iv_f = '=' iv_t = 'Paketmodus.' ).
    a( iv_f = 'B1' iv_t = 'Lokale Pakete einbeziehen: beruecksichtigt auch Pakete des' ).
    a( iv_f = '=' iv_t = 'Kurzzeitnamensraums.' ).
    a( iv_f = 'B1' iv_t = 'Arbeitsliste aus Fehlliste (Typ AL): kein einzelnes Objekt, sondern' ).
    a( iv_f = '=' iv_t = 'eine Liste davon. Der IMG-Report schreibt sie im Zielsystem, wenn' ).
    a( iv_f = '=' iv_t = 'ihm beim Anlegen eines BC-Sets Objekte fehlen. Der Startpunkt' ).
    a( iv_f = '=' iv_t = 'steht dann in der Datei, nicht im Namensfeld; jedes Objekt der' ).
    a( iv_f = '=' iv_t = 'Liste wird ein eigenes Kapitel.' ).
    a( iv_f = '=' iv_t = 'Liegt die Fehlliste auf dem Applikationsserver, wird das eigens' ).
    a( iv_f = '=' iv_t = 'angekreuzt; das Kennzeichen gehoert zur Fehlliste, nicht zum Import.' ).

    a( iv_f = 'AS' iv_t = 'Umfang' ).
    a( iv_f = 'B1' iv_t = 'Objekttyp und Objektname grenzen die Objektliste ein.' ).
    a( iv_f = 'B1' iv_t = 'Max. Objekte begrenzt die Aufnahme. Die Gesamtzahl der gefundenen' ).
    a( iv_f = '=' iv_t = 'Objekte bleibt im Dokument vermerkt.' ).
    a( iv_f = 'B1' iv_t = 'Objektdokumentation: liest die klassische Objektdokumentation fuer' ).
    a( iv_f = '=' iv_t = 'Programme, Transaktionen und Datenelemente.' ).
    a( iv_f = 'B1' iv_t = 'Details: ergaenzt Feldlisten fuer Tabellen, Basistabellen und' ).
    a( iv_f = '=' iv_t = 'Verknuepfung fuer Views, Textelemente fuer Programme, Festwerte' ).
    a( iv_f = '=' iv_t = 'fuer Domaenen, Feldbezeichner fuer Datenelemente und die' ).
    a( iv_f = '=' iv_t = 'Schnittstelle fuer Funktionsbausteine.' ).
    a( iv_f = 'B1' iv_t = 'Zu Klassen und Interfaces stehen Oberklasse, Schnittstellen,' ).
    a( iv_f = '=' iv_t = 'Komponenten, implementierte Schnittstellenmethoden und die lokalen' ).
    a( iv_f = '=' iv_t = 'Klassen samt Methoden. Ein Behavior-Pool ist nach aussen leer; die' ).
    a( iv_f = '=' iv_t = 'Handler, die die Logik tragen, stehen als lokale Klassen darin.' ).
    a( iv_f = 'B1' iv_t = 'Zu einer CDS View stehen die Feldliste der Entitaet und die' ).
    a( iv_f = '=' iv_t = 'verwendeten Objekte. Die Feldliste eines IDoc-Segments nennt die' ).
    a( iv_f = '=' iv_t = 'Datenelemente, die WE31 zeigt - im Dictionary fuehrt das Segment' ).
    a( iv_f = '=' iv_t = 'nur Zeichenfelder ohne Datenelement.' ).
    a( iv_f = 'B1' iv_t = 'Zu einem IDoc-Basistyp stehen drei Sichten, jede nach der' ).
    a( iv_f = '=' iv_t = 'Transaktion benannt, in der SAP dasselbe zeigt: die' ).
    a( iv_f = '=' iv_t = 'Segmenthierarchie (WE60), die Nachrichtentypen (WE82) und die' ).
    a( iv_f = '=' iv_t = 'verarbeitenden Bausteine je Richtung (WE57).' ).
    a( iv_f = 'B1' iv_t = 'Quelltext ausgeben: nimmt den Quelltext auf. Fuer Funktionsgruppen und' ).
    a( iv_f = '=' iv_t = 'Klassen werden alle zugehoerigen Includes gelesen. Auch' ).
    a( iv_f = '=' iv_t = 'Verhaltensdefinition, Service-Definition und Metadata Extension' ).
    a( iv_f = '=' iv_t = 'haben Quelltext.' ).
    a( iv_f = 'B1' iv_t = 'Max. Zeilen je Objekt begrenzt den Quelltext. Wird die Grenze' ).
    a( iv_f = '=' iv_t = 'erreicht, steht der Hinweis mit der Gesamtzahl im Quelltext selbst.' ).
    a( iv_f = 'B1' iv_t = 'Verwendungsnachweis: zeigt, wo das Startobjekt verwendet wird, mit' ).
    a( iv_f = '=' iv_t = 'Programmart und - bei einer Tabelle - der Zugriffsart lesend oder' ).
    a( iv_f = '=' iv_t = 'schreibend. Dazu die Fundstellen mit Zeilennummer. Zu einer Tabelle' ).
    a( iv_f = '=' iv_t = 'werden auch die Views und CDS Views genannt, die auf ihr aufsetzen.' ).
    a( iv_f = '=' iv_t = 'Zu Tabellen und Strukturen kommen die Stellen hinzu, die einzelne' ).
    a( iv_f = '=' iv_t = 'Felder anfassen, mit den Feldnamen hinter der Fundstelle.' ).
    a( iv_f = 'B1' iv_t = 'Auch fuer verwendete Objekte: zieht den Verwendungsnachweis nicht' ).
    a( iv_f = '=' iv_t = 'nur zum Startobjekt, sondern zu jedem Objekt im Dokument. Bei einem' ).
    a( iv_f = '=' iv_t = 'IDoc-Basistyp ist das die eigentliche Frage - den Basistyp' ).
    a( iv_f = '=' iv_t = 'typisiert niemand, seine Segmente werden dauernd gelesen. Ohne' ).
    a( iv_f = '=' iv_t = 'Haken bleibt es beim Startobjekt, denn ein Datenelement wie CHAR255' ).
    a( iv_f = '=' iv_t = 'haengt an tausenden Programmen.' ).
    a( iv_f = 'B1' iv_t = 'Ausgehende Aufrufe: die Gegenrichtung. Neben den Querverweistabellen' ).
    a( iv_f = '=' iv_t = 'wird der Quelltext nach CALL FUNCTION, SUBMIT, Tabellenzugriffen und' ).
    a( iv_f = '=' iv_t = 'Klassen durchsucht; Funktionsbausteine stehen in keinem Index.' ).
    a( iv_f = '=' iv_t = 'Ebenfalls aus dem Quelltext gelesen werden die INCLUDE-Anweisungen' ).
    a( iv_f = '=' iv_t = 'eines Programms. Ohne seine Includes laesst sich ein importiertes' ).
    a( iv_f = '=' iv_t = 'Programm nicht uebersetzen. Includes sind Aufbau, nicht Verwendung,' ).
    a( iv_f = '=' iv_t = 'und werden deshalb nicht begrenzt.' ).
    a( iv_f = 'B1' iv_t = 'Verweistiefe: wie weit die Verweise verfolgt werden. Null bedeutet' ).
    a( iv_f = '=' iv_t = 'nicht verfolgen, eins die direkten Nachbarn dokumentieren.' ).
    a( iv_f = 'B1' iv_t = 'Verwendungstiefe: die Gegenrichtung. Die gefundenen Verwender' ).
    a( iv_f = '=' iv_t = 'werden selbst als Kapitel dokumentiert. Null bedeutet nicht' ).
    a( iv_f = '=' iv_t = 'verfolgen.' ).
    a( iv_f = 'B1' iv_t = 'SAP-Standard ausschliessen: laesst nur Objekte der Eigenentwicklung' ).
    a( iv_f = '=' iv_t = 'stehen. Massstab ist die Auslieferungseinheit des Pakets. Ein' ).
    a( iv_f = '=' iv_t = 'Include hat oft gar keinen Katalogeintrag; dann bleibt es stehen,' ).
    a( iv_f = '=' iv_t = 'denn was niemand katalogisiert hat, ist kein SAP-Standard.' ).
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
    a( iv_f = '=' iv_t = 'UTF-8.' ).
    a( iv_f = 'B1' iv_t = 'Dateiname: vorbelegt mit System, Startobjekt, Datum und Uhrzeit,' ).
    a( iv_f = '=' iv_t = 'ohne Endung - XML und HTML entstehen aus demselben Lauf und' ).
    a( iv_f = '=' iv_t = 'unterscheiden sich nur darin. Das Feld ist ueberschreibbar; der' ).
    a( iv_f = '=' iv_t = 'Vorschlag wandert mit dem Startobjekt mit, solange niemand ihn' ).
    a( iv_f = '=' iv_t = 'geaendert hat. Ein selbst gewaehlter Name bleibt stehen.' ).

    a( iv_f = 'U1' iv_t = 'Import in dieses System' ).
    a( iv_f = 'AS' iv_t = 'Der Report kann die Richtung umkehren: eine in einem anderen System' ).
    a( iv_f = '=' iv_t = 'erzeugte XML-Datei einlesen und die darin definierten Objekte hier' ).
    a( iv_f = '=' iv_t = 'anlegen. Voraussetzung ist, dass beim Export die Definitionsdaten' ).
    a( iv_f = '=' iv_t = 'mitgeschrieben wurden.' ).
    a( iv_f = 'B1' iv_t = 'Ist der Import angekreuzt, sind Typ und Name des Startpunkts inaktiv;' ).
    a( iv_f = '=' iv_t = 'ein Importlauf hat keinen Startpunkt. Beide Felder sind deshalb' ).
    a( iv_f = '=' iv_t = 'keine Mussfelder - sonst waere das Ankreuzfeld nicht erreichbar,' ).
    a( iv_f = '=' iv_t = 'ohne vorher etwas einzugeben, was der Import gar nicht verwendet.' ).
    a( iv_f = '=' iv_t = 'Geprueft wird erst beim Ausfuehren.' ).
    a( iv_f = 'B1' iv_t = 'XML-Datei liegt auf Appl.-Server: liest die Datei vom' ).
    a( iv_f = '=' iv_t = 'Applikationsserver statt vom PC.' ).
    a( iv_f = 'B1' iv_t = 'Angelegt werden Domaenen, Datenelemente, Tabellen, Strukturen,' ).
    a( iv_f = '=' iv_t = 'Views, CDS-Quellen, Programme samt Textelementen, Klassen,' ).
    a( iv_f = '=' iv_t = 'Interfaces und Funktionsgruppen mit ihren Bausteinen.' ).
    a( iv_f = 'B1' iv_t = 'Verhaltensdefinition, Service-Definition und Metadata Extension' ).
    a( iv_f = '=' iv_t = 'reisen als Quelltext mit, das Service-Binding mit Bindungsart,' ).
    a( iv_f = '=' iv_t = 'Services und Versionen. Damit ist das Backend einer' ).
    a( iv_f = '=' iv_t = 'Fiori-Elements-Anwendung vollstaendig uebertragbar.' ).
    a( iv_f = '=' iv_t = 'Startpunkt-Typen dafuer: BD, SD, MX und SB.' ).
    a( iv_f = 'B1' iv_t = 'Ein Service-Binding wird grundsaetzlich unveroeffentlicht' ).
    a( iv_f = '=' iv_t = 'angelegt, auch wenn es im Quellsystem veroeffentlicht war. Ein' ).
    a( iv_f = '=' iv_t = 'Binding anzulegen ist eine Entwicklungsaufgabe, einen Dienst' ).
    a( iv_f = '=' iv_t = 'nach aussen bereitzustellen eine andere.' ).
    a( iv_f = 'B1' iv_t = 'UI5-Anwendungen reisen mit allen Dateien, samt Verzeichnisbaum.' ).
    a( iv_f = '=' iv_t = 'Gelesen und geschrieben wird ueber die UI5-Repository-API, den' ).
    a( iv_f = '=' iv_t = 'gleichen Weg, den auch ADT nimmt - nicht ueber die BSP-Seiten.' ).
    a( iv_f = '=' iv_t = 'Deren Inhalt ist nur der XML-Rahmen der Seite, und der' ).
    a( iv_f = '=' iv_t = 'Verzeichnisbaum steht ohnehin woanders. Der Dateiinhalt geht' ).
    a( iv_f = '=' iv_t = 'als Base64 ins XML - eine Regel fuer Text und Binaeres. Im' ).
    a( iv_f = '=' iv_t = 'HTML steht er nie: der HTML-Teil fasst Definitionsdaten nicht' ).
    a( iv_f = '=' iv_t = 'an, das lesbare Dokument bleibt lesbar. Base64 blaeht um rund' ).
    a( iv_f = '=' iv_t = 'ein Drittel auf; bei grossen Anwendungen wird das Dokument' ).
    a( iv_f = '=' iv_t = 'entsprechend gross. Startpunkt-Typ: U5.' ).
    a( iv_f = 'B1' iv_t = 'Was um eine UI5-Anwendung herum liegt, reist nicht mit: der' ).
    a( iv_f = '=' iv_t = 'ICF-Knoten, die MIME-Objekte, die Berechtigungsvorschlagswerte' ).
    a( iv_f = '=' iv_t = 'und die Gateway-Registrierung des OData-Service. Sie stehen im' ).
    a( iv_f = '=' iv_t = 'Dokument, angelegt werden sie nicht - das bleibt Handarbeit.' ).
    a( iv_f = 'B1' iv_t = 'IDoc-Segmenttypen und -Basistypen reisen mit. Ein Segmenttyp' ).
    a( iv_f = '=' iv_t = 'traegt im Katalog TABL, weil SAP dazu eine gleichnamige' ).
    a( iv_f = '=' iv_t = 'Struktur erzeugt; als Struktur importiert entstuende etwas mit' ).
    a( iv_f = '=' iv_t = 'den richtigen Feldern, das WE31 nicht als Segment kennt. Der' ).
    a( iv_f = '=' iv_t = 'Report erkennt das und legt ein echtes Segment an. Ein' ).
    a( iv_f = '=' iv_t = 'vorhandenes Segment bleibt unangetastet - eine neue' ).
    a( iv_f = '=' iv_t = 'Segmentdefinition waere eine neue Version. Startpunkt-Typen:' ).
    a( iv_f = '=' iv_t = 'IS und IT.' ).
    a( iv_f = 'B1' iv_t = 'Ein Basistyp nimmt seine Segmenttypen mit. Die Segmenthierarchie' ).
    a( iv_f = '=' iv_t = 'steht in der Syntaxtabelle und in keinem Querverweisindex; ohne' ).
    a( iv_f = '=' iv_t = 'diesen Umweg kaeme drueben ein Basistyp an, dessen Segmente es' ).
    a( iv_f = '=' iv_t = 'nicht gibt, und das Anlegen schluege fehl.' ).
    a( iv_f = 'B1' iv_t = 'Damit ein Basistyp drueben entsteht, muss das Dokument alles tragen,' ).
    a( iv_f = '=' iv_t = 'worauf er steht: Segmente, deren Datenelemente und eigene Domaenen.' ).
    a( iv_f = '=' iv_t = 'Das heisst Export mit Definitionsdaten und Verweistiefe 3. Bei' ).
    a( iv_f = '=' iv_t = 'Verweistiefe 2 fehlen die Domaenen.' ).
    a( iv_f = 'B1' iv_t = 'Nachrichtenklassen reisen mit allen Nachrichten und allen' ).
    a( iv_f = '=' iv_t = 'gepflegten Sprachen - anders als der uebrige Inhalt, der der' ).
    a( iv_f = '=' iv_t = 'Ausgabesprache folgt. Eine nur englisch gepflegte Klasse kaeme in' ).
    a( iv_f = '=' iv_t = 'einem deutschen Dokument sonst ohne eine einzige Nachricht an.' ).
    a( iv_f = '=' iv_t = 'Beim Import werden fehlende Nummern und Sprachen ergaenzt,' ).
    a( iv_f = '=' iv_t = 'vorhandene Texte bleiben unveraendert.' ).
    a( iv_f = 'B1' iv_t = 'Der GUI-Status eines Programms reist mit: Menues, Funktionstasten,' ).
    a( iv_f = '=' iv_t = 'Drucktastenleiste und Titel. Sie sind ein eigener' ).
    a( iv_f = '=' iv_t = 'Programmbestandteil und kommen mit dem Quelltext allein nicht' ).
    a( iv_f = '=' iv_t = 'mit; ein Report, der seinen Status setzt, liefe sonst auf einen' ).
    a( iv_f = '=' iv_t = 'Abbruch. Ein Programm ohne Status ist der Normalfall.' ).
    a( iv_f = 'B1' iv_t = 'Der Pflegedialog einer Tabelle oder eines Views reist vollstaendig' ).
    a( iv_f = '=' iv_t = 'mit: der Eintrag in TVDIR mit Funktionsgruppe und Bildnummern, die' ).
    a( iv_f = '=' iv_t = 'Formroutinen zu den Pflegeereignissen, die Berechtigungsgruppe,' ).
    a( iv_f = '=' iv_t = 'die Dynpros der Funktionsgruppe samt Ablauflogik und die' ).
    a( iv_f = '=' iv_t = 'Pflegetransaktion. Ohne diese Teile kaeme ein View an, den SM30' ).
    a( iv_f = '=' iv_t = 'nicht kennt - auch dann, wenn der View selbst fehlerfrei' ).
    a( iv_f = '=' iv_t = 'angelegt wurde.' ).
    a( iv_f = 'B1' iv_t = 'Die Funktionsgruppe und die Pflegetransaktion zieht der Export von' ).
    a( iv_f = '=' iv_t = 'selbst nach. Auf sie zeigt kein Querverweis; sie stehen nur im' ).
    a( iv_f = '=' iv_t = 'Pflegeeintrag.' ).
    a( iv_f = 'B1' iv_t = 'Der Eintrag in TVDIR wird im Zielsystem direkt geschrieben und' ).
    a( iv_f = '=' iv_t = 'haengt nicht am Transportauftrag. Erzeugen liesse er sich nur' ).
    a( iv_f = '=' iv_t = 'ueber SE54, und SE54 ist ein Dialog. Das Protokoll weist es aus,' ).
    a( iv_f = '=' iv_t = 'damit niemand den Eintrag im Auftrag sucht.' ).
    a( iv_f = 'B1' iv_t = 'Ein Dynpro, das es hier schon gibt, wird nicht ueberschrieben. Der' ).
    a( iv_f = '=' iv_t = 'Baustein kennt dafuer keinen Weg ohne SE51; das Protokoll meldet' ).
    a( iv_f = '=' iv_t = 'es je Bild.' ).
    a( iv_f = 'B1' iv_t = 'Pflegetransaktionen sind meist Parametertransaktionen - SM30 mit' ).
    a( iv_f = '=' iv_t = 'vorbelegtem Viewnamen. Die Vorbelegung wird mitgenommen und beim' ).
    a( iv_f = '=' iv_t = 'Import wieder aufgebaut. Startpunkt-Typ dafuer gibt es keinen;' ).
    a( iv_f = '=' iv_t = 'Transaktion und View-Cluster kommen ueber die Verweise oder' ).
    a( iv_f = '=' iv_t = 'ueber die Arbeitsliste.' ).
    a( iv_f = 'B1' iv_t = 'Bei einer CDS-Quelle entstehen SQL-View und Strukturobjekt beim' ).
    a( iv_f = '=' iv_t = 'Aktivieren von selbst; sie stehen nicht im Dokument.' ).
    a( iv_f = 'B1' iv_t = 'Sekundaerindizes einer Tabelle reisen mit und werden angelegt,' ).
    a( iv_f = '=' iv_t = 'nachdem die Tabelle aktiv ist.' ).
    a( iv_f = 'B1' iv_t = 'Klassen reisen als quelltextbasierte Fassung - der Text, den SE24' ).
    a( iv_f = '=' iv_t = 'zeigt. Autor, Aenderungsdatum und UUID bleiben im Quellsystem.' ).
    a( iv_f = 'B1' iv_t = 'Textelemente reisen in allen gepflegten Sprachen und werden je' ).
    a( iv_f = '=' iv_t = 'Sprache zurueckgeschrieben - nicht in die Anmeldesprache dessen,' ).
    a( iv_f = '=' iv_t = 'der importiert. Die Objektdokumentation von Programmen und' ).
    a( iv_f = '=' iv_t = 'Datenelementen reist ebenso je Sprache mit, auch wenn sie im' ).
    a( iv_f = '=' iv_t = 'lesbaren Dokument nicht angezeigt wird.' ).
    a( iv_f = 'B1' iv_t = 'Testlauf ist vorbelegt: der Report meldet, was er anlegen wuerde, und' ).
    a( iv_f = '=' iv_t = 'legt nichts an. Wer schreiben will, nimmt den Haken heraus.' ).
    a( iv_f = 'B1' iv_t = 'Ein Objekt, das es hier schon gibt, bleibt unangetastet, solange' ).
    a( iv_f = '=' iv_t = 'Bestehende Objekte ueberschreiben nicht gesetzt ist.' ).
    a( iv_f = 'B1' iv_t = 'Die Reihenfolge legt der Report fest: Domaenen, Datenelemente,' ).
    a( iv_f = '=' iv_t = 'Tabellen, Views, CDS-Quellen, Programme, Interfaces, Klassen,' ).
    a( iv_f = '=' iv_t = 'Funktionsgruppen, zuletzt View-Cluster und Transaktionen. Eine' ).
    a( iv_f = '=' iv_t = 'Tabelle ohne ihre Datenelemente liesse sich nicht aktivieren, ein' ).
    a( iv_f = '=' iv_t = 'Cluster ohne die Views seiner Knoten nicht aufklappen.' ).
    a( iv_f = 'B1' iv_t = 'Aktiviert wird gezielt: aus den inaktiven Objekten des Benutzers' ).
    a( iv_f = '=' iv_t = 'nimmt der Import nur die, die zum eben geschriebenen Objekt gehoeren.' ).
    a( iv_f = '=' iv_t = 'Angefangene Arbeit anderer bleibt unberuehrt.' ).
    a( iv_f = 'B1' iv_t = 'Bei einem lokalen Paket wird kein Auftrag angefordert, sonst der' ).
    a( iv_f = '=' iv_t = 'angegebene verwendet. Das gilt je Objekt: wer ein lokales Paket' ).
    a( iv_f = '=' iv_t = 'auf ein transportfaehiges umlenkt, bekommt den Auftrag auch dann' ).
    a( iv_f = '=' iv_t = 'angehaengt, wenn das Zielpaket oben lokal war.' ).
    a( iv_f = 'B1' iv_t = 'Ein Objekt landet nicht im Auftrag, sondern in einer Aufgabe' ).
    a( iv_f = '=' iv_t = 'darunter. Fehlt eine offene Aufgabe, lehnt das Korrektursystem ohne' ).
    a( iv_f = '=' iv_t = 'Dialog ab - mit einer Meldung, die nach fehlender Berechtigung' ).
    a( iv_f = '=' iv_t = 'aussieht. Aufgabe anlegen, wenn noetig legt sie deshalb vor dem Lauf' ).
    a( iv_f = '=' iv_t = 'unter dem angegebenen Auftrag an. Ohne Haken warnt der Report nur.' ).
    a( iv_f = 'B1' iv_t = 'Zielpaket gilt fuer alles. Wer die Paketstruktur des Quellsystems' ).
    a( iv_f = '=' iv_t = 'behalten oder umlenken will, nimmt die vier Regelzeilen darunter:' ).
    a( iv_f = '=' iv_t = 'links das Paket, in dem das Objekt drueben lag, rechts das Paket,' ).
    a( iv_f = '=' iv_t = 'in dem es hier landen soll - etwa $TMP nach ZBLE_WM. Was keine' ).
    a( iv_f = '=' iv_t = 'Regel trifft, geht ins Zielpaket, oder mit Quellpaket' ).
    a( iv_f = '=' iv_t = 'beibehalten dorthin, wo es herkam.' ).
    a( iv_f = 'B1' iv_t = 'Das Quellpaket steht im Dokument; der Export schreibt es in die' ).
    a( iv_f = '=' iv_t = 'Objektreferenz. Ein Dokument aus einer aelteren Fassung hat es' ).
    a( iv_f = '=' iv_t = 'nicht - dann gilt das Zielpaket.' ).
    a( iv_f = 'B1' iv_t = 'Ein Paket, das es hier nicht gibt, wird nicht angelegt. Es bleibt' ).
    a( iv_f = '=' iv_t = 'beim Zielpaket, und das Protokoll sagt warum. Gemeldet wird eine' ).
    a( iv_f = '=' iv_t = 'Zeile je Regel, nicht je Objekt.' ).
    a( iv_f = 'B1' iv_t = 'Nach dem Lauf wird jedes Objekt geprueft: DDIC-Objekte auf die' ).
    a( iv_f = '=' iv_t = 'aktive Fassung, Programme mit einem Syntax-Check. Gemeldet wird nur,' ).
    a( iv_f = '=' iv_t = 'was auffaellt. Angelegt heisst nicht brauchbar - einer Struktur kann' ).
    a( iv_f = '=' iv_t = 'ein Datenelement fehlen, und dann aktiviert sie nicht.' ).
    a( iv_f = 'B1' iv_t = 'Scheitert ein Schritt, stehen im Protokoll der Rueckgabecode und' ).
    a( iv_f = '=' iv_t = 'die Meldung des SAP-Bausteins. Scheitert eine Aktivierung, nennt es' ).
    a( iv_f = '=' iv_t = 'das Objekt, auf dem das gescheiterte steht und das es hier nicht' ).
    a( iv_f = '=' iv_t = 'aktiv gibt - etwa die Domaene unter einem Datenelement.' ).

    a( iv_f = 'U1' iv_t = 'Hinweise' ).
    a( iv_f = 'AS' iv_t = 'Objektdokumentation und Verwendungsnachweis erzeugen je Objekt eigene' ).
    a( iv_f = '=' iv_t = 'Datenbankzugriffe und bestimmen die Laufzeit. Kurztexte stammen aus' ).
    a( iv_f = '=' iv_t = 'gepufferten Texttabellen und fallen nicht ins Gewicht.' ).
    a( iv_f = 'AS' iv_t = 'Ist in der gewaehlten Sprache kein Kurztext gepflegt, wird auf Englisch' ).
    a( iv_f = '=' iv_t = 'zurueckgegriffen. Objekte ohne Text in jeder Sprache bleiben leer.' ).
    a( iv_f = 'AS' iv_t = 'Pakete ohne Katalogeintrag werden mit einem Vermerk uebergangen; der' ).
    a( iv_f = '=' iv_t = 'Lauf bricht nicht ab.' ).
    a( iv_f = 'AS' iv_t = 'Geloeschte Objekte, deren Loeschauftrag noch nicht freigegeben ist,' ).
    a( iv_f = '=' iv_t = 'stehen weiter im Objektkatalog. Sie werden uebergangen.' ).
    a( iv_f = 'AS' iv_t = 'Im Paketmodus endet das Dokument an der Paketgrenze. Was die' ).
    a( iv_f = '=' iv_t = 'Objekte ausserhalb verwenden, steht in der Aufrufliste, wird aber' ).
    a( iv_f = '=' iv_t = 'nicht als eigenes Kapitel dokumentiert. Wer die Nachbarschaft' ).
    a( iv_f = '=' iv_t = 'braucht, startet vom tragenden Objekt mit Verweistiefe 2.' ).

  ENDMETHOD.

  METHOD build_atc.

    CLEAR mt_line.

    a( iv_f = 'U1' iv_t = 'Verwendung' ).
    a( iv_f = 'AS' iv_t = 'Der Report dokumentiert die Pruefkonfiguration des Systems: welche' ).
    a( iv_f = '=' iv_t = 'Pruefvarianten es gibt, welche Checks darin stecken, mit welcher' ).
    a( iv_f = '=' iv_t = 'Prioritaet deren Meldungen laufen und mit welchem Pseudokommentar' ).
    a( iv_f = '=' iv_t = 'oder Pragma sich eine Meldung unterdruecken laesst.' ).
    a( iv_f = 'AS' iv_t = 'Das ist die dritte Sicht neben Customizing und Entwicklung: nicht' ).
    a( iv_f = '=' iv_t = 'was im System steht, sondern woran es gemessen wird.' ).
    a( iv_f = 'AS' iv_t = 'Die Ausgabe erfolgt als XML und als HTML.' ).
    a( iv_f = 'U1' iv_t = 'Voraussetzungen' ).
    a( iv_f = 'AS' iv_t = 'Leseberechtigung fuer den Code Inspector. Fuer Download und Anzeige' ).
    a( iv_f = '=' iv_t = 'im Browser ist Dialogbetrieb erforderlich; im Hintergrund steht nur' ).
    a( iv_f = '=' iv_t = 'die Ablage auf dem Applikationsserver zur Verfuegung.' ).
    a( iv_f = 'U1' iv_t = 'Selektion' ).
    a( iv_f = 'AS' iv_t = 'Auswahl' ).
    a( iv_f = 'B1' iv_t = 'Modus: V nimmt eine Pruefvariante, K den Katalog aller aktivierten' ).
    a( iv_f = '=' iv_t = 'Checks. Die Variante beantwortet, was geprueft wird; der Katalog,' ).
    a( iv_f = '=' iv_t = 'was geprueft werden koennte.' ).
    a( iv_f = 'B1' iv_t = 'Pruefvariante: die Wertehilfe zeigt die nicht-versteckten Varianten' ).
    a( iv_f = '=' iv_t = 'mit Eigentuemer und Text.' ).
    a( iv_f = 'B1' iv_t = 'Eigentuemer: leer heisst globale Variante. Der Code Inspector' ).
    a( iv_f = '=' iv_t = 'fuehrt persoenliche Varianten unter dem Namen ihres Eigentuemers.' ).
    a( iv_f = 'B1' iv_t = 'Alle Varianten: dokumentiert jede Variante statt einer. Versteckte' ).
    a( iv_f = '=' iv_t = 'einbeziehen nimmt auch die auf, die die Wertehilfe nicht zeigt -' ).
    a( iv_f = '=' iv_t = 'das sind auf einem Standardsystem die meisten.' ).
    a( iv_f = 'AS' iv_t = 'Umfang' ).
    a( iv_f = 'B1' iv_t = 'Meldungen je Check: gibt zu jedem Check die moeglichen Meldungen' ).
    a( iv_f = '=' iv_t = 'mit Code, Prioritaet und Text aus. Ohne diesen Haken bleibt es bei' ).
    a( iv_f = '=' iv_t = 'der Liste der Checks.' ).
    a( iv_f = 'B1' iv_t = 'Kundenpriorisierung ausweisen: stellt die kundeneigene Prioritaet' ).
    a( iv_f = '=' iv_t = 'neben die der Checkklasse. Genau dort sieht man, wo ein System vom' ).
    a( iv_f = '=' iv_t = 'Standard abweicht.' ).
    a( iv_f = 'B1' iv_t = 'Pseudokommentar und Pragma: die beiden Wege, eine Meldung im' ).
    a( iv_f = '=' iv_t = 'Quelltext zu unterdruecken.' ).
    a( iv_f = 'B1' iv_t = 'Erteilte Ausnahmen zaehlen: wie viele Ausnahmen es zu einer' ).
    a( iv_f = '=' iv_t = 'Meldung gibt. Gezaehlt wird, dass es eine Ausnahme gibt, nicht dass' ).
    a( iv_f = '=' iv_t = 'sie genehmigt ist - der Schluessel des Genehmigungsstands wechselt' ).
    a( iv_f = '=' iv_t = 'zwischen Staenden.' ).
    a( iv_f = 'B1' iv_t = 'Nach Kategorie gliedern: schiebt eine Ebene zwischen Variante und' ).
    a( iv_f = '=' iv_t = 'Check. Ohne den Haken stehen die Checks flach unter der Variante.' ).
    a( iv_f = 'U1' iv_t = 'Ausgabe' ).
    a( iv_f = 'B1' iv_t = 'HTML erzeugen/anzeigen: lesbare Fassung mit Inhaltsverzeichnis.' ).
    a( iv_f = 'B1' iv_t = 'XML erzeugen/ausgeben: fuehrendes Format, wieder einlesbar.' ).
    a( iv_f = 'B1' iv_t = 'HTML einklappen ab Zeilen: laengere Meldungslisten stehen im HTML' ).
    a( iv_f = '=' iv_t = 'zugeklappt hinter einer Zeile mit Bezeichnung und Umfang.' ).
    a( iv_f = 'B1' iv_t = 'Roundtrip pruefen: serialisiert, liest wieder ein, serialisiert' ).
    a( iv_f = '=' iv_t = 'erneut und vergleicht. Schreibt nichts in das System zurueck.' ).
    a( iv_f = 'B1' iv_t = 'Download auf PC und Ablage Appl.-Server schreiben dieselbe Datei' ).
    a( iv_f = '=' iv_t = 'in UTF-8.' ).
    a( iv_f = 'B1' iv_t = 'Dateiname: vorbelegt mit System, Variante bzw. Modus, Datum und' ).
    a( iv_f = '=' iv_t = 'Uhrzeit, ohne Endung. Das Feld ist ueberschreibbar.' ).
    a( iv_f = 'U1' iv_t = 'Hinweise' ).
    a( iv_f = 'AS' iv_t = 'Die Checkliste einer Pruefvariante steht nicht lesbar in der' ).
    a( iv_f = '=' iv_t = 'Datenbank - SCICHKV_PA ist ein INDX-Cluster. Der Report liest sie' ).
    a( iv_f = '=' iv_t = 'deshalb ueber die Schnittstellen des Code Inspectors.' ).
    a( iv_f = 'AS' iv_t = 'Ein Check, den die Variante nennt und den es hier nicht mehr gibt,' ).
    a( iv_f = '=' iv_t = 'bekommt trotzdem ein Kapitel mit dem Vermerk nicht ladbar. Nach' ).
    a( iv_f = '=' iv_t = 'einem Upgrade ist das der Normalfall, und eine Luecke in der' ).
    a( iv_f = '=' iv_t = 'Konfiguration gehoert ins Dokument.' ).
    a( iv_f = 'AS' iv_t = 'Ein vollstaendiger Katalog umfasst mehrere hundert Checks mit' ).
    a( iv_f = '=' iv_t = 'einigen tausend Meldungen. Fuer solche Laeufe empfiehlt sich' ).
    a( iv_f = '=' iv_t = 'Hintergrundverarbeitung mit Ablage auf dem Applikationsserver.' ).

  ENDMETHOD.

  METHOD run.

    build_img( ).
    save( 'ZDOCUMIZER_IMG' ).

    build_dev( ).
    save( 'ZDOCUMIZER_DEV' ).

    build_atc( ).
    save( 'ZDOCUMIZER_ATC' ).

    COMMIT WORK AND WAIT.
    WRITE: / 'Dokumentation gesichert.'.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_docu( )->run( ).