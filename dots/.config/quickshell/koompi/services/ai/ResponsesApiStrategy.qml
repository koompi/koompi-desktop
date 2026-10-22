import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import QtQuick

// OpenAI's Responses API, the route a ChatGPT plan requires; it refuses forbiddenFields.
ApiStrategy {
    property bool isReasoning: false
    property var pendingCalls: ({}) // output_index -> { call_id, name, arguments }
    property bool completed: false
    property bool failed: false
    readonly property string tokenVar: "KOOMPI_CHATGPT_TOKEN"
    readonly property var forbiddenFields: ["temperature", "max_output_tokens", "previous_response_id", "metadata", "user"]

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function stripThinking(text) {
        return `${text ?? ""}`.replace(/\n*<think>[\s\S]*?<\/think>\n*/g, "");
    }

    // no item ids: with store false the server has nothing to look them up in
    function inputItems(message) {
        if (message.toolCallId && message.toolCallId.length > 0)
            return [{ "type": "function_call_output", "call_id": message.toolCallId, "output": message.functionResponse ?? "" }];
        if (message.role === "tool") {
            const legacy = (message.functionResponse ?? "").length > 0 ? message.functionResponse : message.rawContent;
            return [{ "type": "message", "role": "user", "content": [{ "type": "input_text", "text": legacy ?? "" }] }];
        }
        const assistant = message.role === "assistant";
        const text = assistant ? stripThinking(message.rawContent) : `${message.rawContent ?? ""}`;
        const items = [];
        if (text.length > 0 || !assistant) {
            items.push({ "type": "message", "role": assistant ? "assistant" : "user",
                "content": [{ "type": assistant ? "output_text" : "input_text", "text": text }] });
        }
        for (const call of (message.toolCalls ?? []))
            items.push({ "type": "function_call", "call_id": call.id, "name": call.name, "arguments": call.arguments ?? "{}" });
        return items;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        const data = Object.assign({}, model.extraParams ?? {}, {
            "model": model.model,
            "instructions": systemPrompt,
            "input": [].concat(...messages.map(message => inputItems(message))),
            "stream": true,
            "store": false,
        });
        if (tools && tools.length > 0) data.tools = tools;
        for (const field of forbiddenFields) delete data[field];
        return data;
    }

    // the plan token reaches curl through a builtin printf, so it is in no argv and no file
    function buildAuthorizationHeader(apiKeyEnvVarName: string, model: AiModel): string {
        if (model?.auth === "chatgpt") return `-H @<(printf 'Authorization: Bearer %s\\n' "\$${tokenVar}")`;
        if (!model?.requires_key) return "";
        return `\$\{${apiKeyEnvVarName}:+-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"\}`;
    }

    function finalizeScriptContent(scriptContent: string): string {
        if (scriptContent.indexOf(`"\$${tokenVar}"`) < 0) return scriptContent;
        const helper = CF.StringUtils.shellSingleQuoteEscape(CF.FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/chatgpt_auth.py`));
        const setup = `${tokenVar}="$('${helper}' token)" || { printf 'data: {"type":"error","code":"chatgpt_auth_%s"}\\n' "$?"; exit 1; }\n`;
        const cut = scriptContent.indexOf("\n") + 1;
        return scriptContent.slice(0, cut) + setup + scriptContent.slice(cut);
    }

    function parseResponseLine(line, message) {
        const text = line.trim();
        if (text.length === 0 || text.startsWith(":") || text.startsWith("event:")) return {};
        const payload = text.startsWith("data:") ? text.slice(5).trim() : text;
        if (payload === "[DONE]") return {};
        let event;
        try {
            event = JSON.parse(payload);
        } catch (e) {
            message.rawContent += line;
            message.content += line;
            return {};
        }
        return handleEvent(event, message);
    }

    function handleEvent(event, message) {
        switch (event.type) {
        case "response.output_text.delta":
            appendText(message, event.delta ?? "", false);
            return {};
        case "response.reasoning_summary_text.delta":
            appendText(message, event.delta ?? "", true);
            return {};
        case "response.output_item.added":
        case "response.output_item.done":
            noteItem(event.output_index ?? 0, event.item);
            return {};
        case "response.function_call_arguments.delta":
            callAt(event.output_index ?? 0).arguments += event.delta ?? "";
            return {};
        case "response.function_call_arguments.done":
            if (typeof event.arguments === "string") callAt(event.output_index ?? 0).arguments = event.arguments;
            return {};
        case "response.completed":
            return complete(event.response, message);
        case "response.failed":
            return fail(message, event.response?.error?.code, event.response?.error?.message);
        case "response.incomplete":
            return fail(message, event.response?.incomplete_details?.reason ?? "incomplete", "");
        case "error":
            return fail(message, event.code ?? event.error?.code, event.message ?? event.error?.message);
        }
        if (!event.type && event.error) return fail(message, event.error.code ?? event.error.type, event.error.message);
        return {};
    }

    function callAt(index) {
        if (!pendingCalls[index]) pendingCalls[index] = { "call_id": "", "name": "", "arguments": "" };
        return pendingCalls[index];
    }

    function noteItem(index, item) {
        if (item?.type !== "function_call") return;
        const call = callAt(index);
        if (item.call_id) call.call_id = item.call_id;
        if (item.name) call.name = item.name;
        if ((item.arguments ?? "").length > 0) call.arguments = item.arguments;
    }

    function appendText(message, delta, reasoning) {
        if (delta.length === 0) return;
        if (reasoning !== isReasoning) {
            const mark = reasoning ? "\n\n<think>\n\n" : "\n\n</think>\n\n";
            isReasoning = reasoning;
            message.content += mark;
            message.rawContent += mark;
        }
        message.content += delta;
        message.rawContent += delta;
    }

    function closeThinking(message) {
        if (!isReasoning) return;
        isReasoning = false;
        message.content += "\n\n</think>\n\n";
        message.rawContent += "\n\n</think>\n\n";
    }

    // the shape OpenAiApiStrategy hands back, so Requester and ToolRunner need no change
    function takeCalls(message) {
        const indices = Object.keys(pendingCalls).sort((a, b) => Number(a) - Number(b));
        const calls = [];
        const wire = [];
        for (let k = 0; k < indices.length; k++) {
            const call = pendingCalls[indices[k]];
            if (call.name.length === 0) continue;
            let args = {};
            try {
                if (call.arguments.length > 0) args = JSON.parse(call.arguments);
            } catch (e) {
                console.log("[AI] Responses: Could not parse tool call arguments: ", e);
            }
            const id = call.call_id.length > 0 ? call.call_id : `call_${k}`;
            calls.push({ "name": call.name, "args": args, "id": id });
            wire.push({ "id": id, "name": call.name, "arguments": call.arguments || "{}" });
        }
        pendingCalls = ({});
        if (calls.length === 0) return null;
        message.functionName = calls[0].name;
        message.toolCalls = wire;
        return calls;
    }

    function complete(response, message) {
        completed = true;
        closeThinking(message);
        const result = { "finished": true };
        const usage = response?.usage;
        if (usage) {
            result.tokenUsage = { "input": usage.input_tokens ?? -1, "output": usage.output_tokens ?? -1, "total": usage.total_tokens ?? -1 };
        }
        const calls = takeCalls(message);
        if (calls) {
            result.functionCall = calls[0];
            result.functionCalls = calls;
        }
        return result;
    }

    function fail(message, code, detail) {
        failed = true;
        pendingCalls = ({});
        closeThinking(message);
        const shown = `${code ?? ""}`.length > 0 ? `${code}` : "unknown_error";
        const text = `\n\n**${Translation.tr("Error")}** \`${shown}\`${detail ? `: ${detail}` : ""}`;
        message.rawContent += text;
        message.content += text;
        return { "finished": true };
    }

    // success is response.completed and nothing else
    function onRequestFinished(message) {
        if (!completed && !failed) fail(message, "incomplete_stream", "");
        return {};
    }

    function reset() {
        isReasoning = false;
        pendingCalls = ({});
        completed = false;
        failed = false;
    }
}
