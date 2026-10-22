.pragma library

// A failed request in plain words. OpenAiApiStrategy and ResponsesApiStrategy hand
// what they saw (the HTTP status, the error code, any reset time) to explain(), and
// the chat shows render() of the answer instead of a raw code. No QML type is
// reachable from here on purpose: tests/test_ai_providers.sh runs it under bun.
// `Translation` is passed in, so its literals are found by the translation tool.

// curl prints this after the body (--write-out), so the strategies learn the HTTP
// status even when the error body is pretty-printed JSON they could not parse.
var trailerType = "koompi.http";

function withStatusTrailer(script) {
    const mark = "exec curl ";
    const at = script.indexOf(mark);
    if (at < 0) return script;
    // a string: curl writes 000 when it never got an answer, which JSON refuses as a number
    const trailer = `--write-out '\\ndata: {"type":"${trailerType}","status":"%{http_code}","retry_after":"%header{retry-after}"}\\n' `;
    return script.slice(0, at + mark.length) + trailer + script.slice(at + mark.length);
}

// {code, type, message, resetsAt, resetsInSeconds} from a JSON error body, or null
function fromBody(text) {
    let body;
    try {
        body = JSON.parse(`${text ?? ""}`.trim());
    } catch (e) {
        return null;
    }
    if (!body || typeof body !== "object") return null;
    const e = body.error ?? body.response?.error;
    if (typeof e === "string") return { "code": e, "message": `${body.error_description ?? body.message ?? ""}` };
    if (!e || typeof e !== "object") {
        if (typeof body.detail === "string") return { "code": "", "message": body.detail };
        return null;
    }
    return fromError(e);
}

// the same fields from an error object a stream event carries
function fromError(e) {
    if (!e || typeof e !== "object") return {};
    return {
        "code": `${e.code ?? e.type ?? ""}`,
        "type": `${e.type ?? ""}`,
        "message": `${e.message ?? ""}`,
        "resetsAt": e.resets_at ?? null,
        "resetsInSeconds": e.resets_in_seconds ?? null,
    };
}

// seconds until the limit resets, or -1 when the response did not say
function resetSeconds(err, nowMs) {
    const now = nowMs ?? Date.now();
    const inSeconds = Number(err.resetsInSeconds);
    if (err.resetsInSeconds != null && Number.isFinite(inSeconds) && inSeconds > 0) return Math.round(inSeconds);
    if (err.resetsAt != null && `${err.resetsAt}`.length > 0) {
        const n = Number(err.resetsAt);
        const at = Number.isFinite(n) ? (n > 1e12 ? n : n * 1000) : Date.parse(err.resetsAt);
        if (Number.isFinite(at) && at > now) return Math.round((at - now) / 1000);
    }
    const retry = `${err.retryAfter ?? ""}`.trim();
    if (/^\d+$/.test(retry) && Number(retry) > 0) return Number(retry);
    if (retry.length > 0) {
        const at = Date.parse(retry);
        if (Number.isFinite(at) && at > now) return Math.round((at - now) / 1000);
    }
    return -1;
}

function fill(text, value) {
    return `${text}`.split("%1").join(`${value}`);
}

function waitText(seconds, Translation) {
    if (seconds < 90) return Translation.tr("about a minute");
    if (seconds < 90 * 60) return fill(Translation.tr("about %1 minutes"), Math.round(seconds / 60));
    if (seconds < 36 * 3600) return fill(Translation.tr("about %1 hours"), Math.round(seconds / 3600));
    return fill(Translation.tr("about %1 days"), Math.round(seconds / 86400));
}

function has(code, words) {
    return words.some(w => code.indexOf(w) >= 0);
}

// The chatgpt_auth.py exits the request script reports as chatgpt_auth_<exit>.
function signInProblem(code, Translation) {
    if (code === "chatgpt_auth_3") return [Translation.tr("Plan not included."),
        Translation.tr("This ChatGPT sign-in does not include plan usage. Sign out and continue with ChatGPT again in Settings > AI."), "sign_in"];
    if (code === "chatgpt_auth_5") return [Translation.tr("Can't reach OpenAI."),
        Translation.tr("Check your internet connection and try again."), "retry"];
    return [Translation.tr("Sign in again."),
        Translation.tr("Your ChatGPT sign-in has ended. Open Settings > AI and choose Continue with ChatGPT."), "sign_in"];
}

