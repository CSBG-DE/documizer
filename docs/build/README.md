# Produktdokumentation bauen

Zwei Skripte, eine Gestaltung: `build_docx.js` erzeugt die deutsche Fassung,
`build_docx_en.js` die englische. Inhalt und Gestaltung stehen jeweils zusammen in der Datei,
das Logo liegt daneben.

```
npm i -g docx
NODE_PATH="$APPDATA/npm/node_modules" node build_docx.js    ../Documizer_Produktdokumentation.docx
NODE_PATH="$APPDATA/npm/node_modules" node build_docx_en.js ../Documizer_Product_Documentation.docx
```

Beide Fassungen muessen inhaltlich gleich bleiben: wer ein Kapitel aendert, aendert es in beiden.
Die Akzentfarbe steht in beiden Skripten als eine Konstante (`ACC`) und ist das Markenblau aus
`csbg_logo.png`.

Das PDF entsteht aus dem Word-Dokument (Datei → Exportieren → PDF). Dabei das
Inhaltsverzeichnis aktualisieren lassen, sonst stehen dort die Seitenzahlen des vorigen Stands.

Das Skript gehoert in die Versionsverwaltung, weil die Dokumentation sonst nur als Ergebnis
existiert: ein neues Kapitel waere jedes Mal Handarbeit im fertigen Dokument.
