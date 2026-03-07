export type Category = {
  id: string;
  label: string;
};

export const allCategories: Category[] = [
  { id: "agents", label: "Agents" },
  { id: "workflows", label: "Workflows" },
  { id: "tools", label: "Tools" },
  { id: "skills", label: "Skills" },
  { id: "voice", label: "Voice" },
  { id: "rag", label: "RAG" },
  { id: "settings", label: "Settings" },
];

export const navCategories = allCategories;
