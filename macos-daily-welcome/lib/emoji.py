#!/usr/bin/env python3
"""Turn spoken emoji into emoji.

"tell mama happy birthday with a party emoji" should send "Happy birthday
🎉", not the words "with a party emoji". This finds those phrases, works
out which emoji is meant, and puts it where it belongs.

The table covers what people actually say out loud. Anything it doesn't
know goes to the model, if a key is set, and the answer is remembered so
the same description never costs two requests.
"""

import json
import os
import re
import sys
import urllib.request
from pathlib import Path

TABLE = {
    "smile": "🙂", "smiley": "😄", "smiling": "😄", "happy": "😄", "grin": "😁",
    "laugh": "😂", "laughing": "😂", "crying laughing": "😂", "lol": "😂",
    "wink": "😉", "winking": "😉", "tongue": "😛", "silly": "🤪",
    "sad": "🙁", "crying": "😢", "cry": "😢", "sobbing": "😭", "upset": "😞",
    "angry": "😠", "mad": "😠", "furious": "😡",
    "love": "❤️", "heart": "❤️", "hearts": "💕", "red heart": "❤️",
    "broken heart": "💔", "heart eyes": "😍", "kiss": "😘", "blush": "😊",
    "blushing": "😊", "shy": "😳", "embarrassed": "😳",
    "thumbs up": "👍", "thumbs down": "👎", "ok": "👌", "okay": "👌",
    "clap": "👏", "clapping": "👏", "wave": "👋", "waving": "👋",
    "pray": "🙏", "praying": "🙏", "thanks": "🙏", "please": "🙏",
    "muscle": "💪", "strong": "💪", "fist": "✊", "fist bump": "👊",
    "peace": "✌️", "point": "👉", "hand": "✋",
    "fire": "🔥", "hot": "🔥", "star": "⭐", "sparkle": "✨", "sparkles": "✨",
    "hundred": "💯", "one hundred": "💯", "party": "🎉", "celebrate": "🎉",
    "confetti": "🎊", "balloon": "🎈", "gift": "🎁", "cake": "🎂",
    "birthday": "🎂", "champagne": "🍾", "cheers": "🥂", "beer": "🍺",
    "coffee": "☕", "tea": "🍵", "pizza": "🍕", "burger": "🍔", "food": "🍽️",
    "sun": "☀️", "sunny": "☀️", "moon": "🌙", "rain": "🌧️", "snow": "❄️",
    "rainbow": "🌈", "flower": "🌸", "rose": "🌹", "tree": "🌳", "plant": "🌱",
    "dog": "🐶", "cat": "🐱", "bear": "🐻", "monkey": "🐵", "bird": "🐦",
    "car": "🚗", "plane": "✈️", "flight": "✈️", "train": "🚆", "rocket": "🚀",
    "home": "🏠", "house": "🏠", "work": "💼", "money": "💰", "dollar": "💵",
    "phone": "📱", "call": "📞", "mail": "📧", "email": "📧", "computer": "💻",
    "clock": "🕐", "time": "⏰", "alarm": "⏰", "calendar": "📅", "late": "⏰",
    "check": "✅", "tick": "✅", "done": "✅", "cross": "❌", "no": "❌",
    "warning": "⚠️", "question": "❓", "exclamation": "❗", "eyes": "👀",
    "think": "🤔", "thinking": "🤔", "shrug": "🤷", "facepalm": "🤦",
    "sleep": "😴", "sleepy": "😴", "tired": "😪", "sick": "🤒",
    "cool": "😎", "sunglasses": "😎", "nerd": "🤓", "brain": "🧠",
    "skull": "💀", "ghost": "👻", "alien": "👽", "robot": "🤖",
    "music": "🎵", "guitar": "🎸", "game": "🎮", "book": "📚", "pencil": "✏️",
    "trophy": "🏆", "medal": "🏅", "target": "🎯", "chart": "📈",
    "wink face": "😉", "crossed fingers": "🤞", "salute": "🫡",
}

