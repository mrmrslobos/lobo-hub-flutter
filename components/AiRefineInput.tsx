import React, { useState, useRef, useEffect } from 'react';
import { Send, Loader2, Sparkles, RotateCcw } from 'lucide-react';

interface RefinementEntry {
  request: string;
  status: 'pending' | 'done' | 'error';
  error?: string;
}

interface AiRefineInputProps {
  /** Called with the user's text; must return a promise that resolves when the plan is updated */
  onRefine: (request: string) => Promise<void>;
  /** Optional label shown above the input */
  label?: string;
  /** Placeholder text for the input */
  placeholder?: string;
  className?: string;
}

const AiRefineInput: React.FC<AiRefineInputProps> = ({
  onRefine,
  label = 'Refine with AI',
  placeholder = 'Ask AI to change anything… e.g. "Move rest days to Saturday and Sunday"',
  className = '',
}) => {
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [history, setHistory] = useState<RefinementEntry[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

  // Auto-focus after submission so user can type a follow-up immediately
  useEffect(() => {
    if (!loading) inputRef.current?.focus();
  }, [loading]);

  const submit = async () => {
    const trimmed = input.trim();
    if (!trimmed || loading) return;

    const entry: RefinementEntry = { request: trimmed, status: 'pending' };
    setHistory(prev => [...prev, entry]);
    setInput('');
    setLoading(true);

    try {
      await onRefine(trimmed);
      setHistory(prev =>
        prev.map((h, i) => i === prev.length - 1 ? { ...h, status: 'done' } : h),
      );
    } catch (err: any) {
      setHistory(prev =>
        prev.map((h, i) =>
          i === prev.length - 1
            ? { ...h, status: 'error', error: err?.message || 'Something went wrong. Try again.' }
            : h,
        ),
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className={`bg-gradient-to-r from-indigo-50 to-purple-50 border border-indigo-100 rounded-3xl p-5 space-y-3 ${className}`}>
      {/* Header */}
      <div className="flex items-center gap-2">
        <Sparkles size={15} className="text-indigo-500 shrink-0" />
        <p className="text-sm font-bold text-indigo-700">{label}</p>
      </div>

      {/* History thread */}
      {history.length > 0 && (
        <div className="space-y-2">
          {history.map((entry, i) => (
            <div key={i} className="space-y-1">
              {/* User bubble */}
              <div className="flex justify-end">
                <span className="bg-indigo-600 text-white text-xs font-semibold px-3 py-1.5 rounded-2xl rounded-tr-sm max-w-[85%]">
                  {entry.request}
                </span>
              </div>
              {/* AI response bubble */}
              <div className="flex justify-start">
                {entry.status === 'pending' ? (
                  <span className="bg-white border border-indigo-100 text-indigo-400 text-xs px-3 py-1.5 rounded-2xl rounded-tl-sm flex items-center gap-1.5">
                    <Loader2 size={11} className="animate-spin" /> Updating plan…
                  </span>
                ) : entry.status === 'done' ? (
                  <span className="bg-white border border-emerald-200 text-emerald-700 text-xs font-semibold px-3 py-1.5 rounded-2xl rounded-tl-sm flex items-center gap-1.5">
                    ✓ Plan updated
                  </span>
                ) : (
                  <span className="bg-white border border-red-200 text-red-600 text-xs px-3 py-1.5 rounded-2xl rounded-tl-sm flex items-center gap-1.5">
                    <RotateCcw size={11} /> {entry.error}
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Input row */}
      <div className="flex gap-2">
        <input
          ref={inputRef}
          type="text"
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') submit(); }}
          placeholder={placeholder}
          disabled={loading}
          className="flex-1 px-4 py-2.5 bg-white border border-indigo-200 rounded-2xl text-sm placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-indigo-400/30 disabled:opacity-60"
        />
        <button
          onClick={submit}
          disabled={!input.trim() || loading}
          className="px-4 py-2.5 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 disabled:opacity-40 transition-colors flex items-center gap-1.5 shrink-0"
        >
          {loading
            ? <Loader2 size={16} className="animate-spin" />
            : <Send size={16} />}
        </button>
      </div>
      <p className="text-[10px] text-indigo-400 leading-relaxed">
        Ask to change rest days, swap exercises, adjust duration, change cuisine, dietary restrictions, and more.
      </p>
    </div>
  );
};

export default AiRefineInput;
