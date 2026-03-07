
import React, { useState, useMemo, useRef, useEffect } from 'react';
import { createId } from '../services/id';
import {
  Plus,
  TrendingDown,
  TrendingUp,
  DollarSign,
  Filter,
  ArrowDownCircle,
  ArrowUpCircle,
  Sparkles,
  Loader2,
  Trash2,
  Lock,
  Globe,
  Share2,
  Pencil,
  X,
  Check,
  Download,
  Upload,
  FileText,
  FileSpreadsheet,
  ChevronDown,
} from 'lucide-react';
import { Transaction, BudgetCategory, Visibility, User, Family } from '../types';
import { analyzeBudget, parseBankStatement, ParsedBankTransaction, ParsedBankResult } from '../services/gemini';
import { useLocale } from '../contexts/LocaleContext';
import { format, isSameMonth } from 'date-fns';
import { PieChart, Pie, Cell, ResponsiveContainer } from 'recharts';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import ModuleHint from '../components/ModuleHint';

const COLOR_PRESETS = [
  '#f59e0b', '#3b82f6', '#ec4899', '#10b981', '#8b5cf6',
  '#ef4444', '#06b6d4', '#f97316', '#14b8a6', '#6366f1',
  '#84cc16', '#e11d48', '#0ea5e9', '#a855f7', '#22c55e',
];

// ── helpers ────────────────────────────────────────────────────────────────

/** Escape a string for safe insertion into HTML (prevents XSS in PDF export). */
function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function generateId() {
  return createId();
}

/** Read a File as plain text (for CSV). */
function readFileAsText(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(file);
  });
}

/** Read a File as a base64 string (for PDF). */
function readFileAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result as string;
      // Strip the "data:application/pdf;base64," prefix
      resolve(dataUrl.split(',')[1]);
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}

