export type Category = {
  id: string;
  label: string;
  supported: boolean;
  showInNav: boolean;
  reason?: string;
};

export const allCategories: Category[] = [
  { id: "workflows", label: "Workflows", supported: true, showInNav: true },
  { id: "tools", label: "Tools", supported: true, showInNav: true },
  { id: "skills", label: "Skills", supported: true, showInNav: true },
  { id: "voice", label: "Voice", supported: true, showInNav: true },
  { id: "rag", label: "RAG", supported: true, showInNav: true },
  { id: "settings", label: "Settings", supported: true, showInNav: true },
  { id: "agents", label: "Agents", supported: false, showInNav: false, reason: "Not supported in CogniCore framework" },
  { id: "mcps", label: "MCP Servers", supported: false, showInNav: false, reason: "Not supported in CogniCore framework" },
  { id: "processors", label: "Processors", supported: false, showInNav: false, reason: "Not supported in CogniCore framework" },
  { id: "scorers", label: "Scorers", supported: false, showInNav: false, reason: "Not supported in CogniCore framework" },
  { id: "datasets", label: "Datasets", supported: false, showInNav: false, reason: "Not supported in CogniCore framework" }
];

export const navCategories = allCategories.filter(c => c.showInNav);

export function getCategory(id: string): Category | undefined {
  return allCategories.find(c => c.id === id);
}
