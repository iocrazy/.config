import fs from "fs";
import { spawn } from "child_process";

const HOME = process.env.HOME || "/tmp";
const NOTIFY_BIN = "/opt/homebrew/bin/python3";
const NOTIFY_SCRIPT = `${HOME}/.config/agent-tracker/notify.py`;
const MAX_SUMMARY_CHARS = 600;
const TRACKER_BIN = `${HOME}/.config/agent-tracker/bin/tracker-client`;
const DEBUG_LOG = `${HOME}/.config/opencode/tracker-debug.log`;

// Helper to run tracker-client with proper argument handling
const runTracker = (args) => {
	return new Promise((resolve) => {
		const proc = spawn(TRACKER_BIN, args, { stdio: "pipe" });
		let stderr = "";
		proc.stderr?.on("data", (data) => { stderr += data.toString(); });
		proc.on("close", (code) => {
			resolve({ exitCode: code, stderr });
		});
		proc.on("error", (err) => {
			resolve({ exitCode: -1, stderr: err.message });
		});
	});
};

const debugLog = (msg) => {
	const now = new Date();
	const utc8 = new Date(now.getTime() + 8 * 60 * 60 * 1000);
	const timestamp = utc8.toISOString().replace("Z", "+08:00");
	fs.appendFileSync(DEBUG_LOG, `[${timestamp}] ${msg}\n`);
};

