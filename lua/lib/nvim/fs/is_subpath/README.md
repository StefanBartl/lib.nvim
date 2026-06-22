Die Funktion prüft, ob `path` innerhalb von `base` liegt (inkl. Gleichheit). Ablauf in Schritten:

1. Beide Pfade werden normalisiert (`norm`): Trennzeichen vereinheitlichen, `.`/`..`-Segmente auflösen, überflüssige Slashes entfernen und trailing-separator standardisiert.
2. Wenn die normalisierten Strings exakt gleich sind, gilt `path` als Unterpfad (gleiches Verzeichnis → `true`).
3. Wenn die Länge von `path` kürzer oder gleich der Länge von `base` ist (aber nicht gleich, da oberer Check schon false gemacht hätte), kann `path` nicht in `base` liegen → `false`.
4. Der Systempfadtrenner wird aus `package.config` ermittelt (erstes Zeichen). Falls `base` nicht mit dem Separator endet, wird ein Separator angehängt — so wird sichergestellt, dass nur ganze Verzeichnisnamen als Präfix zählen (z. B. `/foo/bar` ≠ `/foo/b` weil `/foo/b` + `/` zu `/foo/b/`).
5. Schließlich wird geprüft, ob die ersten `#base` Zeichen von `path` gleich `base` sind; ist das der Fall, liegt `path` innerhalb von `base` → `true`, sonst `false`.

