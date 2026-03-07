import React, { useState, useEffect, useCallback } from 'react';
import { createId } from '../services/id';
import { X, Bell, CheckSquare, Calendar, ListTodo, Utensils, BookOpen, Activity, Wallet, ClipboardList, Vote, MessageSquare } from 'lucide-react';

export interface ToastMessage {
  id: string;
  userName: string;
  action: string;
  module: string;
  detail: string;
  timestamp: number;
}

const MODULE_CONFIG: Record<string, { icon: React.ElementType; bg: string; text: string }> = {
  Tasks:      { icon: CheckSquare, bg: 'bg-emerald-50 border-emerald-200', text: 'text-emerald-700' },
  Calendar:   { icon: Calendar,    bg: 'bg-indigo-50 border-indigo-200',   text: 'text-indigo-700' },
  Lists:      { icon: ListTodo,    bg: 'bg-violet-50 border-violet-200',   text: 'text-violet-700' },
  Meals:      { icon: Utensils,    bg: 'bg-amber-50 border-amber-200',     text: 'text-amber-700' },
  Devotional: { icon: BookOpen,    bg: 'bg-sky-50 border-sky-200',         text: 'text-sky-700' },
  Fitness:    { icon: Activity,    bg: 'bg-green-50 border-green-200',     text: 'text-green-700' },
  Budget:     { icon: Wallet,      bg: 'bg-pink-50 border-pink-200',       text: 'text-pink-700' },
  Chores:     { icon: ClipboardList, bg: 'bg-teal-50 border-teal-200',    text: 'text-teal-700' },
  Polls:      { icon: Vote,          bg: 'bg-fuchsia-50 border-fuchsia-200', text: 'text-fuchsia-700' },
  Chat:       { icon: MessageSquare, bg: 'bg-indigo-50 border-indigo-200',   text: 'text-indigo-700' },
};

const DEFAULT_CONFIG = { icon: Bell, bg: 'bg-stone-50 border-stone-200', text: 'text-stone-700' };

const TOAST_DURATION = 5000;

// Global toast queue - components can push to this from anywhere
let globalPush: ((toast: Omit<ToastMessage, 'id'>) => void) | null = null;

export function pushToast(toast: Omit<ToastMessage, 'id'>) {
  if (globalPush) globalPush(toast);
}

const NotificationToast: React.FC = () => {
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  const addToast = useCallback((toast: Omit<ToastMessage, 'id'>) => {
    const newToast: ToastMessage = { ...toast, id: createId() };
    setToasts(prev => [...prev.slice(-4), newToast]); // Keep max 5
  }, []);

  const removeToast = useCallback((id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  // Register global push function
  useEffect(() => {
    globalPush = addToast;
    return () => { globalPush = null; };
  }, [addToast]);

  // Auto-dismiss
  useEffect(() => {
    if (toasts.length === 0) return;
    const oldest = toasts[0];
    const age = Date.now() - oldest.timestamp;
    const remaining = Math.max(0, TOAST_DURATION - age);
    const timer = setTimeout(() => removeToast(oldest.id), remaining);
    return () => clearTimeout(timer);
  }, [toasts, removeToast]);

  if (toasts.length === 0) return null;

  return (
    <div className="fixed top-4 right-4 z-[9999] flex flex-col gap-3 max-w-sm w-full pointer-events-none">
      {toasts.map(toast => {
        const config = MODULE_CONFIG[toast.module] || DEFAULT_CONFIG;
        const IconComp = config.icon;
        return (
          <div
            key={toast.id}
            className={`pointer-events-auto ${config.bg} border rounded-2xl p-4 shadow-xl shadow-stone-200/50 animate-in slide-in-from-right fade-in duration-300`}
          >
            <div className="flex items-start gap-3">
              <div className={`p-1.5 rounded-lg ${config.text} bg-white/80 shrink-0`}>
                <IconComp size={16} />
              </div>
              <div className="flex-1 min-w-0">
                <p className={`text-xs font-bold ${config.text}`}>{toast.userName}</p>
                <p className="text-sm text-stone-700 leading-snug mt-0.5">
                  {toast.action}{toast.detail ? `: ${toast.detail}` : ''}
                </p>
                <p className="text-[10px] text-stone-400 mt-1">{toast.module}</p>
              </div>
              <button
                onClick={() => removeToast(toast.id)}
                className="p-1 text-stone-300 hover:text-stone-500 shrink-0"
              >
                <X size={14} />
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
};

export default NotificationToast;
