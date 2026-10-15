"""Rule B3: no franchise names in generated or shipped text.

tools/castle/denylist.sha256 holds SHA-256 hashes of normalised forbidden words
(lowercase a-z only), never the words themselves, so the repo stays clean. Every
word and every pair of adjacent words of the scanned files is hashed and looked up.

  python3 -m castle.denylist --add WORD     add a word (run from tools/)
  python3 -m castle.denylist                scan the default files
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HASHES = os.path.join(HERE, "denylist.sha256")
SCANNED = ["content", "localization/translations.csv", "levels/castle", "nakama/content", "resources"]
TEXT_EXT = (".json", ".csv", ".tscn", ".tres", ".lua", ".md", ".txt")


def h(word):
    return hashlib.sha256(word.encode()).hexdigest()


def load():
    with open(HASHES) as f:
        return {line.strip() for line in f if line.strip() and not line.startswith("#")}


def tokens(text):
    words = re.findall(r"[a-z]+", text.lower())
    yield from words
    for a, b in zip(words, words[1:]):
        yield a + b


def scan_text(text, hashes):
    hits = set()
    for tok in tokens(text):
        if h(tok) in hashes:
            hits.add(tok)
    return hits


def scan(root=os.path.dirname(os.path.dirname(HERE)), paths=SCANNED):
    hashes = load()
    found = []
    for p in paths:
        full = os.path.join(root, p)
        files = [full] if os.path.isfile(full) else [os.path.join(d, f) for d, _, fs in os.walk(full) for f in fs]
        for f in sorted(files):
            if not f.endswith(TEXT_EXT):
                continue
            with open(f, encoding="utf-8", errors="ignore") as fh:
                for n, line in enumerate(fh, 1):
                    for tok in scan_text(line, hashes):
                        found.append((os.path.relpath(f, root), n, tok))
    return found


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--add":
        word = re.sub(r"[^a-z]", "", sys.argv[2].lower())
        with open(HASHES, "a") as f:
            f.write(h(word) + "\n")
        print("added")
        return
    found = scan()
    for f, n, _tok in found:
        print(f"{f}:{n}: forbidden name (B3)")
    sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