// OpenCode plugin for agent-tracker integration
// Tracks task start/finish when Claude is busy/idle
export default async ({ client, directory, $ }) => {
	debugLog(`Plugin loaded. HOME=${HOME}, TRACKER_BIN=${TRACKER_BIN}`);

	// Only run within tmux (TMUX_PANE must be set)
	const TMUX_PANE = process.env.TMUX_PANE;
	debugLog(`TMUX_PANE=${TMUX_PANE || "NOT SET"}`);
	if (!TMUX_PANE) {
		debugLog("No TMUX_PANE, returning empty handler");
		return {};
	}

	// Resolve tmux context once at startup to avoid race conditions
	let tmuxContext = null;
	const resolveTmuxContext = async () => {
		if (tmuxContext) return tmuxContext;
		try {
			const result = await $`tmux display-message -p -t ${TMUX_PANE} "#{session_id}:::#{window_id}:::#{pane_id}"`.quiet();
			const parts = result.stdout.trim().split(":::");
			if (parts.length === 3) {
				tmuxContext = {
					sessionId: parts[0],
					windowId: parts[1],
					paneId: parts[2],
				};
			}
		} catch {
			// Fallback: use TMUX_PANE directly
			tmuxContext = { paneId: TMUX_PANE };
		}
		return tmuxContext;
	};
	await resolveTmuxContext();

	let taskActive = false;
	let currentSessionID = null;
	let lastUserMessage = "";

	const trackerReady = () => {
		try {
			fs.accessSync(TRACKER_BIN, fs.constants.X_OK);
			debugLog(`trackerReady: true`);
			return true;
		} catch {
			debugLog(`trackerReady: false`);
			return false;
		}
	};

	const buildTrackerArgs = () => {
		const args = [];
		if (tmuxContext?.sessionId) args.push("-session-id", tmuxContext.sessionId);
		if (tmuxContext?.windowId) args.push("-window-id", tmuxContext.windowId);
		if (tmuxContext?.paneId) args.push("-pane", tmuxContext.paneId);
		return args;
	};

	// On init: finish any stale task for this pane
	const finishStaleTask = async () => {
		if (!(trackerReady())) return;
		// Note: flags must come BEFORE the subcommand name for Go flag parsing
		const cmdArgs = [
			"command",
			...buildTrackerArgs(),
			"-summary", "stale",
			"finish_task"  // subcommand must be last
		];
		await runTracker(cmdArgs);
	};
	finishStaleTask();

	const summarizeText = (parts = []) => {
		const text = parts
			.filter((p) => p?.type === "text" && !p.ignored)
			.map((p) => p.text || "")
			.join("\n")
			.trim();
		return text.slice(0, MAX_SUMMARY_CHARS);
	};

	const collectUserInputs = (messages) => {
		return messages
			.filter((m) => m?.info?.role === "user")
			.slice(-3)
			.map((m) => summarizeText(m.parts))
			.filter((text) => text);
	};

	const startTask = async (summary, sessionID) => {
		debugLog(`startTask called: summary="${summary}", sessionID=${sessionID}`);
		if (!summary) { debugLog("startTask: no summary, returning"); return; }
		if (!(trackerReady())) { debugLog("startTask: tracker not ready"); return; }
		taskActive = true;
		currentSessionID = sessionID;
		// Note: flags must come BEFORE the subcommand name for Go flag parsing
		const cmdArgs = [
			"command",
			...buildTrackerArgs(),
			"-summary", summary,
			"start_task"  // subcommand must be last
		];
		debugLog(`startTask: running with cmdArgs=${JSON.stringify(cmdArgs)}`);
		const result = await runTracker(cmdArgs);
		debugLog(`startTask: result exitCode=${result?.exitCode}, stderr=${result?.stderr}`);
	};

	const finishTask = async (summary) => {
		debugLog(`finishTask called: summary="${summary}", taskActive=${taskActive}`);
		if (!taskActive) { debugLog("finishTask: task not active, returning"); return; }
		if (!(trackerReady())) { debugLog("finishTask: tracker not ready"); return; }
		taskActive = false;
		currentSessionID = null;
		// Note: flags must come BEFORE the subcommand name for Go flag parsing
		const cmdArgs = [
			"command",
			...buildTrackerArgs(),
			"-summary", summary || "done",
			"finish_task"  // subcommand must be last
		];
		debugLog(`finishTask: running with cmdArgs=${JSON.stringify(cmdArgs)}`);
		const result = await runTracker(cmdArgs);
		debugLog(`finishTask: result exitCode=${result?.exitCode}, stderr=${result?.stderr}`);
	};

	const notify = async (sessionID) => {
		try {
			const messages =
				(await client.session.messages({
					path: { id: sessionID },
					query: { directory },
				})) || [];

			const assistant = [...messages]
				.reverse()
				.find((m) => m?.info?.role === "assistant");
			if (!assistant) return;

			const assistantText = summarizeText(assistant.parts);
			if (!assistantText) return;

			const payload = {
				type: "agent-turn-complete",
				"last-assistant-message": assistantText,
				input_messages: collectUserInputs(messages),
			};

			const serialized = JSON.stringify(payload);
			try {
				await $`${NOTIFY_BIN} ${NOTIFY_SCRIPT} ${serialized}`;
			} catch {
				// ignore notification failures
			}
		} catch {
			// Ignore notification failures
		}
	};

	const getLastMessageText = async (sessionID, role, retries = 3) => {
		for (let attempt = 0; attempt < retries; attempt++) {
			try {
				const messages =
					(await client.session.messages({
						path: { id: sessionID },
						query: { directory },
					})) || [];
				const msg = [...messages]
					.reverse()
					.find((m) => m?.info?.role === role);
				if (msg) {
					const text = summarizeText(msg.parts);
					if (text) return text;
				}
			} catch {
				// ignore fetch errors
			}
			if (attempt < retries - 1) {
				await new Promise((r) => setTimeout(r, 100));
			}
		}
		return "";
	};

	// Track message IDs to their roles
	const messageRoles = new Map();

	return {
		event: async ({ event }) => {
			// Track message roles from message.updated events
			if (event?.type === "message.updated") {
				const info = event?.properties?.info;
				if (info?.id && info?.role) {
					messageRoles.set(info.id, info.role);
				}
			}

			// Capture user message text from message.part.updated
			if (event?.type === "message.part.updated") {
				const part = event?.properties?.part;
				if (part?.type === "text" && part?.text && part?.messageID) {
					const role = messageRoles.get(part.messageID);
					// Capture if it's a user message, or if we're not yet in a task (user input comes first)
					if (role === "user" || (!role && !taskActive)) {
						const text = part.text?.trim();
						if (text && text.length > 0) {
							lastUserMessage = text.slice(0, MAX_SUMMARY_CHARS);
						}
					}
				}
			}

			if (event?.type !== "session.status") return;

			const sessionID = event?.properties?.sessionID;
			const status = event?.properties?.status;
			debugLog(`session.status event: status.type=${status?.type}, taskActive=${taskActive}`);
			if (!sessionID || !status) return;

			if (status.type === "busy" && !taskActive) {
				debugLog("Status changed to BUSY, starting task...");
				// Use captured message first, then fall back to API
				let text = lastUserMessage;
				if (!text) {
					text = await getLastMessageText(sessionID, "user");
				}
				await startTask(text || "working...", sessionID);
				lastUserMessage = "";
			} else if (status.type === "idle" && taskActive) {
				debugLog("Status changed to IDLE, finishing task...");
				if (currentSessionID && sessionID !== currentSessionID) return;
				const text = await getLastMessageText(sessionID, "assistant");
				await finishTask(text || "done");
				await notify(sessionID);
			}
		},
	};
};
