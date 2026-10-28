# Lokale Änderungen gegenüber iced_video_player 0.6.0

Alle Stellen sind im Code mit `ReVideo patch` markiert.

- `src/video.rs`: Bei Pause liefert GStreamer bei jedem Abruf dasselbe Preroll-Bild. Es wird
  nur noch als neu gemeldet, wenn Buffer oder Zeitstempel sich ändern (vorher ~60 Uploads/s).
- `src/video_player.rs`: Beim Abspielen wird mit doppelter Video-Framerate statt mit jeder
  Bildschirmaktualisierung gezeichnet. Bei Pause nur noch bis 2 s nach einer Eingabe oder
  einem neuen Bild (vorher dauerhaft ~30/s).
- `src/video.rs`: Neue Funktion `Video::frame_position()` liefert den Zeitstempel des
  angezeigten Frames; `position()` fragt die Pipeline und kann einen Frame hinterherhinken.

Bei einem Update der Crate: neue Version hierher kopieren und die markierten Stellen übertragen.
