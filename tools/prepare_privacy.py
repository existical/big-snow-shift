"""Derive the offline policy from the uploadable HTML without external services."""
from html.parser import HTMLParser
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
URL = "https://www.existical.com/privacy/big-snow-shift/"


class PolicyText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.include = False
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag == "header" or tag == "section":
            self.include = True
        if self.include:
            if tag in ("p", "h1", "h2", "h3"):
                self.parts.append("\n\n")
            elif tag == "li":
                self.parts.append("\n• ")

    def handle_endtag(self, tag):
        if tag in ("header", "section"):
            self.include = False
            self.parts.append("\n\n")

    def handle_data(self, data):
        if self.include and data.strip():
            self.parts.append(data)


def main():
    source = ROOT / "docs/privacy/big-snow-shift/index.html"
    parser = PolicyText()
    parser.feed(source.read_text(encoding="utf-8"))
    text = re.sub(r"\n{3,}", "\n\n", "".join(parser.parts)).strip()
    text += "\n\nPublished policy: " + URL + "\n"
    output = ROOT / "assets/licenses/PRIVACY_POLICY.txt"
    output.write_text(text, encoding="utf-8", newline="\n")
    print("Offline privacy policy prepared: " + str(output.relative_to(ROOT)))


if __name__ == "__main__":
    main()
