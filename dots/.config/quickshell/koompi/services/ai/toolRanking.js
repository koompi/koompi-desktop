.pragma library

// How relevant a tool is to one turn: keyword overlap, no model call and no
// embedding, so the ranking can be read off the entry itself. A hit on the tool's
// own name is worth five, a hint three, a word of its description one.
//
// Hints are the words a person says when they need the tool, and the model never
// sees them. Without them a short turn matched nothing ("How much does the E13
// cost?", "Move my bar to the bottom"), every such turn got the same three tools by
// priority, and web and setter tools were never offered (tests/bench/ai).

// Words carried by nearly every description, so matching on them ranks nothing.
const stopWords = {
    "the": 1, "this": 1, "that": 1, "with": 1, "from": 1, "into": 1, "your": 1, "you": 1,
    "and": 1, "for": 1, "not": 1, "use": 1, "used": 1, "using": 1, "user": 1, "its": 1,
    "one": 1, "only": 1, "any": 1, "all": 1, "can": 1, "call": 1, "get": 1, "set": 1,
    "it": 1, "is": 1, "are": 1, "was": 1, "has": 1, "have": 1, "what": 1, "when": 1,
    "how": 1, "why": 1, "who": 1, "does": 1, "did": 1, "will": 1, "would": 1, "should": 1,
    "please": 1, "want": 1, "need": 1, "tell": 1, "show": 1, "give": 1, "make": 1,
    "instead": 1, "before": 1, "after": 1, "other": 1, "than": 1, "them": 1, "they": 1,
    "here": 1, "there": 1, "about": 1, "over": 1, "just": 1, "also": 1, "like": 1
};

function wordsOf(text, keepStopWords) {
    const found = `${text ?? ""}`.toLowerCase().match(/[a-z0-9]{3,}/g) ?? [];
    const out = {};
    for (const word of found) if (keepStopWords || !stopWords[word]) out[word] = 1;
    return out;
}

// Hints match every word of the turn: "call me Sokha" has nothing else to go on.
function relevanceScore(entry, text) {
    const said = wordsOf(text, false);
    const saidAll = wordsOf(text, true);
    let score = 0;
    for (const word in wordsOf(entry.name.replace(/_/g, " "), false)) if (said[word]) score += 5;
    for (const word in wordsOf(entry.hints, true)) if (saidAll[word]) score += 3;
    for (const word in wordsOf(entry.description, false)) if (said[word]) score += 1;
    return score;
}