CACHE = Path(os.environ.get("WELCOME_STATE_DIR",
                            Path.home() / ".local/state/daily-welcome")) / "emoji-cache"

LEAD_IN = {"with", "and", "plus", "add", "use", "a", "an", "the", "some", "of"}


def cached(description):
    if not CACHE.exists():
        return None
    for line in CACHE.read_text(encoding="utf-8").splitlines():
        if "\t" in line:
            key, value = line.split("\t", 1)
            if key == description:
                return value
    return None


def remember(description, emoji):
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    with CACHE.open("a", encoding="utf-8") as handle:
        handle.write(f"{description}\t{emoji}\n")


def from_model(description):
    """Anything the table doesn't know: ask, once, then remember."""
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        return None

    body = json.dumps({
        "model": os.environ.get("ORBIT_OPENAI_MODEL", "gpt-4o-mini"),
        "messages": [
            {"role": "system", "content":
             "Reply with exactly one emoji character and nothing else. "
             "If no emoji fits, reply with a single dash."},
            {"role": "user", "content": description},
        ],
        "temperature": 0,
        "max_tokens": 5,
    }).encode()

    request = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            reply = json.load(response)["choices"][0]["message"]["content"].strip()
    except Exception:  # noqa: BLE001 - a missing emoji is not worth an error
        return None

    # One character of actual emoji, or nothing.
    if not reply or reply == "-" or reply.isascii():
        return None
    return reply[:4].strip()


def resolve_exact(description):
    """The table and the cache only - no guessing at how many words were
    meant. "great work thumbs up" must not quietly match on "thumbs up"
    and swallow "great work" with it."""
    description = " ".join(description.lower().split())
    if not description:
        return None
    if description in TABLE:
        return TABLE[description]
    hit = cached(description)
    return hit or None


def resolve(description):
    description = " ".join(description.lower().split())
    if not description:
        return None
    exact = resolve_exact(description)
    if exact:
        return exact
    if cached(description) is not None:
        return None          # asked before, nothing fits
    emoji = from_model(description)
    remember(description, emoji or "")
    return emoji


def expand(text):
    """Finds "<description> emoji" and swaps in the character.

    Works backwards from the word "emoji" rather than forwards from a
    lead-in: the lead-in is optional ("thumbs up emoji"), and a pattern
    that scans forwards will happily swallow the message itself.
    """
    words = text.split()
    if not words:
        return text

    bare = [w.strip(".,!?;:\"'").lower() for w in words]
    out = []
    trailing = []
    index = 0

    while index < len(words):
        if bare[index] not in ("emoji", "emojis"):
            out.append(words[index])
            index += 1
            continue

        # Look back over at most three words for the description, and one
        # more for the article and lead-in that usually precede it.
        taken = None
        # Longest exact match first, so a two-word emoji beats the one word
        # that happens to end it. Only if nothing is known does it ask.
        for resolver in (resolve_exact, resolve):
            for size in (3, 2, 1):
                if len(out) < size:
                    continue
                candidate = [w.strip(".,!?;:\"'").lower() for w in out[-size:]]
                if any(word in LEAD_IN for word in candidate):
                    continue
                emoji = resolver(" ".join(candidate))
                if emoji:
                    taken = (size, emoji)
                    break
            if taken:
                break

        if not taken:
            out.append(words[index])
            index += 1
            continue

        size, emoji = taken
        del out[-size:]
        # Drop the lead-in words that introduced it: "with a", "and the".
        while out and out[-1].strip(".,!?;:\"'").lower() in LEAD_IN:
            out.pop()

        at_end = index == len(words) - 1
        if at_end:
            trailing.append(emoji)
        else:
            out.append(emoji)
        index += 1

    result = " ".join(out).strip(" ,")
    if trailing:
        result = (result + " " + " ".join(trailing)).strip()
    return result


if __name__ == "__main__":
    print(expand(" ".join(sys.argv[1:])))
