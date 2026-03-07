
import React, { useState, useMemo, useEffect, useRef } from 'react';
import {
  Plus,
  Trash2,
  Pencil,
  Check,
  X,
  CheckSquare,
  Square,
  Sparkles,
  Loader2,
  ChevronRight,
  ShoppingCart,
  Package,
  Hammer,
  MoreHorizontal,
  Lock,
  Globe,
  Share2,
  Tags,
  ChevronDown,
  ChevronUp,
  History,
} from 'lucide-react';
import { List, ListItem, Visibility, User, Family } from '../types';
import { textToChecklist, categorizeListItems } from '../services/gemini';
import { useRealtimeDB } from '../hooks/useRealtimeDB';

const Lists: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const [isAiLoading, setIsAiLoading] = useState(false);
  const [aiText, setAiText] = useState('');
  const [newItemText, setNewItemText] = useState('');
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [newListTitle, setNewListTitle] = useState('');
  const [newListVisibility, setNewListVisibility] = useState<Visibility>('FAMILY');
  const [isCategorizing, setIsCategorizing] = useState(false);
  const [groupedView, setGroupedView] = useState(false);
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({});

  // Inline item edit state
  const [editingItemId, setEditingItemId] = useState<string | null>(null);
  const [editItemText, setEditItemText] = useState('');
  const [editItemQuantity, setEditItemQuantity] = useState('');

  // Item history autocomplete
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [suggestionIdx, setSuggestionIdx] = useState(-1);
  const addInputRef = useRef<HTMLInputElement>(null);

  // Frequency-sorted list of every item text ever used across this family's lists
  const itemHistory = useMemo(() => {
    const seen = new Map<string, string>(); // lowercase key → original casing
    const freq = new Map<string, number>();
    for (const list of db.lists) {
      if (list.familyId !== family.id) continue;
      for (const item of list.items) {
        const key = item.text.trim().toLowerCase();
        if (!key) continue;
        if (!seen.has(key)) seen.set(key, item.text.trim());
        freq.set(key, (freq.get(key) || 0) + 1);
      }
    }
    return [...seen.entries()]
      .sort((a, b) => (freq.get(b[0]) || 0) - (freq.get(a[0]) || 0))
      .map(([, text]) => text);
  }, [db.lists, family.id]);

  const filteredSuggestions = useMemo(() => {
    if (!showSuggestions || !newItemText.trim()) return [];
    const q = newItemText.trim().toLowerCase();
    return itemHistory
      .filter(t => t.toLowerCase().includes(q) && t.toLowerCase() !== q)
      .slice(0, 6);
  }, [itemHistory, newItemText, showSuggestions]);

  const visibleLists = useMemo(() => {
    return db.lists.filter(l =>
      l.familyId === family.id &&
      (l.visibility === 'FAMILY' || l.creatorId === user.id)
    );
  }, [db.lists, family.id, user.id]);

  const [activeListId, setActiveListId] = useState<string | null>(visibleLists[0]?.id || null);

  // Select first list when none is active, or reset when current selection no longer exists
  useEffect(() => {
    if (!activeListId && visibleLists.length > 0) {
      setActiveListId(visibleLists[0].id);
    } else if (activeListId && !visibleLists.some(l => l.id === activeListId)) {
      setActiveListId(visibleLists[0]?.id || null);
    }
  }, [activeListId, visibleLists]);

  const activeList = visibleLists.find(l => l.id === activeListId);

  const toggleItem = (listId: string, itemId: string) => {
    const newLists = db.lists.map(list => {
      if (list.id === listId) {
        return {
          ...list,
          items: list.items.map(item => item.id === itemId ? { ...item, checked: !item.checked } : item)
        };
      }
      return list;
    });
    const newDb = { ...db, lists: newLists };
    save(newDb, 'checked off an item', 'Lists', activeList?.title || '');
  };

  const startEditItem = (item: ListItem) => {
    setEditingItemId(item.id);
    setEditItemText(item.text);
    setEditItemQuantity(item.quantity || '');
  };

  const saveEditItem = () => {
    if (!editingItemId || !editItemText.trim() || !activeListId) return;
    const newLists = db.lists.map(list => {
      if (list.id !== activeListId) return list;
      return {
        ...list,
        items: list.items.map(item =>
          item.id === editingItemId
            ? { ...item, text: editItemText.trim(), quantity: editItemQuantity.trim() || undefined }
            : item
        ),
      };
    });
    save({ ...db, lists: newLists }, 'edited an item', 'Lists', editItemText.trim());
    setEditingItemId(null);
  };

  const deleteItem = (itemId: string) => {
    if (!activeListId) return;
    const newLists = db.lists.map(list => {
      if (list.id !== activeListId) return list;
      return { ...list, items: list.items.filter(item => item.id !== itemId) };
    });
    save({ ...db, lists: newLists }, 'deleted an item', 'Lists', '');
  };

  const addItem = () => {
    const trimmed = newItemText.trim();
    if (!trimmed || !activeListId) return;
    const newItem: ListItem = {
      id: Math.random().toString(36).substr(2, 9),
      text: trimmed,
      checked: false
    };
    const newLists = db.lists.map(list => {
      if (list.id === activeListId) return { ...list, items: [...list.items, newItem] };
      return list;
    });
    const newDb = { ...db, lists: newLists };
    save(newDb, 'added an item', 'Lists', newItemText);
    setNewItemText('');
  };

  const deleteList = (id: string) => {
    if (!window.confirm('Delete this list and all its items? This cannot be undone.')) return;
    const newLists = db.lists.filter(l => l.id !== id);
    const newDb = { ...db, lists: newLists };
    save(newDb, 'deleted a list', 'Lists', '');
    if (activeListId === id) {
      const remaining = newLists.filter(l => l.familyId === family.id && (l.visibility === 'FAMILY' || l.creatorId === user.id));
      setActiveListId(remaining[0]?.id || null);
    }
  };

  const shareList = (id: string) => {
    const newLists = db.lists.map(l => l.id === id ? { ...l, visibility: 'FAMILY' as Visibility } : l);
    const newDb = { ...db, lists: newLists };
    save(newDb, 'shared a list', 'Lists', '');
  };

  const createList = () => {
    if (!newListTitle.trim()) return;
    const newList: List = {
      id: Math.random().toString(36).substr(2, 9),
      familyId: family.id,
      creatorId: user.id,
      title: newListTitle.trim(),
      category: 'OTHER',
      items: [],
      visibility: newListVisibility
    };
    const newDb = { ...db, lists: [...db.lists, newList] };
    save(newDb, 'created a new list', 'Lists', newListTitle);
    setActiveListId(newList.id);
    setNewListTitle('');
    setNewListVisibility('FAMILY');
    setIsCreateOpen(false);
  };

  const handleAiChecklist = async () => {
    if (!aiText) return;
    setIsAiLoading(true);
    try {
      const items = await textToChecklist(aiText);
      const newList: List = {
        id: Math.random().toString(36).substr(2, 9),
        familyId: family.id,
        creatorId: user.id,
        title: `AI: ${aiText.slice(0, 20)}...`,
        category: 'OTHER',
        items: items.map((item: any) => ({
          id: Math.random().toString(36).substr(2, 9),
          text: item.text,
          quantity: item.quantity,
          checked: false
        })),
        visibility: 'FAMILY'
      };
      const newDb = { ...db, lists: [...db.lists, newList] };
      save(newDb, 'created an AI checklist', 'Lists', '');
      setActiveListId(newList.id);
      setAiText('');
    } catch (e) {
      alert("AI failed to convert text.");
    } finally {
      setIsAiLoading(false);
    }
  };

  const handleCategorize = async () => {
    if (!activeList || activeList.items.length === 0) return;
    setIsCategorizing(true);
    try {
      const itemsToSend = activeList.items.map(i => ({ id: i.id, text: i.text }));
      const result = await categorizeListItems(itemsToSend, activeList.category);
      const categoryMap = new Map(result.map(r => [r.id, r.category]));
      const newLists = db.lists.map(list => {
        if (list.id !== activeList.id) return list;
        return {
          ...list,
          items: list.items.map(item => ({
            ...item,
            aiCategory: categoryMap.get(item.id) || 'Uncategorized',
          })),
        };
      });
      const newDb = { ...db, lists: newLists };
      save(newDb, 'categorized items', 'Lists', activeList?.title || '');
      setGroupedView(true);
      setCollapsedGroups({});
    } catch (e) {
      alert('AI categorization failed. Please try again.');
    } finally {
      setIsCategorizing(false);
    }
  };

  const toggleGroup = (group: string) => {
    setCollapsedGroups(prev => ({ ...prev, [group]: !prev[group] }));
  };

  const getGroupedItems = (items: ListItem[]) => {
    const groups: Record<string, ListItem[]> = {};
    for (const item of items) {
      const cat = item.aiCategory || 'Uncategorized';
      if (!groups[cat]) groups[cat] = [];
      groups[cat].push(item);
    }
    return Object.entries(groups).sort(([a], [b]) => a.localeCompare(b));
  };

  const hasCategories = activeList?.items.some(i => i.aiCategory);

  const getCategoryIcon = (cat: string) => {
    switch (cat) {
      case 'GROCERY': return <ShoppingCart size={18} />;
      case 'PACKING': return <Package size={18} />;
      case 'HARDWARE': return <Hammer size={18} />;
      default: return <CheckSquare size={18} />;
    }
  };

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Family Lists</h1>
          <p className="text-stone-500">Shared checklists for shopping, projects, and travel.</p>
        </div>
        <button
          onClick={() => setIsCreateOpen(true)}
          className="bg-indigo-600 text-white px-6 py-3 rounded-2xl font-bold flex items-center justify-center space-x-2 shadow-xl shadow-indigo-100"
        >
          <Plus size={20} />
          <span>New List</span>
        </button>
      </header>

      {/* AI Wizard */}
      <div className="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-3xl p-6 text-white relative overflow-hidden shadow-xl shadow-emerald-100">
        <Sparkles className="absolute right-[-10px] bottom-[-10px] w-40 h-40 opacity-10" />
        <div className="relative z-10 max-w-2xl">
          <h3 className="text-xl font-bold mb-2 flex items-center">
            <Sparkles size={20} className="mr-2" />
            AI Checklist Wizard
          </h3>
          <p className="text-emerald-50 text-sm mb-4">Paste a paragraph or list of items, and I'll structure it into a checklist for you.</p>
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="text"
              placeholder="e.g., We need 3 packs of batteries, a screwdriver, blue tape..."
              value={aiText}
              onChange={(e) => setAiText(e.target.value)}
              className="flex-1 px-4 py-3 bg-white/10 backdrop-blur-md border border-white/20 rounded-2xl text-white placeholder:text-white/60 focus:outline-none focus:ring-2 focus:ring-white/50"
            />
            <button
              onClick={handleAiChecklist}
              disabled={isAiLoading || !aiText}
              className="bg-white text-emerald-600 px-6 py-3 rounded-2xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center min-w-[140px]"
            >
              {isAiLoading ? <Loader2 size={18} className="animate-spin" /> : 'Convert to List'}
            </button>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        {/* Sidebar: All Lists */}
        <div className="space-y-4">
          <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest px-2">Your Lists</h3>
          <div className="space-y-1">
            {visibleLists.map(list => (
              <button
                key={list.id}
                onClick={() => setActiveListId(list.id)}
                className={`w-full flex items-center justify-between p-4 rounded-2xl transition-all ${activeListId === list.id ? 'bg-indigo-600 text-white shadow-lg' : 'bg-white text-stone-600 border border-stone-200 hover:border-stone-300'}`}
              >
                <div className="flex items-center space-x-3 truncate">
                  <span className={activeListId === list.id ? 'text-white' : 'text-stone-400'}>
                    {getCategoryIcon(list.category)}
                  </span>
                  <span className="font-bold truncate">{list.title}</span>
                  {list.visibility === 'PRIVATE' && (
                    <Lock size={12} className={`shrink-0 ${activeListId === list.id ? 'text-indigo-200' : 'text-stone-400'}`} />
                  )}
                </div>
                <span className={`text-[10px] font-black px-2 py-1 rounded-full ${activeListId === list.id ? 'bg-indigo-500 text-white' : 'bg-stone-100 text-stone-500'}`}>
                  {list.items.length}
                </span>
              </button>
            ))}
          </div>
        </div>

        {/* Active List Detail */}
        <div className="lg:col-span-3 space-y-6">
          {activeList ? (
            <div className="bg-white rounded-3xl border border-stone-200 shadow-sm overflow-hidden min-h-[400px] flex flex-col">
              <div className="p-6 border-b border-stone-100 flex items-center justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-2xl font-black text-stone-800">{activeList.title}</h2>
                    {activeList.visibility === 'PRIVATE' && <Lock size={14} className="text-stone-400" />}
                  </div>
                  <p className="text-xs font-bold text-stone-400 uppercase tracking-widest">{activeList.category}</p>
                </div>
                <div className="flex items-center space-x-1">
                  <button
                    onClick={handleCategorize}
                    disabled={isCategorizing || activeList.items.length === 0}
                    title="AI Categorize Items"
                    className="flex items-center gap-1.5 px-3 py-2 text-sm font-bold rounded-xl transition-colors bg-indigo-50 text-indigo-600 hover:bg-indigo-100 disabled:opacity-50"
                  >
                    {isCategorizing ? <Loader2 size={16} className="animate-spin" /> : <Tags size={16} />}
                    <span className="hidden sm:inline">Categorize</span>
                  </button>
                  {hasCategories && (
                    <button
                      onClick={() => setGroupedView(!groupedView)}
                      title={groupedView ? 'Flat view' : 'Grouped view'}
                      className={`px-3 py-2 text-sm font-bold rounded-xl transition-colors ${groupedView ? 'bg-indigo-600 text-white' : 'bg-stone-100 text-stone-500 hover:bg-stone-200'}`}
                    >
                      {groupedView ? 'Grouped' : 'Flat'}
                    </button>
                  )}
                  {activeList.visibility === 'PRIVATE' && activeList.creatorId === user.id && (
                    <button onClick={() => shareList(activeList.id)} title="Share with Family" className="p-2 text-stone-300 hover:text-indigo-500">
                      <Share2 size={20} />
                    </button>
                  )}
                  <button onClick={() => deleteList(activeList.id)} className="p-2 text-stone-300 hover:text-red-500"><Trash2 size={20} /></button>
                </div>
              </div>

              <div className="flex-1 p-6 space-y-2 overflow-y-auto">
                {activeList.items.length === 0 ? (
                  <div className="text-center py-20 text-stone-400">List is empty. Add something below!</div>
                ) : groupedView && hasCategories ? (
                  <div className="space-y-4">
                    {getGroupedItems(activeList.items).map(([group, items]) => {
                      const isCollapsed = collapsedGroups[group];
                      const checkedCount = items.filter(i => i.checked).length;
                      return (
                        <div key={group} className="border border-stone-100 rounded-2xl overflow-hidden">
                          <button
                            onClick={() => toggleGroup(group)}
                            className="w-full flex items-center justify-between px-4 py-3 bg-stone-50 hover:bg-stone-100 transition-colors"
                          >
                            <div className="flex items-center gap-2">
                              <Tags size={14} className="text-indigo-500" />
                              <span className="font-bold text-sm text-stone-700">{group}</span>
                              <span className="text-[10px] font-bold bg-stone-200 text-stone-500 px-2 py-0.5 rounded-full">
                                {checkedCount}/{items.length}
                              </span>
                            </div>
                            {isCollapsed ? <ChevronDown size={16} className="text-stone-400" /> : <ChevronUp size={16} className="text-stone-400" />}
                          </button>
                          {!isCollapsed && (
                            <div className="px-2 py-1">
                              {items.map(item => (
                                <div key={item.id} className="group flex items-center p-3 hover:bg-stone-50 rounded-xl transition-all">
                                  {editingItemId === item.id ? (
                                    <div className="flex-1 flex items-center gap-2">
                                      <input type="text" value={editItemText} onChange={(e) => setEditItemText(e.target.value)}
                                        onKeyDown={(e) => e.key === 'Enter' && saveEditItem()} autoFocus
                                        className="flex-1 px-3 py-2 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900" placeholder="Item name" />
                                      <input type="text" value={editItemQuantity} onChange={(e) => setEditItemQuantity(e.target.value)}
                                        onKeyDown={(e) => e.key === 'Enter' && saveEditItem()}
                                        className="w-24 px-3 py-2 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900" placeholder="Qty" />
                                      <button onClick={saveEditItem} className="p-2 text-emerald-600 hover:bg-emerald-50 rounded-lg"><Check size={16} /></button>
                                      <button onClick={() => setEditingItemId(null)} className="p-2 text-stone-400 hover:bg-stone-100 rounded-lg"><X size={16} /></button>
                                    </div>
                                  ) : (
                                    <>
                                      <button
                                        onClick={() => toggleItem(activeList.id, item.id)}
                                        className={`mr-4 transition-colors ${item.checked ? 'text-indigo-600' : 'text-stone-300 hover:text-indigo-500'}`}
                                      >
                                        {item.checked ? <CheckSquare size={22} /> : <Square size={22} />}
                                      </button>
                                      <div className="flex-1">
                                        <p className={`font-semibold ${item.checked ? 'text-stone-400 line-through' : 'text-stone-700'}`}>{item.text}</p>
                                        {item.quantity && <p className="text-[10px] font-bold text-stone-400">{item.quantity}</p>}
                                      </div>
                                      <div className="flex items-center space-x-1">
                                        <button onClick={() => startEditItem(item)} className="p-2 text-stone-300 hover:text-indigo-500 active:text-indigo-500 rounded-lg transition-colors"><Pencil size={16} /></button>
                                        <button onClick={() => deleteItem(item.id)} className="p-2 text-stone-300 hover:text-red-500 active:text-red-500 rounded-lg transition-colors"><Trash2 size={16} /></button>
                                      </div>
                                    </>
                                  )}
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                ) : (
                  activeList.items.map(item => (
                    <div key={item.id} className="group flex items-center p-3 hover:bg-stone-50 rounded-xl transition-all">
                      {editingItemId === item.id ? (
                        <div className="flex-1 flex items-center gap-2">
                          <input
                            type="text"
                            value={editItemText}
                            onChange={(e) => setEditItemText(e.target.value)}
                            onKeyDown={(e) => e.key === 'Enter' && saveEditItem()}
                            autoFocus
                            className="flex-1 px-3 py-2 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                            placeholder="Item name"
                          />
                          <input
                            type="text"
                            value={editItemQuantity}
                            onChange={(e) => setEditItemQuantity(e.target.value)}
                            onKeyDown={(e) => e.key === 'Enter' && saveEditItem()}
                            className="w-24 px-3 py-2 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                            placeholder="Qty"
                          />
                          <button onClick={saveEditItem} className="p-2 text-emerald-600 hover:bg-emerald-50 rounded-lg"><Check size={16} /></button>
                          <button onClick={() => setEditingItemId(null)} className="p-2 text-stone-400 hover:bg-stone-100 rounded-lg"><X size={16} /></button>
                        </div>
                      ) : (
                        <>
                          <button
                            onClick={() => toggleItem(activeList.id, item.id)}
                            className={`mr-4 transition-colors ${item.checked ? 'text-indigo-600' : 'text-stone-300 hover:text-indigo-500'}`}
                          >
                            {item.checked ? <CheckSquare size={22} /> : <Square size={22} />}
                          </button>
                          <div className="flex-1">
                            <p className={`font-semibold ${item.checked ? 'text-stone-400 line-through' : 'text-stone-700'}`}>{item.text}</p>
                            {item.quantity && <p className="text-[10px] font-bold text-stone-400">{item.quantity}</p>}
                            {item.aiCategory && <p className="text-[10px] font-bold text-indigo-400">{item.aiCategory}</p>}
                          </div>
                          <div className="flex items-center space-x-1">
                            <button onClick={() => startEditItem(item)} className="p-2 text-stone-300 hover:text-indigo-500 active:text-indigo-500 rounded-lg transition-colors"><Pencil size={16} /></button>
                            <button onClick={() => deleteItem(item.id)} className="p-2 text-stone-300 hover:text-red-500 active:text-red-500 rounded-lg transition-colors"><Trash2 size={16} /></button>
                          </div>
                        </>
                      )}
                    </div>
                  ))
                )}
              </div>

              <div className="p-6 bg-stone-50 border-t border-stone-100">
                <div className="relative">
                  {/* Autocomplete suggestions — float above the input */}
                  {filteredSuggestions.length > 0 && (
                    <div role="listbox" className="absolute bottom-full left-0 right-0 mb-2 bg-white border border-stone-200 rounded-2xl shadow-lg overflow-hidden z-10">
                      {filteredSuggestions.map((text, idx) => (
                        <button
                          key={text}
                          role="option"
                          aria-selected={idx === suggestionIdx}
                          // onMouseDown so it fires before the input's onBlur
                          onMouseDown={(e) => {
                            e.preventDefault();
                            setNewItemText(text);
                            setSuggestionIdx(-1);
                            setShowSuggestions(false);
                            addInputRef.current?.focus();
                          }}
                          className={`w-full text-left px-5 py-3 text-stone-700 transition-colors text-sm font-medium flex items-center gap-3 border-b border-stone-50 last:border-0 ${idx === suggestionIdx ? 'bg-indigo-50 text-indigo-700' : 'hover:bg-indigo-50 hover:text-indigo-700'}`}
                        >
                          <History size={13} className="text-stone-300 shrink-0" />
                          {text}
                        </button>
                      ))}
                    </div>
                  )}
                  <input
                    ref={addInputRef}
                    type="text"
                    value={newItemText}
                    onChange={(e) => { setNewItemText(e.target.value); setShowSuggestions(true); setSuggestionIdx(-1); }}
                    onFocus={() => setShowSuggestions(true)}
                    onBlur={() => setShowSuggestions(false)}
                    onKeyDown={(e) => {
                      if (e.key === 'ArrowDown') { e.preventDefault(); setSuggestionIdx(i => Math.min(i + 1, filteredSuggestions.length - 1)); }
                      else if (e.key === 'ArrowUp') { e.preventDefault(); setSuggestionIdx(i => Math.max(i - 1, -1)); }
                      else if (e.key === 'Enter') {
                        if (suggestionIdx >= 0 && filteredSuggestions[suggestionIdx]) {
                          setNewItemText(filteredSuggestions[suggestionIdx]);
                          setSuggestionIdx(-1);
                          setShowSuggestions(false);
                        } else { addItem(); setShowSuggestions(false); setSuggestionIdx(-1); }
                      } else if (e.key === 'Escape') { setShowSuggestions(false); setSuggestionIdx(-1); }
                    }}
                    placeholder="Type and press enter to add..."
                    className="w-full px-5 py-4 bg-white border border-stone-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 pr-12 font-medium text-stone-900"
                  />
                  <button
                    onClick={() => { addItem(); setShowSuggestions(false); }}
                    className="absolute right-3 top-3 p-2 bg-indigo-600 text-white rounded-xl hover:bg-indigo-700"
                  >
                    <Plus size={20} />
                  </button>
                </div>
              </div>
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center h-[400px] bg-white border border-stone-200 border-dashed rounded-3xl text-stone-400">
              <CheckSquare size={48} className="mb-4 opacity-20" />
              <p>Select a list or create a new one to get started.</p>
            </div>
          )}
        </div>
      </div>

      {/* Create List Modal */}
      {isCreateOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl p-8 shadow-2xl">
            <h2 className="text-2xl font-bold mb-6">New List</h2>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">List Name</label>
                <input
                  type="text"
                  value={newListTitle}
                  onChange={(e) => setNewListTitle(e.target.value)}
                  autoFocus
                  className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
                  placeholder="e.g., Grocery Run"
                />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">Visibility</label>
                <div className="flex bg-stone-100 p-1 rounded-xl">
                  <button
                    onClick={() => setNewListVisibility('FAMILY')}
                    className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${newListVisibility === 'FAMILY' ? 'bg-white text-indigo-600 shadow-sm' : 'text-stone-500'}`}
                  >
                    <Globe size={14} /> Shared
                  </button>
                  <button
                    onClick={() => setNewListVisibility('PRIVATE')}
                    className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${newListVisibility === 'PRIVATE' ? 'bg-white text-stone-800 shadow-sm' : 'text-stone-500'}`}
                  >
                    <Lock size={14} /> Private
                  </button>
                </div>
              </div>
              <div className="pt-4 flex gap-3">
                <button onClick={() => setIsCreateOpen(false)} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold hover:bg-stone-200">Cancel</button>
                <button onClick={createList} disabled={!newListTitle} className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold hover:bg-indigo-700 disabled:opacity-50 shadow-lg shadow-indigo-100">Create</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Lists;
