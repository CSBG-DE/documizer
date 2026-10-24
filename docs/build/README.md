# Produktdokumentation bauen

`build_docx.js` erzeugt `docs/Documizer_Produktdokumentation.docx` aus einer einzigen Quelle —
Inhalt und Gestaltung stehen zusammen in dieser Datei, das Logo liegt daneben.

```
npm i -g docx
NODE_PATH="$APPDATA/npm/node_modules" node build_docx.js ../Documizer_Produktdokumentation.docx
```

Das PDF entsteht aus dem Word-Dokument (Datei → Exportieren → PDF). Dabei das
Inhaltsverzeichnis aktualisieren lassen, sonst stehen dort die Seitenzahlen des vorigen Stands.

Das Skript gehoert in die Versionsverwaltung, weil die Dokumentation sonst nur als Ergebnis
existiert: ein neues Kapitel waere jedes Mal Handarbeit im fertigen Dokument.
