import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import tasks from "./src/index.js";

const taskTools = new Set(["TaskCreate", "TaskList", "TaskGet", "TaskUpdate"]);

export default function (pi: ExtensionAPI) {
  tasks({
    ...pi,
    registerTool(tool) {
      if (taskTools.has(tool.name)) pi.registerTool(tool);
    },
    events: {
      on: () => () => {},
      emit: () => {},
    },
  });
}
