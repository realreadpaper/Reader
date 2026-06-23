#!/bin/bash
set -e
ROOT=$(mktemp -d)
mkdir -p "$ROOT/META-INF" "$ROOT/OEBPS"
cat > "$ROOT/mimetype" <<'EOF'
application/epub+zip
EOF
cat > "$ROOT/META-INF/container.xml" <<'EOF'
<?xml version="1.0"?>
<container version="1.0">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF
cat > "$ROOT/OEBPS/content.opf" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Minimal Book</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:identifier id="bookid">test-001</dc:identifier>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
  </spine>
</package>
EOF
cat > "$ROOT/OEBPS/chapter1.xhtml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter 1</title></head>
<body><h1>Chapter 1</h1><p>Content of chapter one.</p></body>
</html>
EOF
cat > "$ROOT/OEBPS/toc.ncx" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="test-001"/></head>
  <docTitle><text>Minimal Book</text></docTitle>
  <navMap>
    <navPoint id="ch1" playOrder="1">
      <navLabel><text>Chapter 1</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
EOF
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SCRIPT_DIR/minimal.epub"
rm -f "$OUT"
(cd "$ROOT" && zip -X0 "$OUT" mimetype >/dev/null)
(cd "$ROOT" && zip -rDX9 "$OUT" META-INF OEBPS >/dev/null)
rm -rf "$ROOT"
echo "Created $OUT"
