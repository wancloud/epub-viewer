from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class QuotePair:
    """A pair of quote markers that denotes dialogue, plus the color to render it in."""

    open: str
    close: str
    color: str
    enabled: bool = True

    def to_dict(self) -> dict:
        return {"open": self.open, "close": self.close, "color": self.color, "enabled": self.enabled}

    @staticmethod
    def from_dict(data: dict) -> "QuotePair":
        return QuotePair(
            open=data["open"],
            close=data["close"],
            color=data["color"],
            enabled=data.get("enabled", True),
        )


@dataclass
class DialogueConfig:
    pairs: list[QuotePair] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {"pairs": [p.to_dict() for p in self.pairs]}

    @staticmethod
    def from_dict(data: dict) -> "DialogueConfig":
        return DialogueConfig(pairs=[QuotePair.from_dict(p) for p in data.get("pairs", [])])

    def enabled_pairs(self) -> list[QuotePair]:
        return [p for p in self.pairs if p.enabled and p.open and p.close]


def find_dialogue_spans(text: str, config: DialogueConfig) -> list[tuple[int, int, str]]:
    """Scan `text` for dialogue delimited by any enabled quote pair in `config`.

    Returns a sorted, non-overlapping list of (start, end, color) spans in text-offset
    coordinates. `end` is exclusive and the span includes the marker characters themselves.

    Markers where open == close (e.g. plain " or ') are treated as toggles: the first
    occurrence opens a span, the next occurrence of that same character closes it.
    Markers with distinct open/close characters (e.g. 「」, «») are matched with a stack,
    so different pair types may nest; an unmatched trailing open is simply left unstyled.
    """
    pairs = config.enabled_pairs()
    if not pairs or not text:
        return []

    same_char_pairs = {p.open: p for p in pairs if p.open == p.close}
    open_to_pair = {p.open: p for p in pairs if p.open != p.close}
    close_to_pair = {p.close: p for p in pairs if p.open != p.close}

    spans: list[tuple[int, int, str]] = []
    stack: list[tuple[QuotePair, int]] = []
    open_same: dict[str, int] = {}

    for i, ch in enumerate(text):
        if ch in same_char_pairs:
            if ch in open_same:
                start = open_same.pop(ch)
                spans.append((start, i + 1, same_char_pairs[ch].color))
            else:
                open_same[ch] = i
            continue

        if ch in open_to_pair:
            stack.append((open_to_pair[ch], i))
            continue

        if ch in close_to_pair:
            pair = close_to_pair[ch]
            for depth in range(len(stack) - 1, -1, -1):
                if stack[depth][0] is pair:
                    start = stack[depth][1]
                    del stack[depth:]
                    spans.append((start, i + 1, pair.color))
                    break

    spans.sort(key=lambda s: s[0])
    return _remove_overlaps(spans)


def _remove_overlaps(spans: list[tuple[int, int, str]]) -> list[tuple[int, int, str]]:
    result: list[tuple[int, int, str]] = []
    last_end = -1
    for start, end, color in spans:
        if start >= last_end:
            result.append((start, end, color))
            last_end = end
    return result
