
import React, { useState } from 'react';
import { History, Sparkles, MessageSquare, Clock, ArrowRight, Trash2 } from 'lucide-react';
import { User, Family } from '../types';
import { format } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';

const AiHistory: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);

  const clearHistory = () => {
    if (confirm("Clear all AI history?")) {
      const newDb = { ...db, aiHistory: [] };
      save(newDb, 'cleared AI history', 'AI History', '');
    }
  };

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">AI Intelligence Lab</h1>
          <p className="text-stone-500">Review past insights and generated content.</p>
        </div>
        <button 
          onClick={clearHistory}
          className="text-stone-400 hover:text-red-500 font-bold text-sm flex items-center"
        >
          <Trash2 size={16} className="mr-2" />
          Clear Log
        </button>
      </header>

      {db.aiHistory.length > 0 ? (
        <div className="space-y-6">
          {db.aiHistory.map(item => (
            <div key={item.id} className="bg-white rounded-3xl border border-stone-200 p-6 shadow-sm hover:shadow-md transition-shadow">
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center space-x-3">
                  <div className="p-2 bg-indigo-50 text-indigo-600 rounded-xl">
                    <Sparkles size={18} />
                  </div>
                  <h4 className="font-black text-stone-800 uppercase tracking-widest text-xs">{item.module} Assistance</h4>
                </div>
                <div className="flex items-center text-stone-400 text-xs font-bold">
                  <Clock size={12} className="mr-1" />
                  {format(new Date(item.createdAt), 'MMM d, h:mm a')}
                </div>
              </div>
              <div className="space-y-4">
                <div className="bg-stone-50 rounded-2xl p-4 border border-stone-100">
                  <p className="text-xs font-black text-stone-400 uppercase tracking-widest mb-2">Prompt</p>
                  <p className="text-stone-700 font-medium italic">"{item.prompt}"</p>
                </div>
                <div className="bg-white rounded-2xl p-4 border border-indigo-50">
                  <p className="text-xs font-black text-indigo-400 uppercase tracking-widest mb-2">Result</p>
                  <p className="text-stone-800 leading-relaxed whitespace-pre-wrap">{item.response}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="flex flex-col items-center justify-center py-32 bg-white border border-dashed border-stone-200 rounded-[2.5rem] text-stone-400">
          <History size={48} className="mb-4 opacity-20" />
          <p className="font-medium">No history yet. Start using the "AI" buttons in any module!</p>
        </div>
      )}
    </div>
  );
};

export default AiHistory;
