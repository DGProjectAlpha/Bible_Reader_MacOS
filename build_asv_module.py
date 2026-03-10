#!/usr/bin/env python3
"""Convert ASV JSON (tagged format with Strong's) to SQLite .brbmod for macOS BibleReader."""

import json
import sqlite3
import os

INPUT = "/workspace/BibleReader/src/data/asv.json"
OUTPUT = "/workspace/BibleReaderMac/BibleReaderMac/BundledModules/ASV.brbmod"

def main():
    print("Loading ASV JSON...")
    with open(INPUT, "r") as f:
        books = json.load(f)

    print(f"Loaded {len(books)} books")

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    conn = sqlite3.connect(OUTPUT)
    cur = conn.cursor()

    cur.executescript("""
        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE TABLE verses (
            book TEXT NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            text TEXT NOT NULL
        );

        CREATE TABLE word_tags (
            verse_id TEXT NOT NULL,
            word_index INTEGER NOT NULL,
            word TEXT NOT NULL,
            strongs_number TEXT
        );

        CREATE INDEX idx_verses_book_chapter ON verses(book, chapter);
        CREATE INDEX idx_word_tags_verse_id ON word_tags(verse_id);
    """)

    metadata = {
        "name": "American Standard Version",
        "abbreviation": "ASV",
        "language": "en",
        "format": "tagged",
        "version": "1",
        "versification_scheme": "kjv",
        "copyright": "Public Domain",
        "notes": "American Standard Version (1901) with Strong's Concordance numbers"
    }
    cur.executemany("INSERT INTO metadata (key, value) VALUES (?, ?)", metadata.items())

    verse_rows = []
    tag_rows = []
    total_verses = 0
    total_tags = 0

    for book in books:
        book_name = book["name"]
        chapters = book["chapters"]

        for ch_idx, chapter in enumerate(chapters):
            ch_num = ch_idx + 1
            for v_idx, verse_words in enumerate(chapter):
                v_num = v_idx + 1
                total_verses += 1

                text = " ".join(w["word"] for w in verse_words)
                verse_rows.append((book_name, ch_num, v_num, text))

                verse_id = f"{book_name}:{ch_num}:{v_num}"
                for w_idx, word_token in enumerate(verse_words):
                    strongs_list = word_token.get("strongs", [])
                    if strongs_list:
                        for s in strongs_list:
                            tag_rows.append((verse_id, w_idx, word_token["word"], s))
                            total_tags += 1
                    else:
                        tag_rows.append((verse_id, w_idx, word_token["word"], None))
                        total_tags += 1

    print(f"Inserting {total_verses} verses...")
    cur.executemany("INSERT INTO verses (book, chapter, verse, text) VALUES (?, ?, ?, ?)", verse_rows)

    print(f"Inserting {total_tags} word tags...")
    cur.executemany("INSERT INTO word_tags (verse_id, word_index, word, strongs_number) VALUES (?, ?, ?, ?)", tag_rows)

    conn.commit()
    conn.close()

    size_mb = os.path.getsize(OUTPUT) / (1024 * 1024)
    print(f"Done! {OUTPUT}")
    print(f"  {total_verses} verses, {total_tags} word tags, {size_mb:.1f} MB")

if __name__ == "__main__":
    main()