/** Trigger a browser file download. */
function triggerDownload(content: string | Blob, filename: string, mime = 'text/csv') {
  const blob = content instanceof Blob ? content : new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

// ── types ──────────────────────────────────────────────────────────────────

interface EditableNewCategory {
  name: string;
  suggestedLimit: number;
  color: string;
}

interface ImportPreview {
  transactions: ParsedBankTransaction[];
  newCategories: EditableNewCategory[];
}

// ── component ──────────────────────────────────────────────────────────────

const Budget: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const { fmtCurrency, fmtCurrencyCompact, currencySymbol } = useLocale();
  const fileInputRef = useRef<HTMLInputElement>(null);

  // ── existing state ────────────────────────────────────────────────────
  const [isAiLoading, setIsAiLoading] = useState(false);
  const [aiTips, setAiTips] = useState<string[]>([]);
  const [aiError, setAiError] = useState('');
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isCategoriesOpen, setIsCategoriesOpen] = useState(false);
  const [showExportMenu, setShowExportMenu] = useState(false);

  // Add-transaction form
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [categoryId, setCategoryId] = useState(db.budgetCategories[0]?.id || '');
  const [type, setType] = useState<'EXPENSE' | 'INCOME'>('EXPENSE');
  const [txVisibility, setTxVisibility] = useState<Visibility>('FAMILY');

  // Category form
  const [catName, setCatName] = useState('');
  const [catLimit, setCatLimit] = useState('');
  const [catColor, setCatColor] = useState(COLOR_PRESETS[0]);

  // Edit-transaction form
  const [editingTx, setEditingTx] = useState<Transaction | null>(null);
  const [editTxAmount, setEditTxAmount] = useState('');
  const [editTxDescription, setEditTxDescription] = useState('');
  const [editTxCategoryId, setEditTxCategoryId] = useState('');
  const [editTxType, setEditTxType] = useState<'EXPENSE' | 'INCOME'>('EXPENSE');
  const [editTxVisibility, setEditTxVisibility] = useState<Visibility>('FAMILY');

  // Edit-category form
  const [editingCatId, setEditingCatId] = useState<string | null>(null);
  const [editCatName, setEditCatName] = useState('');
  const [editCatLimit, setEditCatLimit] = useState('');
  const [editCatColor, setEditCatColor] = useState('');

  // ── import state ─────────────────────────────────────────────────────
  const [isImportLoading, setIsImportLoading] = useState(false);
  const [importError, setImportError] = useState('');
  const [importPreview, setImportPreview] = useState<ImportPreview | null>(null);
  // one boolean per transaction
  const [importSelections, setImportSelections] = useState<boolean[]>([]);
  // editable new-category limits
  const [editableNewCats, setEditableNewCats] = useState<EditableNewCategory[]>([]);

  // ── derived data ──────────────────────────────────────────────────────
  const visibleCategories = useMemo(() => {
    return db.budgetCategories.filter(c =>
      c.familyId === family.id &&
      (c.visibility === 'FAMILY' || c.creatorId === user.id)
    );
  }, [db.budgetCategories, family.id, user.id]);

  // Reset categoryId when the selected category no longer exists (e.g. deleted)
  useEffect(() => {
    if (categoryId && !visibleCategories.some(c => c.id === categoryId)) {
      setCategoryId(visibleCategories[0]?.id || '');
    }
  }, [categoryId, visibleCategories]);

  const visibleTransactions = useMemo(() => {
    return db.transactions.filter(t =>
      t.familyId === family.id &&
      (t.visibility === 'FAMILY' || t.creatorId === user.id)
    );
  }, [db.transactions, family.id, user.id]);

  const stats = useMemo(() => {
    const now = new Date();
    // Stats compare against monthly category limits, so only count this month's transactions
    const monthTx = visibleTransactions.filter(t => isSameMonth(new Date(t.date), now));
    const totalExpenses = monthTx
      .filter(t => t.type === 'EXPENSE')
      .reduce((acc, curr) => acc + curr.amount, 0);
    const totalIncome = monthTx
      .filter(t => t.type === 'INCOME')
      .reduce((acc, curr) => acc + curr.amount, 0);
    const byCategory = visibleCategories.map(cat => {
      const spent = monthTx
        .filter(t => t.categoryId === cat.id && t.type === 'EXPENSE')
        .reduce((acc, curr) => acc + curr.amount, 0);
      return {
        name: cat.name,
        spent,
        limit: cat.limit,
        color: cat.color,
        percentage: cat.limit > 0 ? Math.min(100, (spent / cat.limit) * 100) : 0,
      };
    });
    return { totalExpenses, totalIncome, byCategory, net: totalIncome - totalExpenses };
  }, [visibleTransactions, visibleCategories]);

  // ── transaction CRUD ──────────────────────────────────────────────────
  const addTransaction = () => {
    const numAmount = parseFloat(amount);
    if (isNaN(numAmount) || numAmount <= 0 || !description || !categoryId) return;
    const newTransaction: Transaction = {
      id: generateId(),
      familyId: family.id,
      creatorId: user.id,
      categoryId,
      amount: Math.abs(numAmount),
      type,
      date: new Date().toISOString(),
      description,
      visibility: txVisibility,
    };
    save({ ...db, transactions: [newTransaction, ...db.transactions] }, 'added a transaction', 'Budget', description);
    setIsModalOpen(false);
    setAmount('');
    setDescription('');
    setTxVisibility('FAMILY');
  };

  const deleteTransaction = (id: string) => {
    save({ ...db, transactions: db.transactions.filter(t => t.id !== id) }, 'deleted a transaction', 'Budget', '');
  };

  const openEditTransaction = (tx: Transaction) => {
    setEditingTx(tx);
    setEditTxAmount(String(tx.amount));
    setEditTxDescription(tx.description);
    setEditTxCategoryId(tx.categoryId);
    setEditTxType(tx.type);
    setEditTxVisibility(tx.visibility);
  };

  const updateTransaction = () => {
    if (!editingTx) return;
    const numAmount = parseFloat(editTxAmount);
    if (isNaN(numAmount) || numAmount <= 0 || !editTxDescription || !editTxCategoryId) return;
    const newTxns = db.transactions.map(t =>
      t.id === editingTx.id
        ? { ...t, amount: Math.abs(numAmount), description: editTxDescription, categoryId: editTxCategoryId, type: editTxType, visibility: editTxVisibility }
        : t
    );
    save({ ...db, transactions: newTxns }, 'updated a transaction', 'Budget', editTxDescription);
    setEditingTx(null);
  };

  const shareTransaction = (id: string) => {
    const newTxns = db.transactions.map(t => t.id === id ? { ...t, visibility: 'FAMILY' as Visibility } : t);
    save({ ...db, transactions: newTxns }, 'shared a transaction', 'Budget', '');
  };

  // ── category CRUD ─────────────────────────────────────────────────────
  const addCategory = () => {
    const limit = parseFloat(catLimit);
    if (!catName || isNaN(limit) || limit <= 0) return;
    const newCat: BudgetCategory = {
      id: generateId(),
      familyId: family.id,
      creatorId: user.id,
      name: catName,
      limit,
      color: catColor,
      visibility: 'FAMILY',
    };
    const newDb = { ...db, budgetCategories: [...db.budgetCategories, newCat] };
    save(newDb, 'added a budget category', 'Budget', catName);
    if (!categoryId) setCategoryId(newCat.id);
    setCatName('');
    setCatLimit('');
    setCatColor(COLOR_PRESETS[0]);
  };

  const deleteCategory = (id: string) => {
    const txCount = db.transactions.filter(t => t.categoryId === id).length;
    const msg = txCount > 0
      ? `Delete this category and its ${txCount} transaction${txCount === 1 ? '' : 's'}? This cannot be undone.`
      : 'Delete this category? This cannot be undone.';
    if (!window.confirm(msg)) return;
    save({
      ...db,
      budgetCategories: db.budgetCategories.filter(c => c.id !== id),
      transactions: db.transactions.filter(t => t.categoryId !== id),
    }, 'deleted a budget category', 'Budget', '');
  };

  const startEditCategory = (cat: BudgetCategory) => {
    setEditingCatId(cat.id);
    setEditCatName(cat.name);
    setEditCatLimit(String(cat.limit));
    setEditCatColor(cat.color);
  };

  const saveEditCategory = () => {
    if (!editingCatId || !editCatName) return;
    const limit = parseFloat(editCatLimit);
    if (isNaN(limit) || limit <= 0) return;
    const newCats = db.budgetCategories.map(c =>
      c.id === editingCatId ? { ...c, name: editCatName, limit, color: editCatColor } : c
    );
    save({ ...db, budgetCategories: newCats }, 'updated a budget category', 'Budget', editCatName);
    setEditingCatId(null);
  };

  // ── AI savings coach ──────────────────────────────────────────────────
  const handleAnalyze = async () => {
    setIsAiLoading(true);
    setAiError('');
    const summaryText = stats.byCategory
      .map(c => `${c.name}: Spent ${fmtCurrencyCompact(c.spent)} of ${fmtCurrencyCompact(c.limit)}`)
      .join('. ');
    try {
      const result = await analyzeBudget(summaryText) as string[];
      setAiTips(result);
    } catch (e: any) {
      setAiError(e?.message || 'AI failed to analyze. Try again later.');
    } finally {
      setIsAiLoading(false);
    }
  };

  // ── export CSV ────────────────────────────────────────────────────────
  const exportCSV = () => {
    const catMap = Object.fromEntries(visibleCategories.map(c => [c.id, c.name]));
    const header = ['Date', 'Description', 'Category', 'Type', 'Amount'];
    const rows = visibleTransactions.map(t => [
      format(new Date(t.date), 'yyyy-MM-dd'),
      `"${t.description.replace(/"/g, '""')}"`,
      `"${(catMap[t.categoryId] ?? 'Uncategorised').replace(/"/g, '""')}"`,
      t.type,
      t.amount.toFixed(2),
    ]);
    const csv = [header, ...rows].map(r => r.join(',')).join('\n');
    triggerDownload(csv, `finance-${format(new Date(), 'yyyy-MM-dd')}.csv`, 'text/csv');
    setShowExportMenu(false);
  };

  // ── export PDF ────────────────────────────────────────────────────────
  const exportPDF = () => {
    setShowExportMenu(false);
    const dateStr = format(new Date(), 'MMMM d, yyyy');
    const catMap = Object.fromEntries(visibleCategories.map(c => [c.id, c.name]));

    const rows = visibleTransactions.map(t => `
      <tr>
        <td>${format(new Date(t.date), 'MMM d, yyyy')}</td>
        <td>${escapeHtml(t.description)}</td>
        <td>${escapeHtml(catMap[t.categoryId] ?? '—')}</td>
        <td>${t.type}</td>
        <td class="${t.type === 'INCOME' ? 'income' : 'expense'}">
          ${t.type === 'INCOME' ? '+' : '-'}${fmtCurrencyCompact(t.amount)}
        </td>
      </tr>`).join('');

    const catRows = stats.byCategory.map(c => `
      <tr>
        <td><span class="dot" style="background:${escapeHtml(c.color)}"></span>${escapeHtml(c.name)}</td>
        <td>${fmtCurrencyCompact(c.limit)}</td>
        <td>${fmtCurrencyCompact(c.spent)}</td>
        <td>${c.percentage.toFixed(0)}%</td>
      </tr>`).join('');

    const html = `<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Finance Report</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; color: #1c1c1e; padding: 32px; font-size: 13px; }
  h1 { font-size: 22px; font-weight: 700; }
  .sub { color: #6b7280; font-size: 11px; margin-top: 4px; margin-bottom: 24px; }
  .summary { display: flex; gap: 16px; margin-bottom: 28px; }
  .box { flex: 1; border-radius: 8px; padding: 12px 16px; }
  .box-g { background: #f0fdf4; color: #166534; }
  .box-r { background: #fff1f2; color: #9f1239; }
  .box-b { background: #eff6ff; color: #1e40af; }
  .box label { display: block; font-size: 11px; font-weight: 600; margin-bottom: 4px; opacity: .75; }
  .box span { font-size: 17px; font-weight: 700; }
  h2 { font-size: 14px; font-weight: 600; margin: 0 0 10px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 28px; }
  th { background: #4f46e5; color: #fff; text-align: left; padding: 7px 10px; font-size: 11px; font-weight: 600; }
  td { padding: 6px 10px; border-bottom: 1px solid #f3f4f6; }
  tr:nth-child(even) td { background: #f9fafb; }
  .income { color: #166534; font-weight: 600; }
  .expense { color: #9f1239; font-weight: 600; }
  .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 6px; }
  @media print { @page { margin: 20mm; } }
</style>
</head><body>
<h1>Family Finance Report</h1>
<p class="sub">Generated ${dateStr} · ${escapeHtml(family.name ?? 'My Family')}</p>
<div class="summary">
  <div class="box box-g"><label>Income</label><span>${fmtCurrencyCompact(stats.totalIncome)}</span></div>
  <div class="box box-r"><label>Expenses</label><span>${fmtCurrencyCompact(stats.totalExpenses)}</span></div>
  <div class="box ${stats.net >= 0 ? 'box-g' : 'box-r'}"><label>Net Savings</label><span>${fmtCurrencyCompact(stats.net)}</span></div>
</div>
<h2>Budget Categories</h2>
<table><thead><tr><th>Category</th><th>Budget Limit</th><th>Spent</th><th>% Used</th></tr></thead>
<tbody>${catRows}</tbody></table>
<h2>Transactions</h2>
<table><thead><tr><th>Date</th><th>Description</th><th>Category</th><th>Type</th><th>Amount</th></tr></thead>
<tbody>${rows}</tbody></table>
</body></html>`;

    const win = window.open('', '_blank', 'width=900,height=700');
    if (!win) return;
    win.document.write(html);
    win.document.close();
    win.focus();
    win.print();
  };

  // ── import: file selected ─────────────────────────────────────────────
  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!e.target) return;
    (e.target as HTMLInputElement).value = '';
    if (!file) return;

    const isPDF = file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf');
    const isCSV = file.type === 'text/csv' || file.name.toLowerCase().endsWith('.csv');
    if (!isPDF && !isCSV) {
      setImportError('Please upload a CSV or PDF bank statement.');
      return;
    }

    setIsImportLoading(true);
    setImportError('');
    setImportPreview(null);

    try {
      const existingNames = visibleCategories.map(c => c.name);
      let fileArg: Parameters<typeof parseBankStatement>[0];

      if (isPDF) {
        const base64 = await readFileAsBase64(file);
        fileArg = { type: 'pdf', base64 };
      } else {
        const content = await readFileAsText(file);
        fileArg = { type: 'text', content };
      }

      const result: ParsedBankResult = await parseBankStatement(fileArg, existingNames);

      const colorCount = COLOR_PRESETS.length;
      const editableCats: EditableNewCategory[] = result.newCategories.map((c, i) => ({
        name: c.name,
        suggestedLimit: c.suggestedLimit,
        color: COLOR_PRESETS[(visibleCategories.length + i) % colorCount],
      }));

      setImportPreview({ transactions: result.transactions, newCategories: editableCats });
      setImportSelections(result.transactions.map(() => true));
      setEditableNewCats(editableCats);
    } catch (err: any) {
      setImportError(err?.message ?? 'AI failed to parse the statement. Try again.');
    } finally {
      setIsImportLoading(false);
    }
  };

  // ── import: confirm ───────────────────────────────────────────────────
  const handleConfirmImport = () => {
    if (!importPreview) return;

    // 1. Create any new categories that are referenced by selected transactions
    const selectedTxns = importPreview.transactions.filter((_, i) => importSelections[i]);
    const newCatNamesNeeded = new Set(
      selectedTxns.filter(t => t.isNewCategory).map(t => t.suggestedCategory)
    );

    const createdCats: BudgetCategory[] = editableNewCats
      .filter(nc => newCatNamesNeeded.has(nc.name))
      .map(nc => ({
        id: generateId(),
        familyId: family.id,
        creatorId: user.id,
        name: nc.name,
        limit: nc.suggestedLimit,
        color: nc.color,
        visibility: 'FAMILY' as Visibility,
      }));

    // 2. Build a name→id map covering both existing and newly created categories
    const catNameToId = Object.fromEntries([
      ...visibleCategories.map(c => [c.name, c.id]),
      ...createdCats.map(c => [c.name, c.id]),
    ]);

    // Fall back to first available category if nothing matches
    const fallbackCatId = visibleCategories[0]?.id ?? createdCats[0]?.id ?? '';

    // 3. Create transactions
    const newTransactions: Transaction[] = selectedTxns.map(t => ({
      id: generateId(),
      familyId: family.id,
      creatorId: user.id,
      categoryId: catNameToId[t.suggestedCategory] ?? fallbackCatId,
      amount: Math.abs(t.amount),
      type: t.type,
      date: (() => { try { const d = new Date(t.date); return isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString(); } catch { return new Date().toISOString(); } })(),
      description: t.description,
      visibility: 'FAMILY' as Visibility,
    }));

    const newDb = {
      ...db,
      budgetCategories: [...db.budgetCategories, ...createdCats],
      transactions: [...newTransactions, ...db.transactions],
    };

    save(
      newDb,
      'imported bank statement',
      'Budget',
      `${newTransactions.length} transactions`,
    );

    setImportPreview(null);
    setImportSelections([]);
    setEditableNewCats([]);
    setImportError('');
  };

  const selectedCount = importSelections.filter(Boolean).length;

  // ── render ────────────────────────────────────────────────────────────
  return (
    <div className="space-y-8 pb-10" onClick={() => showExportMenu && setShowExportMenu(false)}>
      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        accept=".csv,.pdf,text/csv,application/pdf"
        className="hidden"
        onChange={handleFileSelect}
      />

      {/* Header */}
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Family Finance</h1>
          <p className="text-stone-500">Track spending, save together, stay balanced.</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {/* Import */}
          <button
            onClick={() => fileInputRef.current?.click()}
            disabled={isImportLoading}
            className="flex items-center gap-2 px-4 py-2.5 bg-stone-100 text-stone-700 rounded-xl font-bold text-sm hover:bg-stone-200 transition-colors disabled:opacity-50"
          >
            {isImportLoading
              ? <Loader2 size={16} className="animate-spin" />
              : <Upload size={16} />}
            Import
          </button>

          {/* Export dropdown */}
          <div className="relative">
            <button
              onClick={(e) => { e.stopPropagation(); setShowExportMenu(v => !v); }}
              disabled={visibleTransactions.length === 0}
              className="flex items-center gap-2 px-4 py-2.5 bg-stone-100 text-stone-700 rounded-xl font-bold text-sm hover:bg-stone-200 transition-colors disabled:opacity-50"
            >
              <Download size={16} />
              Export
              <ChevronDown size={14} />
            </button>
            {showExportMenu && (
              <div className="absolute right-0 top-full mt-1 w-44 bg-white rounded-2xl shadow-xl border border-stone-100 overflow-hidden z-20">
                <button
                  onClick={exportCSV}
                  className="w-full flex items-center gap-3 px-4 py-3 text-sm font-semibold text-stone-700 hover:bg-stone-50 transition-colors"
                >
                  <FileSpreadsheet size={16} className="text-emerald-600" />
                  Export as CSV
                </button>
                <button
                  onClick={exportPDF}
                  className="w-full flex items-center gap-3 px-4 py-3 text-sm font-semibold text-stone-700 hover:bg-stone-50 transition-colors"
                >
                  <FileText size={16} className="text-red-500" />
                  Export as PDF
                </button>
              </div>
            )}
          </div>

          {/* Add transaction */}
          {visibleCategories.length === 0 && (
            <p className="text-sm text-amber-600 bg-amber-50 border border-amber-200 px-3 py-2 rounded-xl font-medium">
              Add a category first
            </p>
          )}
          <button
            onClick={() => setIsModalOpen(true)}
            disabled={visibleCategories.length === 0}
            title={visibleCategories.length === 0 ? 'Create a budget category first' : undefined}
            className="bg-indigo-600 text-white px-6 py-2.5 rounded-xl font-bold flex items-center justify-center space-x-2 shadow-xl shadow-indigo-100 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Plus size={20} />
            <span>Add Transaction</span>
          </button>
        </div>
      </header>

      {/* Import error banner */}
      {importError && (
        <div className="bg-red-50 border border-red-200 rounded-2xl px-5 py-3 flex items-center justify-between">
          <p className="text-sm text-red-600">{importError}</p>
          <button onClick={() => setImportError('')}><X size={16} className="text-red-400" /></button>
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
          <div className="flex items-center space-x-3 text-stone-400 mb-2">
            <TrendingUp size={18} />
            <span className="text-sm font-bold uppercase tracking-wider">Total Income</span>
          </div>
          <p className="text-3xl font-black text-emerald-600">{fmtCurrencyCompact(stats.totalIncome)}</p>
        </div>
        <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
          <div className="flex items-center space-x-3 text-stone-400 mb-2">
            <TrendingDown size={18} />
            <span className="text-sm font-bold uppercase tracking-wider">Total Expenses</span>
          </div>
          <p className="text-3xl font-black text-red-500">{fmtCurrencyCompact(stats.totalExpenses)}</p>
        </div>
        <div className={`rounded-3xl p-6 shadow-sm border ${stats.net >= 0 ? 'bg-emerald-50 border-emerald-100' : 'bg-rose-50 border-rose-100'}`}>
          <div className="flex items-center space-x-3 text-stone-500 mb-2">
            <DollarSign size={18} />
            <span className="text-sm font-bold uppercase tracking-wider">Net Savings</span>
          </div>
          <p className={`text-3xl font-black ${stats.net >= 0 ? 'text-emerald-700' : 'text-rose-700'}`}>
            {fmtCurrencyCompact(stats.net)}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Left: categories + transactions */}
        <div className="lg:col-span-2 space-y-6">
          {/* Monthly Targets */}
          <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
            <div className="flex items-center justify-between mb-8">
              <h3 className="text-xl font-bold text-stone-800">Monthly Targets</h3>
              <button onClick={() => setIsCategoriesOpen(true)} className="text-indigo-600 font-bold text-sm hover:underline">
                Manage Categories
              </button>
            </div>
            <div className="space-y-8">
              {stats.byCategory.map((cat, i) => (
                <div key={i} className="space-y-2">
                  <div className="flex justify-between items-end">
                    <div>
                      <span className="text-lg font-bold text-stone-800">{cat.name}</span>
                      <p className="text-xs text-stone-400">Spent {fmtCurrencyCompact(cat.spent)} of {fmtCurrencyCompact(cat.limit)}</p>
                    </div>
                    <span className={`text-sm font-bold ${cat.spent > cat.limit ? 'text-red-500' : 'text-stone-700'}`}>
                      {cat.percentage.toFixed(0)}%
                    </span>
                  </div>
                  <div className="h-3 w-full bg-stone-100 rounded-full overflow-hidden">
                    <div
                      className="h-full rounded-full transition-all duration-1000"
                      style={{ width: `${cat.percentage}%`, backgroundColor: cat.spent > cat.limit ? '#ef4444' : cat.color }}
                    />
                  </div>
                </div>
              ))}
              {stats.byCategory.length === 0 && (
                <p className="text-center py-8 text-stone-400 text-sm">
                  No categories yet — click <strong>Manage Categories</strong> to add one, or <strong>Import</strong> a bank statement.
                </p>
              )}
            </div>
          </div>

          {/* Transaction History */}
          <div className="bg-white rounded-3xl border border-stone-200 shadow-sm overflow-hidden">
            <div className="p-6 border-b border-stone-100">
              <h3 className="text-xl font-bold text-stone-800">Recent Activity</h3>
            </div>
            {visibleTransactions.length > 0 ? (
              <div className="divide-y divide-stone-50">
                {visibleTransactions.slice(0, 20).map(t => {
                  const catName = visibleCategories.find(c => c.id === t.categoryId)?.name;
                  return (
                    <div key={t.id} className="group flex items-center p-4 hover:bg-stone-50 transition-colors">
                      <div className={`p-3 rounded-2xl mr-4 shrink-0 ${t.type === 'INCOME' ? 'bg-emerald-100 text-emerald-600' : 'bg-rose-100 text-rose-600'}`}>
                        {t.type === 'INCOME' ? <ArrowUpCircle size={24} /> : <ArrowDownCircle size={24} />}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <p className="font-bold text-stone-800 truncate">{t.description}</p>
                          {t.visibility === 'PRIVATE' && <Lock size={12} className="text-stone-400 shrink-0" />}
                        </div>
                        <p className="text-xs text-stone-500">
                          {format(new Date(t.date), 'MMM d, yyyy')}
                          {catName && <> · <span className="text-stone-400">{catName}</span></>}
                        </p>
                      </div>
                      <div className="text-right flex items-center space-x-2 ml-2 shrink-0">
                        <span className={`font-black text-lg ${t.type === 'INCOME' ? 'text-emerald-600' : 'text-stone-900'}`}>
                          {t.type === 'INCOME' ? '+' : '-'}{fmtCurrencyCompact(t.amount)}
                        </span>
                        <div className="flex items-center space-x-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          {t.creatorId === user.id && (
                            <button onClick={() => openEditTransaction(t)} className="p-2 text-stone-300 hover:text-indigo-500 rounded-lg transition-colors">
                              <Pencil size={16} />
                            </button>
                          )}
                          {t.visibility === 'PRIVATE' && t.creatorId === user.id && (
                            <button onClick={() => shareTransaction(t.id)} className="p-2 text-stone-300 hover:text-indigo-500 rounded-lg transition-colors">
                              <Share2 size={16} />
                            </button>
                          )}
                          <button onClick={() => deleteTransaction(t.id)} className="p-2 text-stone-300 hover:text-red-500 rounded-lg transition-colors">
                            <Trash2 size={16} />
                          </button>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <ModuleHint
                emoji="💰"
                title="Track every dollar as a family"
                tips={[
                  'Add transactions manually or import a CSV / PDF bank statement',
                  'Set monthly spending limits per category to stay on budget',
                  'The AI coach reviews your spending and suggests where to save',
                  'Switch between months to compare spending trends over time',
                ]}
              />
            )}
          </div>
        </div>

        {/* Right: AI savings coach */}
        <div className="space-y-6">
          <div className="bg-indigo-600 rounded-3xl p-6 text-white shadow-xl shadow-indigo-100 relative overflow-hidden">
            <Sparkles className="absolute -right-4 -bottom-4 w-32 h-32 opacity-20" />
            <div className="relative z-10">
              <h3 className="text-xl font-bold mb-4 flex items-center">
                <Sparkles size={20} className="mr-2" />
                AI Savings Coach
              </h3>
              <p className="text-indigo-100 text-sm mb-6 leading-relaxed">
                I've looked at your category limits and spending. Want some tips on where to cut back?
              </p>
              <button
                onClick={handleAnalyze}
                disabled={isAiLoading}
                className="w-full bg-white text-indigo-600 py-3 rounded-2xl font-bold hover:bg-indigo-50 transition-colors flex items-center justify-center space-x-2"
              >
                {isAiLoading
                  ? <Loader2 size={18} className="animate-spin" />
                  : <><span>Analyze Spending</span><TrendingDown size={18} /></>}
              </button>
            </div>
          </div>

          {aiError && (
            <div className="bg-red-50 border border-red-200 rounded-2xl px-5 py-3">
              <p className="text-sm text-red-600">{aiError}</p>
            </div>
          )}

          {aiTips.length > 0 && (
            <div className="bg-white rounded-3xl border-2 border-indigo-100 p-6 shadow-sm space-y-4">
              <h4 className="font-black text-indigo-600 uppercase tracking-widest text-xs">Recommended Actions</h4>
              {aiTips.map((tip, i) => (
                <div key={i} className="flex space-x-3 items-start">
                  <div className="w-6 h-6 rounded-full bg-indigo-50 text-indigo-600 flex items-center justify-center font-bold text-xs shrink-0">{i + 1}</div>
                  <p className="text-sm text-stone-700 leading-relaxed">{tip}</p>
                </div>
              ))}
            </div>
          )}

          {/* Pie chart when data exists */}
          {stats.byCategory.length > 0 && (
            <div className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm">
              <h4 className="font-bold text-stone-800 mb-4">Spending by Category</h4>
              <ResponsiveContainer width="100%" height={180}>
                <PieChart>
                  <Pie data={stats.byCategory} dataKey="spent" cx="50%" cy="50%" outerRadius={70} innerRadius={40}>
                    {stats.byCategory.map((cat, i) => (
                      <Cell key={i} fill={cat.color} />
                    ))}
                  </Pie>
                </PieChart>
              </ResponsiveContainer>
              <div className="mt-3 flex flex-wrap gap-2">
                {stats.byCategory.map((cat, i) => (
                  <div key={i} className="flex items-center gap-1.5 text-xs text-stone-600">
                    <div className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: cat.color }} />
                    {cat.name}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* ── Manage Categories Modal ─────────────────────────────────────── */}
      {isCategoriesOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-lg rounded-3xl shadow-2xl overflow-hidden max-h-[90vh] flex flex-col">
            <div className="p-6 border-b border-stone-100 flex items-center justify-between shrink-0">
              <h2 className="text-2xl font-bold text-stone-800">Manage Categories</h2>
              <button onClick={() => { setIsCategoriesOpen(false); setEditingCatId(null); }} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100">
                <X size={20} />
              </button>
            </div>
            <div className="flex-1 overflow-y-auto p-6 space-y-6">
              {/* Add new */}
              <div className="bg-stone-50 rounded-2xl p-5 space-y-4 border border-stone-100">
                <h3 className="text-xs font-black text-stone-400 uppercase tracking-widest">Add New Category</h3>
                <div className="grid grid-cols-2 gap-3">
                  <input type="text" placeholder="Category name" value={catName} onChange={e => setCatName(e.target.value)}
                    className="col-span-2 px-4 py-3 bg-white border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900 text-sm" />
                  <input type="number" placeholder={`Monthly limit (${currencySymbol})`} value={catLimit} onChange={e => setCatLimit(e.target.value)}
                    className="px-4 py-3 bg-white border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900 text-sm" />
                  <button onClick={addCategory} disabled={!catName || !catLimit}
                    className="bg-indigo-600 text-white rounded-xl font-bold text-sm hover:bg-indigo-700 disabled:opacity-50 flex items-center justify-center gap-2">
                    <Plus size={16} /> Add
                  </button>
                </div>
                <div className="flex flex-wrap gap-2">
                  {COLOR_PRESETS.map(c => (
                    <button key={c} onClick={() => setCatColor(c)}
                      className={`w-7 h-7 rounded-full border-2 transition-all ${catColor === c ? 'border-stone-800 scale-110' : 'border-transparent'}`}
                      style={{ backgroundColor: c }} />
                  ))}
                </div>
              </div>
              {/* Existing */}
              <div className="space-y-2">
                <h3 className="text-xs font-black text-stone-400 uppercase tracking-widest mb-3">Current Categories</h3>
                {visibleCategories.length === 0
                  ? <p className="text-center py-8 text-stone-400 text-sm">No categories yet.</p>
                  : visibleCategories.map(cat => (
                    <div key={cat.id} className="bg-white rounded-2xl border border-stone-200 p-4">
                      {editingCatId === cat.id ? (
                        <div className="space-y-3">
                          <div className="grid grid-cols-2 gap-3">
                            <input type="text" value={editCatName} onChange={e => setEditCatName(e.target.value)}
                              className="px-3 py-2 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20" />
                            <input type="number" value={editCatLimit} onChange={e => setEditCatLimit(e.target.value)}
                              className="px-3 py-2 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20" placeholder="Limit" />
                          </div>
                          <div className="flex flex-wrap gap-1.5">
                            {COLOR_PRESETS.map(c => (
                              <button key={c} onClick={() => setEditCatColor(c)}
                                className={`w-6 h-6 rounded-full border-2 transition-all ${editCatColor === c ? 'border-stone-800 scale-110' : 'border-transparent'}`}
                                style={{ backgroundColor: c }} />
                            ))}
                          </div>
                          <div className="flex gap-2">
                            <button onClick={() => setEditingCatId(null)} className="flex-1 py-2 bg-stone-100 text-stone-600 rounded-xl text-sm font-bold">Cancel</button>
                            <button onClick={saveEditCategory} className="flex-1 py-2 bg-indigo-600 text-white rounded-xl text-sm font-bold flex items-center justify-center gap-1">
                              <Check size={14} /> Save
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-3">
                            <div className="w-4 h-4 rounded-full shrink-0" style={{ backgroundColor: cat.color }} />
                            <div>
                              <p className="font-bold text-stone-800">{cat.name}</p>
                              <p className="text-xs text-stone-400">{fmtCurrencyCompact(cat.limit)} / month</p>
                            </div>
                          </div>
                          <div className="flex items-center gap-1">
                            <button onClick={() => startEditCategory(cat)} className="p-2 text-stone-300 hover:text-indigo-600 transition-colors"><Pencil size={14} /></button>
                            <button onClick={() => deleteCategory(cat.id)} className="p-2 text-stone-300 hover:text-red-500 transition-colors"><Trash2 size={14} /></button>
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Edit Transaction Modal ──────────────────────────────────────── */}
      {editingTx && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl p-8 shadow-2xl">
            <h2 className="text-2xl font-bold mb-6">Edit Transaction</h2>
            <div className="space-y-4">
              <div className="flex bg-stone-100 p-1 rounded-xl">
                <button onClick={() => setEditTxType('EXPENSE')} className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all ${editTxType === 'EXPENSE' ? 'bg-white text-rose-600 shadow-sm' : 'text-stone-500'}`}>Expense</button>
                <button onClick={() => setEditTxType('INCOME')} className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all ${editTxType === 'INCOME' ? 'bg-white text-emerald-600 shadow-sm' : 'text-stone-500'}`}>Income</button>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Amount ({currencySymbol})</label>
                <input type="number" value={editTxAmount} onChange={e => setEditTxAmount(e.target.value)} className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900" placeholder="0.00" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Description</label>
                <input type="text" value={editTxDescription} onChange={e => setEditTxDescription(e.target.value)} className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Category</label>
                <select value={editTxCategoryId} onChange={e => setEditTxCategoryId(e.target.value)} className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900">
                  {visibleCategories.map(cat => <option key={cat.id} value={cat.id}>{cat.name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Visibility</label>
                <div className="flex bg-stone-100 p-1 rounded-xl">
                  <button onClick={() => setEditTxVisibility('FAMILY')} className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${editTxVisibility === 'FAMILY' ? 'bg-white text-indigo-600 shadow-sm' : 'text-stone-500'}`}><Globe size={14} /> Shared</button>
                  <button onClick={() => setEditTxVisibility('PRIVATE')} className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${editTxVisibility === 'PRIVATE' ? 'bg-white text-stone-800 shadow-sm' : 'text-stone-500'}`}><Lock size={14} /> Private</button>
                </div>
              </div>
              <div className="pt-4 flex gap-3">
                <button onClick={() => setEditingTx(null)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold">Cancel</button>
                <button onClick={updateTransaction} className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold shadow-lg shadow-indigo-100">Save</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Add Transaction Modal ───────────────────────────────────────── */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl p-8 shadow-2xl">
            <h2 className="text-2xl font-bold mb-6">New Transaction</h2>
            <div className="space-y-4">
              <div className="flex bg-stone-100 p-1 rounded-xl">
                <button onClick={() => setType('EXPENSE')} className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all ${type === 'EXPENSE' ? 'bg-white text-rose-600 shadow-sm' : 'text-stone-500'}`}>Expense</button>
                <button onClick={() => setType('INCOME')} className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all ${type === 'INCOME' ? 'bg-white text-emerald-600 shadow-sm' : 'text-stone-500'}`}>Income</button>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Amount ({currencySymbol})</label>
                <input type="number" value={amount} onChange={e => setAmount(e.target.value)} className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900" placeholder="0.00" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Description</label>
                <input type="text" value={description} onChange={e => setDescription(e.target.value)} className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900" placeholder="e.g., Weekly Groceries" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Category</label>
                <select value={categoryId} onChange={e => setCategoryId(e.target.value)} className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900">
                  {visibleCategories.map(cat => <option key={cat.id} value={cat.id}>{cat.name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Visibility</label>
                <div className="flex bg-stone-100 p-1 rounded-xl">
                  <button onClick={() => setTxVisibility('FAMILY')} className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${txVisibility === 'FAMILY' ? 'bg-white text-indigo-600 shadow-sm' : 'text-stone-500'}`}><Globe size={14} /> Shared</button>
                  <button onClick={() => setTxVisibility('PRIVATE')} className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${txVisibility === 'PRIVATE' ? 'bg-white text-stone-800 shadow-sm' : 'text-stone-500'}`}><Lock size={14} /> Private</button>
                </div>
              </div>
              <div className="pt-4 flex gap-3">
                <button onClick={() => setIsModalOpen(false)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold">Cancel</button>
                <button onClick={addTransaction} className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold shadow-lg shadow-indigo-100">Save</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── AI Import Preview Modal ─────────────────────────────────────── */}
      {importPreview && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-2xl rounded-3xl shadow-2xl overflow-hidden max-h-[92vh] flex flex-col">
            {/* Header */}
            <div className="p-6 border-b border-stone-100 shrink-0">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h2 className="text-xl font-bold text-stone-900 flex items-center gap-2">
                    <Sparkles size={20} className="text-indigo-600" />
                    AI Bank Statement Import
                  </h2>
                  <p className="text-sm text-stone-500 mt-1">
                    {importPreview.transactions.length} transactions found
                    {editableNewCats.length > 0 && ` · ${editableNewCats.length} new ${editableNewCats.length === 1 ? 'category' : 'categories'} suggested`}
                  </p>
                </div>
                <button onClick={() => { setImportPreview(null); setImportError(''); }} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100 shrink-0">
                  <X size={20} />
                </button>
              </div>
            </div>

            <div className="flex-1 overflow-y-auto p-6 space-y-6">
              {/* New categories */}
              {editableNewCats.length > 0 && (
                <div>
                  <h3 className="text-xs font-black text-stone-400 uppercase tracking-widest mb-3">
                    New Categories to Create
                  </h3>
                  <div className="space-y-2">
                    {editableNewCats.map((nc, i) => (
                      <div key={i} className="flex items-center gap-3 bg-indigo-50 border border-indigo-100 rounded-2xl p-3">
                        <div className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: nc.color }} />
                        <span className="font-bold text-stone-800 flex-1 text-sm">{nc.name}</span>
                        <div className="flex items-center gap-1">
                          <span className="text-xs text-stone-500">{currencySymbol} limit/mo</span>
                          <input
                            type="number"
                            value={nc.suggestedLimit}
                            onChange={e => {
                              const v = parseFloat(e.target.value) || 0;
                              setEditableNewCats(prev => prev.map((c, j) => j === i ? { ...c, suggestedLimit: v } : c));
                            }}
                            className="w-24 px-2 py-1 border border-indigo-200 rounded-lg text-sm font-bold text-stone-800 text-right focus:outline-none focus:ring-2 focus:ring-indigo-300 bg-white"
                          />
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Transactions list */}
              <div>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-xs font-black text-stone-400 uppercase tracking-widest">
                    Transactions
                  </h3>
                  <div className="flex gap-3">
                    <button
                      onClick={() => setImportSelections(importPreview.transactions.map(() => true))}
                      className="text-xs font-bold text-indigo-600 hover:underline"
                    >
                      Select all
                    </button>
                    <button
                      onClick={() => setImportSelections(importPreview.transactions.map(() => false))}
                      className="text-xs font-bold text-stone-400 hover:underline"
                    >
                      Deselect all
                    </button>
                  </div>
                </div>
                <div className="space-y-1.5">
                  {importPreview.transactions.map((t, i) => (
                    <label
                      key={i}
                      className={`flex items-center gap-3 p-3 rounded-2xl border cursor-pointer transition-colors ${importSelections[i] ? 'bg-stone-50 border-stone-200' : 'bg-white border-stone-100 opacity-50'}`}
                    >
                      <input
                        type="checkbox"
                        checked={importSelections[i] ?? true}
                        onChange={e => setImportSelections(prev => prev.map((v, j) => j === i ? e.target.checked : v))}
                        className="rounded accent-indigo-600 w-4 h-4 shrink-0"
                      />
                      <div className={`p-1.5 rounded-xl shrink-0 ${t.type === 'INCOME' ? 'bg-emerald-100 text-emerald-600' : 'bg-rose-100 text-rose-600'}`}>
                        {t.type === 'INCOME' ? <ArrowUpCircle size={14} /> : <ArrowDownCircle size={14} />}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-semibold text-stone-800 truncate">{t.description}</p>
                        <div className="flex items-center gap-2 mt-0.5">
                          <span className="text-xs text-stone-400">{t.date}</span>
                          <span className={`text-xs px-1.5 py-0.5 rounded-full font-bold ${t.isNewCategory ? 'bg-indigo-100 text-indigo-700' : 'bg-stone-100 text-stone-600'}`}>
                            {t.suggestedCategory}
                            {t.isNewCategory && ' ✦'}
                          </span>
                        </div>
                      </div>
                      <span className={`text-sm font-black shrink-0 ${t.type === 'INCOME' ? 'text-emerald-600' : 'text-stone-800'}`}>
                        {t.type === 'INCOME' ? '+' : '-'}{fmtCurrencyCompact(Math.abs(t.amount))}
                      </span>
                    </label>
                  ))}
                </div>
              </div>
            </div>

            {/* Footer */}
            <div className="p-6 border-t border-stone-100 shrink-0 flex gap-3">
              <button
                onClick={() => { setImportPreview(null); setImportError(''); }}
                className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold hover:bg-stone-200 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleConfirmImport}
                disabled={selectedCount === 0}
                className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold shadow-lg shadow-indigo-100 hover:bg-indigo-700 transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
              >
                <Upload size={16} />
                Import {selectedCount} transaction{selectedCount !== 1 ? 's' : ''}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Import loading overlay ──────────────────────────────────────── */}
      {isImportLoading && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-stone-900/50 backdrop-blur-sm">
          <div className="bg-white rounded-3xl p-8 shadow-2xl flex flex-col items-center gap-4 max-w-xs w-full mx-4">
            <div className="w-14 h-14 bg-indigo-100 rounded-2xl flex items-center justify-center">
              <Sparkles size={28} className="text-indigo-600 animate-pulse" />
            </div>
            <div className="text-center">
              <p className="font-bold text-stone-900">Analysing your statement</p>
              <p className="text-sm text-stone-500 mt-1">AI is reading and categorising your transactions…</p>
            </div>
            <Loader2 size={24} className="text-indigo-600 animate-spin" />
          </div>
        </div>
      )}
    </div>
  );
};

export default Budget;
