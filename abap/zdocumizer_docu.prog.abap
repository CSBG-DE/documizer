REPORT zdocumizer_docu.

************************************************************************
* Legt die SAP-Reportdokumentation zu ZDOCUMIZER_IMG und ZDOCUMIZER_DEV
* an. Dokumentationsobjekte sind eigene Repository-Objekte und kommen beim
* Kopieren des Quelltextes nicht mit; dieser Report erzeugt sie im
* Zielsystem neu.
*
* Nach dem Lauf erscheint der Text in SE38 unter Dokumentation und ueber
* die Sprungmarke im Selektionsbild.
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

    a( iv_f = 'U1' iv_t = 'Ausgabe' ).
    a( iv_f = 'B1' iv_t = 'XML erzeugen/ausgeben: fuehrendes Format, wieder einlesbar.' ).
    a( iv_f = 'B1' iv_t = 'HTML erzeugen/anzeigen: lesbare Fassung mit Inhaltsverzeichnis.' ).
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
    a( iv_f = 'AS' iv_t = 'Der Report ermittelt ausgehend von einem Startpaket alle Unterpakete' ).
    a( iv_f = '=' iv_t = 'und die darin enthaltenen Entwicklungsobjekte und erzeugt daraus eine' ).
    a( iv_f = '=' iv_t = 'kapitelweise gegliederte Entwicklerdokumentation.' ).
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
    a( iv_f = 'AS' iv_t = 'Startpaket' ).
    a( iv_f = 'B1' iv_t = 'Paket: Einstiegspaket, Pflichtangabe.' ).
    a( iv_f = 'B1' iv_t = 'Unterpakete rekursiv: bezieht den gesamten Unterbaum ein.' ).
    a( iv_f = 'B1' iv_t = 'Lokale Pakete einbeziehen: beruecksichtigt auch Pakete des' ).
    a( iv_f = '=' iv_t = 'Kurzzeitnamensraums.' ).

    a( iv_f = 'AS' iv_t = 'Umfang' ).
    a( iv_f = 'B1' iv_t = 'Objekttyp und Objektname grenzen die Objektliste ein.' ).
    a( iv_f = 'B1' iv_t = 'Max. Objekte begrenzt die Aufnahme. Die Gesamtzahl der gefundenen' ).
    a( iv_f = '=' iv_t = 'Objekte bleibt im Dokument vermerkt.' ).
    a( iv_f = 'B1' iv_t = 'Objektdokumentation: liest die klassische Objektdokumentation fuer' ).
    a( iv_f = '=' iv_t = 'Programme, Transaktionen und Datenelemente.' ).
    a( iv_f = 'B1' iv_t = 'Details: ergaenzt Feldlisten fuer Tabellen und Views, Komponenten fuer' ).
    a( iv_f = '=' iv_t = 'Klassen und Interfaces sowie verwendete Objekte fuer CDS Views.' ).
    a( iv_f = 'B1' iv_t = 'Quelltext ausgeben: nimmt den Quelltext auf. Fuer Funktionsgruppen und' ).
    a( iv_f = '=' iv_t = 'Klassen werden alle zugehoerigen Includes gelesen.' ).
    a( iv_f = 'B1' iv_t = 'Max. Zeilen je Objekt begrenzt den Quelltext. Wird die Grenze' ).
    a( iv_f = '=' iv_t = 'erreicht, steht der Hinweis mit der Gesamtzahl im Quelltext selbst.' ).
    a( iv_f = 'B1' iv_t = 'Verwendungsnachweis: wertet die Querverweistabellen der Workbench aus.' ).
    a( iv_f = '=' iv_t = 'Die Fundstellen werden als Includes ausgewiesen.' ).
    a( iv_f = 'B1' iv_t = 'Max. Verwendungen je Objekt begrenzt den Nachweis getrennt von der' ).
    a( iv_f = '=' iv_t = 'Objektgrenze.' ).

    a( iv_f = 'U1' iv_t = 'Ausgabe' ).
    a( iv_f = 'B1' iv_t = 'XML erzeugen/ausgeben: fuehrendes Format, wieder einlesbar.' ).
    a( iv_f = 'B1' iv_t = 'HTML erzeugen/anzeigen: lesbare Fassung mit Inhaltsverzeichnis.' ).
    a( iv_f = 'B1' iv_t = 'Roundtrip pruefen: serialisiert, liest wieder ein, serialisiert erneut' ).
    a( iv_f = '=' iv_t = 'und vergleicht. Schreibt nichts in das System zurueck.' ).
    a( iv_f = 'B1' iv_t = 'Download auf PC und Ablage Appl.-Server schreiben dieselbe Datei in' ).
    a( iv_f = '=' iv_t = 'UTF-8. Der Dateiname enthaelt System, Datum und Uhrzeit.' ).

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