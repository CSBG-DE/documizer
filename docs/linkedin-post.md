# LinkedIn-Post — consiness Documizer

## Post

Zwei Sorten Berater lesen diesen Post.

Die einen sollen ein SAP-System dokumentieren, das sie nicht gebaut
haben — oder sich in eines einarbeiten, zu dem es keine Dokumentation
gibt. Die anderen würden ihre KI gern zu genau diesem System befragen,
können ihr das System aber nicht zeigen.

Für beide gibt es jetzt dasselbe Werkzeug: den **consiness Documizer**.

**Installation: Copy, Paste, F8.**
Zwei ABAP-Reports, jeder eine einzige Quelle. In SE38 einfügen,
aktivieren, starten. Keine Zusatzobjekte, keine Textelemente, kein
Transport, kein Add-on, keine Cloud-Verbindung. Auch im Kundensystem, in
das du sonst nichts installieren darfst.

**Für alle, die dokumentieren müssen**

Die Dokumentation ist längst da. Sie liegt nur an vierzehn verschiedenen
Stellen. Die IMG-Aktivität weiß, wozu die Tabelle gut ist. Das
Datenelement weiß, was das Feld bedeutet. Der Verwendungsnachweis weiß,
wer darauf zugreift. Der Quelltext weiß, was wirklich passiert. Der
Documizer trägt das zusammen:

▸ **IMG-Report** — der Einführungsleitfaden als Struktur, mit den
SAP-Originaltexten zu jeder Aktivität und dem tatsächlichen Customizing
bis auf die Tabelleninhalte. Wahlweise mit Projektstatus.

▸ **Entwickler-Report** — Einstieg an einem Paket oder an einem einzelnen
Objekt: Report, Klasse, Funktionsbaustein, Tabelle, View, CDS View.
Kurztexte, Feldlisten, Textelemente, Quelltext, Verwendungsnachweis und
die verwendeten Objekte — rekursiv bis zu der Tiefe, die du angibst.
SAP-Standard lässt sich ausblenden.

Heraus kommt HTML zum Lesen und XML zur Weiterverarbeitung. Eine Datei,
in sich geschlossen, ohne externe Abhängigkeiten.

**Für alle, die Input für die KI brauchen**

Deine KI kennt dein System nicht. Kein MCP-Zugang, kein Joule, kein
Netzweg vom Modell zum SAP — und schon fehlt dem Assistenten genau der
Kontext, der die Antwort brauchbar machen würde.

Der Documizer schließt die Lücke mit Bordmitteln. Du erzeugst die Datei,
du hängst sie an, du fragst. Fachlicher Zusammenhang, Feldbedeutungen,
Abhängigkeiten und Quelltext liegen dem Modell in einer Struktur vor,
mit der es arbeiten kann.

Du behältst dabei die Kontrolle darüber, was das System verlässt: genau
die eine Datei, die du selbst weitergibst. Nichts läuft im Hintergrund.

**Quelloffen.** Beide Reports liegen offen — anschauen, mitnehmen,
anpassen:
https://gitea.consiness.dev/gathmann/Documizer

Wir setzen den Documizer in eigenen Projekten ein: für Übergaben, für
Analysen in fremden Systemen und als Vorarbeit für KI-gestützte
Auswertung. Wenn du ihn ausprobierst, interessiert mich, was dir fehlt.

#SAP #ABAP #S4HANA #Customizing #Dokumentation #KI #OpenSource #consiness

---

## Hinweise zur Verwendung

- **Vor dem Posten prüfen:** Ist das Repository tatsächlich öffentlich
  erreichbar? Die URL im Post ist die interne Gitea-Adresse. Aus dem
  Internet ohne Anmeldung aufrufen, sonst zeigt der Post ins Leere.
- Länge rund 2.500 Zeichen, unter dem LinkedIn-Limit von 3.000. Der
  Umbruch „mehr anzeigen" liegt nach den ersten Absätzen; der Aufhänger
  mit den zwei Zielgruppen steht davor.
- Fehlt im Repository noch eine Lizenzdatei, vor dem Post nachholen —
  „quelloffen" ohne Lizenz ist rechtlich unklar.
