import QtQuick
import qs.modules.common
import qs.modules.common.functions as CF

/**
 * Strategy for Anthropic's Messages API (Claude).
 *
 * Authentication is done WITHOUT an API key: it uses the OAuth access token of a
 * logged-in Claude (Pro/Max) subscription, resolved at request time by
 * `scripts/ai/claude-token.sh` (which reads the token from the `claude`/`ant`
 * CLI or their credential files and auto-refreshes it). The token is sent as a
 * Bearer token together with the `anthropic-beta: oauth-2025-04-20` header.
 *
 * Supports: streamed text, summarized extended thinking, tool/function calls and
 * inline file attachments (images + PDF, base64-encoded in the request).
 */
ApiStrategy {
    id: strategy

    // Streaming state
    property bool isReasoning: false
    property var currentTool: null
    property var pendingFunctionCall: null
    property int inputTokens: -1

    // Placeholders spliced with the base64 file data at script-finalize time
    readonly property string fileDataSubst: "{{ claude_file_data }}"
    readonly property string fileMimeSubst: "{{ claude_file_mime }}"

    readonly property string tokenScript: CF.FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/claude-token.sh`)

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let msgs = messages.map(message => {
            return {
                "role": (message.role === "assistant") ? "assistant" : "user",
                "content": message.rawContent ?? ""
            };
        });

        // Inline the attached file into the most recent message
        if (filePath && filePath.length > 0 && msgs.length > 0) {
            const isPdf = filePath.toLowerCase().endsWith(".pdf");
            const fileBlock = isPdf ? {
                "type": "document",
                "source": { "type": "base64", "media_type": "application/pdf", "data": fileDataSubst }
            } : {
                "type": "image",
                "source": { "type": "base64", "media_type": fileMimeSubst, "data": fileDataSubst }
            };
            const last = msgs[msgs.length - 1];
            let parts = [];
            if (last.content && last.content.length > 0) parts.push({ "type": "text", "text": last.content });
            parts.push(fileBlock);
            last.content = parts;
        }

        let baseData = {
            "model": model.model,
            "max_tokens": 8192,
            "messages": msgs,
            "stream": true,
        };
        // Subscription OAuth tokens require the Claude Code identity as the first
        // system block; the user's own prompt follows it. (Harmless for a
        // developer `ant` token.)
        let systemBlocks = [{ "type": "text", "text": "You are Claude Code, Anthropic's official CLI for Claude." }];
        if (systemPrompt && systemPrompt.length > 0) systemBlocks.push({ "type": "text", "text": systemPrompt });
        baseData.system = systemBlocks;
        if (tools && Array.isArray(tools) && tools.length > 0) baseData.tools = tools;

        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        // No API key: resolve a subscription OAuth token at request time.
        return `-H "anthropic-version: 2023-06-01"`
            + ` -H "anthropic-beta: oauth-2025-04-20"`
            + ` -H "Authorization: Bearer $(bash '${strategy.tokenScript}')"`;
    }

    function startThink(message) {
        if (!isReasoning) {
            isReasoning = true;
            const block = "\n\n<think>\n\n";
            message.content += block;
            message.rawContent += block;
        }
    }

    function endThink(message) {
        if (isReasoning) {
            isReasoning = false;
            const block = "\n\n</think>\n\n";
            message.content += block;
            message.rawContent += block;
        }
    }

    function parseResponseLine(line, message) {
        let clean = line;
        if (clean.startsWith("event:")) return {};
        if (clean.startsWith("data:")) clean = clean.slice(5);
        clean = clean.trim();
        if (clean.length === 0) return {};

        let dataJson;
        try {
            dataJson = JSON.parse(clean);
        } catch (e) {
            return {}; // pings / partial lines
        }

        const type = dataJson.type;

        if (type === "message_start") {
            inputTokens = dataJson.message?.usage?.input_tokens ?? -1;
            return {};
        }

        if (type === "content_block_start") {
            const cb = dataJson.content_block;
            if (cb?.type === "thinking") {
                startThink(message);
            } else if (cb?.type === "tool_use") {
                currentTool = { "name": cb.name, "id": cb.id, "buf": "" };
            }
            return {};
        }

        if (type === "content_block_delta") {
            const delta = dataJson.delta;
            if (delta?.type === "text_delta") {
                endThink(message);
                message.content += delta.text;
                message.rawContent += delta.text;
            } else if (delta?.type === "thinking_delta") {
                startThink(message);
                message.content += delta.thinking;
                message.rawContent += delta.thinking;
            } else if (delta?.type === "input_json_delta") {
                if (currentTool) currentTool.buf += (delta.partial_json ?? "");
            }
            return {};
        }

        if (type === "content_block_stop") {
            endThink(message);
            if (currentTool) {
                let args = {};
                try {
                    args = currentTool.buf.length > 0 ? JSON.parse(currentTool.buf) : {};
                } catch (e) {
                    args = {};
                }
                pendingFunctionCall = { "name": currentTool.name, "args": args };
                const marker = `\n\n[[ Function: ${currentTool.name}(${JSON.stringify(args, null, 2)}) ]]\n`;
                message.content += marker;
                message.rawContent += marker;
                message.functionName = currentTool.name;
                message.functionCall = currentTool.name;
                currentTool = null;
            }
            return {};
        }

        if (type === "message_delta") {
            const out = dataJson.usage?.output_tokens ?? -1;
            return {
                tokenUsage: {
                    input: inputTokens,
                    output: out,
                    total: (inputTokens >= 0 ? inputTokens : 0) + (out >= 0 ? out : 0)
                }
            };
        }

        if (type === "message_stop") {
            let result = { finished: true };
            if (pendingFunctionCall) {
                result.functionCall = pendingFunctionCall;
                pendingFunctionCall = null;
            }
            return result;
        }

        if (type === "error") {
            const errorMsg = `**Error**: ${dataJson.error?.message ?? JSON.stringify(dataJson.error)}`;
            message.content += errorMsg;
            message.rawContent += errorMsg;
            return { finished: true };
        }

        return {};
    }

    function onRequestFinished(message) {
        endThink(message);
        return {};
    }

    function reset() {
        isReasoning = false;
        currentTool = null;
        pendingFunctionCall = null;
        inputTokens = -1;
    }

    function buildScriptFileSetup(filePath) {
        const trimmed = CF.FileUtils.trimFileProtocol(filePath);
        let content = "";
        content += `CLAUDE_FILE_PATH='${CF.StringUtils.shellSingleQuoteEscape(trimmed)}'\n`;
        content += `CLAUDE_FILE_MIME=$(file -b --mime-type "$CLAUDE_FILE_PATH")\n`;
        content += `CLAUDE_FILE_DATA=$(base64 -w 0 "$CLAUDE_FILE_PATH")\n`;
        return content;
    }

    function finalizeScriptContent(scriptContent: string): string {
        return scriptContent
            .split(fileMimeSubst).join(`'"$CLAUDE_FILE_MIME"'`)
            .split(fileDataSubst).join(`'"$CLAUDE_FILE_DATA"'`);
    }
}