function limitProblem(err, code, Translation, nowMs) {
    const seconds = resetSeconds(err, nowMs);
    const plan = err.auth === "chatgpt" || has(code, ["usage_limit", "usage_not_included"]);
    if (plan) {
        return [Translation.tr("Usage limit reached."), seconds > 0
            ? fill(Translation.tr("You have used your ChatGPT plan's limit for now. It resets in %1."), waitText(seconds, Translation))
            : Translation.tr("You have used your ChatGPT plan's limit for now. Try again later, or pick another model."), "wait"];
    }
    if (has(code, ["insufficient_quota", "quota"]))
        return [Translation.tr("Out of credit."), Translation.tr("This API account has no credit left. Add credit with the provider, then try again."), ""];
    return [Translation.tr("Too many requests."), seconds > 0
        ? fill(Translation.tr("The provider is limiting requests. Try again in %1."), waitText(seconds, Translation))
        : Translation.tr("The provider is limiting requests. Wait a moment, then try again."), "wait"];
}

// [title, text, action], first match wins
function classify(err, Translation, nowMs) {
    const code = `${err.code ?? ""}`.toLowerCase();
    const status = Number(err.status ?? 0) || 0;
    if (code.indexOf("chatgpt_auth_") === 0) return signInProblem(code, Translation);
    if (has(code, ["usage_limit", "usage_not_included", "quota"]) || status === 429 || code === "rate_limit_exceeded")
        return limitProblem(err, code, Translation, nowMs);
    if (status === 401 || has(code, ["invalid_api_key", "invalid_token", "token_expired", "unauthorized", "authentication"])) {
        if (err.auth === "chatgpt") return signInProblem("chatgpt_auth_4", Translation);
        return [Translation.tr("API key refused."), Translation.tr("Replace the key in Settings > AI, or type /key in the chat."), "key"];
    }
    if (code === "context_length_exceeded" || status === 413)
        return [Translation.tr("Conversation too long."), Translation.tr("Start a new chat, or clear some of this one, then ask again."), ""];
    if (status === 403 || has(code, ["unsupported_country", "permission", "forbidden"]))
        return [Translation.tr("Not allowed."), Translation.tr("This account can't use this model. Pick another model."), ""];
    if (status === 404 || code === "model_not_found")
        return [Translation.tr("Model not found."), Translation.tr("The provider does not offer this model. Pick another model or check its name."), ""];
    if (status >= 500 || has(code, ["server_error", "overloaded", "unavailable", "timeout"]))
        return [Translation.tr("The service had a problem."), Translation.tr("It is on the provider's side. Try again in a moment."), "retry"];
    if (code === "incomplete_stream")
        return [Translation.tr("The reply was cut off."), Translation.tr("The connection ended before the reply finished. Try again."), "retry"];
    if (code === "max_output_tokens")
        return [Translation.tr("The reply hit its length limit."), Translation.tr("Ask for a shorter answer."), ""];
    if (code === "content_filter")
        return [Translation.tr("The provider stopped this reply."), Translation.tr("Try asking another way."), ""];
    if (status === -1 || code === "unreachable")
        return [Translation.tr("Can't reach the model."), Translation.tr("Check the connection or the endpoint, then try again."), "retry"];
    return [Translation.tr("The request failed."), `${err.message ?? ""}`.trim().length > 0 ? `${err.message}`.trim() : Translation.tr("Try again."), "retry"];
}

// err: {status, code, type, message, resetsAt, resetsInSeconds, retryAfter, auth}
// auth is "chatgpt" for a plan sign-in, "key" for an API key, "" for none.
// -> {title, text, action: "sign_in" | "key" | "wait" | "retry" | "", code}
function explain(err, Translation, nowMs) {
    const e = err ?? {};
    const [title, text, action] = classify(e, Translation, nowMs);
    const code = `${e.code ?? ""}`.length > 0 ? `${e.code}` : (Number(e.status) > 0 ? `HTTP ${e.status}` : "");
    return { "title": title, "text": text, "action": action, "code": code };
}

// what the chat shows: the plain words first, the code last for anyone reporting it
function render(explained) {
    const code = explained.code.length > 0 ? ` \`${explained.code}\`` : "";
    return `\n\n**${explained.title}** ${explained.text}${code}`;
}
