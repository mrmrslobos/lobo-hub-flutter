import React, { useState, useMemo, useRef, useCallback } from 'react';
import {
  Camera, Heart, MessageCircle, Plus, Trash2, X, Image as ImageIcon,
  Star, BookOpen, Upload, ChevronLeft, ChevronRight, Sparkles, Tag,
  Baby, Trophy, Plane, School, PartyPopper, Stethoscope, Users,
} from 'lucide-react';
import { format, parseISO, startOfMonth } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { createId } from '../services/id';
import { supabase } from '../services/supabase';
import {
  User, Family, FamilyPhoto, Milestone, MilestoneCategory, MILESTONE_CATEGORIES, Visibility,
} from '../types';

// ── Constants ─────────────────────────────────────────────────────────────────

const CATEGORY_META: Record<MilestoneCategory, { emoji: string; icon: React.ReactNode; color: string }> = {
  Firsts:       { emoji: '⭐', icon: <Star size={14} />,        color: 'bg-amber-100 text-amber-700' },
  'Growing Up': { emoji: '👶', icon: <Baby size={14} />,        color: 'bg-pink-100 text-pink-700' },
  School:       { emoji: '🎒', icon: <School size={14} />,      color: 'bg-blue-100 text-blue-700' },
  Activities:   { emoji: '🏆', icon: <Trophy size={14} />,      color: 'bg-green-100 text-green-700' },
  Travel:       { emoji: '✈️', icon: <Plane size={14} />,       color: 'bg-sky-100 text-sky-700' },
  Celebrations: { emoji: '🎉', icon: <PartyPopper size={14} />, color: 'bg-violet-100 text-violet-700' },
  Health:       { emoji: '❤️', icon: <Stethoscope size={14} />, color: 'bg-rose-100 text-rose-700' },
  Family:       { emoji: '👨‍👩‍👧', icon: <Users size={14} />,       color: 'bg-indigo-100 text-indigo-700' },
};

const REACTION_EMOJIS = ['❤️', '😍', '😂', '🥹', '🎉', '👏'];

// ── Photo upload helpers ───────────────────────────────────────────────────────

async function uploadPhotoToSupabase(
  file: File,
  familyId: string,
): Promise<string> {
  if (!supabase) throw new Error('Supabase not configured');
  const ext = file.name.split('.').pop() ?? 'jpg';
  const path = `${familyId}/${Date.now()}-${createId()}.${ext}`;
  const { error } = await supabase.storage.from('family-photos').upload(path, file, { upsert: false });
  if (error) throw new Error(error.message);
  const { data } = supabase.storage.from('family-photos').getPublicUrl(path);
  return data.publicUrl;
}

/** Resize & convert a File to a base64 data URI (max 800px wide) for local fallback. */
function fileToDataUri(file: File, maxWidth = 800): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new window.Image();
    const reader = new FileReader();
    reader.onload = (e) => {
      img.onload = () => {
        const scale = Math.min(1, maxWidth / img.width);
        const canvas = document.createElement('canvas');
        canvas.width = img.width * scale;
        canvas.height = img.height * scale;
        canvas.getContext('2d')!.drawImage(img, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL('image/jpeg', 0.82));
      };
      img.onerror = reject;
      img.src = e.target?.result as string;
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

// ── Props ─────────────────────────────────────────────────────────────────────

interface PhotosProps { user: User; family: Family; }

// ── Component ─────────────────────────────────────────────────────────────────

const Photos: React.FC<PhotosProps> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [activeTab, setActiveTab] = useState<'timeline' | 'milestones'>('timeline');
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState('');

  // Photo modal
  const [viewPhoto, setViewPhoto] = useState<FamilyPhoto | null>(null);
  const [captionDraft, setCaptionDraft] = useState('');

  // Add photo form
  const [addModal, setAddModal] = useState(false);
  const [newCaption, setNewCaption] = useState('');
  const [newTakenAt, setNewTakenAt] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [newTags, setNewTags] = useState('');
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const [pendingPreview, setPendingPreview] = useState<string | null>(null);

  // Milestone modal
  const [milestoneModal, setMilestoneModal] = useState(false);
  const [msTitle, setMsTitle] = useState('');
  const [msEmoji, setMsEmoji] = useState('⭐');
  const [msCategory, setMsCategory] = useState<MilestoneCategory>('Firsts');
  const [msDate, setMsDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [msNotes, setMsNotes] = useState('');
  const [msAgeLabel, setMsAgeLabel] = useState('');
  const [msChildId, setMsChildId] = useState(user.id);
  const [editMilestoneId, setEditMilestoneId] = useState<string | null>(null);

  const [lightboxIndex, setLightboxIndex] = useState<number | null>(null);

  // ── Data ────────────────────────────────────────────────────────────────────

  const familyMembers = useMemo(() =>
    (db.users || []).filter(u => (db.familyMembers || []).some(fm => fm.userId === u.id && fm.familyId === family.id)),
    [db.users, db.familyMembers, family.id]);

  const photos = useMemo(() =>
    (db.familyPhotos || [])
      .filter(p => p.familyId === family.id)
      .sort((a, b) => b.takenAt.localeCompare(a.takenAt)),
    [db.familyPhotos, family.id]);

  const milestones = useMemo(() =>
    (db.milestones || [])
      .filter(m => m.familyId === family.id)
      .sort((a, b) => b.date.localeCompare(a.date)),
    [db.milestones, family.id]);

  // Group photos by month
  const byMonth = useMemo(() => {
    const map = new Map<string, FamilyPhoto[]>();
    for (const p of photos) {
      const key = format(parseISO(p.takenAt), 'MMMM yyyy');
      map.set(key, [...(map.get(key) ?? []), p]);
    }
    return map;
  }, [photos]);

  // ── Photo upload ─────────────────────────────────────────────────────────────

  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPendingFile(file);
    const preview = await fileToDataUri(file);
    setPendingPreview(preview);
    setAddModal(true);
    e.target.value = '';
  };

  const handleUploadConfirm = useCallback(async () => {
    if (!pendingFile && !pendingPreview) return;
    setUploading(true);
    setUploadError('');
    try {
      let url = pendingPreview!;
      // Try Supabase Storage first; fall back to data URI
      if (supabase && pendingFile) {
        try {
          url = await uploadPhotoToSupabase(pendingFile, family.id);
        } catch {
          // Use local data URI as fallback
        }
      }
      const photo: FamilyPhoto = {
        id: createId(),
        familyId: family.id,
        uploaderId: user.id,
        url,
        caption: newCaption.trim() || undefined,
        takenAt: newTakenAt,
        createdAt: new Date().toISOString(),
        reactions: [],
        tags: newTags.split(',').map(t => t.trim()).filter(Boolean),
        visibility: 'FAMILY',
      };
      save({ ...db, familyPhotos: [...(db.familyPhotos ?? []), photo] }, 'added photo', 'Photos', photo.caption ?? format(parseISO(newTakenAt), 'MMM d'));
      setAddModal(false);
      setPendingFile(null);
      setPendingPreview(null);
      setNewCaption('');
      setNewTags('');
      setNewTakenAt(format(new Date(), 'yyyy-MM-dd'));
    } catch (err: any) {
      setUploadError(err.message ?? 'Upload failed. Please try again.');
    } finally {
      setUploading(false);
    }
  }, [pendingFile, pendingPreview, newCaption, newTakenAt, newTags, db, family.id, user.id, save]);

  const handleDeletePhoto = (id: string) => {
    save({ ...db, familyPhotos: (db.familyPhotos ?? []).filter(p => p.id !== id) }, 'deleted photo', 'Photos', '');
    if (viewPhoto?.id === id) setViewPhoto(null);
    if (lightboxIndex !== null) setLightboxIndex(null);
  };

  const handleReact = (photoId: string, emoji: string) => {
    const updated = (db.familyPhotos ?? []).map(p => {
      if (p.id !== photoId) return p;
      const existing = p.reactions.find(r => r.userId === user.id && r.emoji === emoji);
      const reactions = existing
        ? p.reactions.filter(r => !(r.userId === user.id && r.emoji === emoji))
        : [...p.reactions, { userId: user.id, emoji }];
      return { ...p, reactions };
    });
    save({ ...db, familyPhotos: updated }, 'reacted to photo', 'Photos', emoji);
  };

  // ── Milestones ───────────────────────────────────────────────────────────────

  const openAddMilestone = () => {
    setEditMilestoneId(null);
    setMsTitle(''); setMsEmoji('⭐'); setMsCategory('Firsts');
    setMsDate(format(new Date(), 'yyyy-MM-dd')); setMsNotes('');
    setMsAgeLabel(''); setMsChildId(user.id);
    setMilestoneModal(true);
  };

  const openEditMilestone = (m: Milestone) => {
    setEditMilestoneId(m.id);
    setMsTitle(m.title); setMsEmoji(m.emoji); setMsCategory(m.category);
    setMsDate(m.date); setMsNotes(m.notes ?? '');
    setMsAgeLabel(m.ageLabel ?? ''); setMsChildId(m.childId);
    setMilestoneModal(true);
  };

  const handleSaveMilestone = () => {
    if (!msTitle.trim()) return;
    const entry: Milestone = {
      id: editMilestoneId ?? createId(),
      familyId: family.id,
      childId: msChildId,
      title: msTitle.trim(),
      emoji: msEmoji,
      category: msCategory,
      date: msDate,
      notes: msNotes.trim() || undefined,
      photoIds: editMilestoneId ? (milestones.find(m => m.id === editMilestoneId)?.photoIds ?? []) : [],
      ageLabel: msAgeLabel.trim() || undefined,
      createdAt: editMilestoneId
        ? (milestones.find(m => m.id === editMilestoneId)?.createdAt ?? new Date().toISOString())
        : new Date().toISOString(),
    };
    const updated = editMilestoneId
      ? (db.milestones ?? []).map(m => m.id === editMilestoneId ? entry : m)
      : [...(db.milestones ?? []), entry];
    save({ ...db, milestones: updated }, editMilestoneId ? 'updated milestone' : 'added milestone', 'Photos', entry.title);
    setMilestoneModal(false);
  };

  const handleDeleteMilestone = (id: string) => {
    save({ ...db, milestones: (db.milestones ?? []).filter(m => m.id !== id) }, 'deleted milestone', 'Photos', '');
  };

  // ── Lightbox ─────────────────────────────────────────────────────────────────

  const lightboxPhotos = useMemo(() => photos, [photos]);

  const lightboxPhoto = lightboxIndex !== null ? lightboxPhotos[lightboxIndex] : null;
  const goLightboxPrev = () => setLightboxIndex(i => (i !== null && i > 0) ? i - 1 : i);
  const goLightboxNext = () => setLightboxIndex(i => (i !== null && i < lightboxPhotos.length - 1) ? i + 1 : i);

  const uploaderName = (uploaderId: string) => (db.users ?? []).find(u => u.id === uploaderId)?.name ?? 'Family';

  // ── Render ────────────────────────────────────────────────────────────────────

  return (
    <div className="space-y-6">
      {/* Hidden file input */}
      <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileSelect} />

      {/* Header */}
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Family Photos</h1>
          <p className="text-stone-500">Your private family album & milestone moments.</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <button onClick={openAddMilestone}
            className="flex items-center gap-2 px-4 py-2.5 bg-amber-50 text-amber-700 border border-amber-200 rounded-2xl font-bold hover:bg-amber-100 transition-colors">
            <Star size={16} />Milestone
          </button>
          <button onClick={() => fileInputRef.current?.click()}
            className="flex items-center gap-2 px-5 py-2.5 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-100">
            <Camera size={18} />Add Photo
          </button>
        </div>
      </header>

      {/* Stats */}
      {(photos.length > 0 || milestones.length > 0) && (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[
            { label: 'Photos', value: photos.length, icon: <ImageIcon size={16} className="text-indigo-500" /> },
            { label: 'Milestones', value: milestones.length, icon: <Star size={16} className="text-amber-500" /> },
            { label: 'Reactions', value: photos.reduce((n, p) => n + p.reactions.length, 0), icon: <Heart size={16} className="text-rose-500" /> },
            { label: 'Months', value: byMonth.size, icon: <BookOpen size={16} className="text-emerald-500" /> },
          ].map(s => (
            <div key={s.label} className="bg-white rounded-2xl border border-stone-100 p-4 flex items-center gap-3">
              {s.icon}
              <div>
                <p className="text-xl font-black text-stone-800">{s.value}</p>
                <p className="text-xs text-stone-400 font-semibold">{s.label}</p>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Tabs */}
      <div className="flex bg-stone-100 p-1 rounded-2xl gap-1">
        {(['timeline', 'milestones'] as const).map(tab => (
          <button key={tab} onClick={() => setActiveTab(tab)}
            className={`flex-1 py-2 rounded-xl text-sm font-bold transition-all capitalize ${activeTab === tab ? 'bg-white text-stone-800 shadow-sm' : 'text-stone-500'}`}>
            {tab === 'timeline' ? `📸 Timeline` : `⭐ Milestones (${milestones.length})`}
          </button>
        ))}
      </div>

      {/* ── Timeline tab ── */}
      {activeTab === 'timeline' && (
        <>
          {photos.length === 0 ? (
            <div className="bg-white rounded-3xl border border-stone-100 p-16 text-center text-stone-400">
              <ImageIcon size={48} className="mx-auto mb-4 text-stone-200" />
              <p className="font-semibold text-lg">Your family album is empty</p>
              <p className="text-sm mt-2 max-w-xs mx-auto">Add photos to build your private family timeline — shared only with your family.</p>
              <button onClick={() => fileInputRef.current?.click()}
                className="mt-6 flex items-center gap-2 mx-auto px-6 py-3 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-100">
                <Upload size={18} />Upload First Photo
              </button>
            </div>
          ) : (
            Array.from(byMonth.entries()).map(([monthLabel, monthPhotos]) => (
              <div key={monthLabel} className="space-y-3">
                <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest">{monthLabel}</h3>
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
                  {monthPhotos.map((photo, idx) => {
                    const globalIdx = lightboxPhotos.findIndex(p => p.id === photo.id);
                    return (
                      <button
                        key={photo.id}
                        onClick={() => setLightboxIndex(globalIdx)}
                        className="relative aspect-square rounded-2xl overflow-hidden group bg-stone-100"
                      >
                        <img src={photo.url} alt={photo.caption ?? ''} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300" loading="lazy" />
                        {photo.reactions.length > 0 && (
                          <div className="absolute bottom-1.5 left-1.5 bg-black/50 text-white text-xs px-1.5 py-0.5 rounded-full flex items-center gap-1">
                            <Heart size={10} fill="currentColor" />{photo.reactions.length}
                          </div>
                        )}
                        {photo.milestoneId && (
                          <div className="absolute top-1.5 right-1.5 bg-amber-400 text-white text-xs px-1.5 py-0.5 rounded-full">
                            ⭐
                          </div>
                        )}
                      </button>
                    );
                  })}
                </div>
              </div>
            ))
          )}
        </>
      )}

      {/* ── Milestones tab ── */}
      {activeTab === 'milestones' && (
        <div className="space-y-3">
          {milestones.length === 0 ? (
            <div className="bg-white rounded-3xl border border-stone-100 p-16 text-center text-stone-400">
              <Star size={48} className="mx-auto mb-4 text-stone-200" />
              <p className="font-semibold text-lg">No milestones yet</p>
              <p className="text-sm mt-2">Record first steps, first words, first day of school — cherish every moment.</p>
              <button onClick={openAddMilestone}
                className="mt-6 flex items-center gap-2 mx-auto px-6 py-3 bg-amber-500 text-white rounded-2xl font-bold hover:bg-amber-600 transition-colors">
                <Star size={18} />Add First Milestone
              </button>
            </div>
          ) : (
            milestones.map(m => {
              const cat = CATEGORY_META[m.category];
              const child = (db.users ?? []).find(u => u.id === m.childId);
              return (
                <div key={m.id} className="bg-white rounded-2xl border border-stone-100 p-4 flex items-start gap-4 shadow-sm">
                  <div className={`w-12 h-12 rounded-2xl flex items-center justify-center text-2xl shrink-0 ${cat.color}`}>
                    {m.emoji}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <p className="font-bold text-stone-800">{m.title}</p>
                      <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${cat.color}`}>{m.category}</span>
                    </div>
                    <p className="text-xs text-stone-400 mt-0.5">
                      {child?.name ?? 'Family'} · {format(parseISO(m.date), 'MMMM d, yyyy')}
                      {m.ageLabel && ` · ${m.ageLabel}`}
                    </p>
                    {m.notes && <p className="text-sm text-stone-600 mt-1 italic">"{m.notes}"</p>}
                  </div>
                  <div className="flex gap-1 shrink-0">
                    <button onClick={() => openEditMilestone(m)} className="p-2 text-stone-300 hover:text-indigo-500 rounded-xl transition-colors">
                      <Star size={15} />
                    </button>
                    <button onClick={() => handleDeleteMilestone(m.id)} className="p-2 text-stone-300 hover:text-red-500 rounded-xl transition-colors">
                      <Trash2 size={15} />
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>
      )}

      {/* ── Add Photo Modal ── */}
      {addModal && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/60 p-4">
          <div className="bg-white rounded-3xl w-full max-w-md p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-xl font-bold text-stone-800">Add Photo</h2>
              <button onClick={() => { setAddModal(false); setPendingPreview(null); setPendingFile(null); }} className="p-2 hover:bg-stone-100 rounded-xl"><X size={20} /></button>
            </div>
            {pendingPreview && (
              <img src={pendingPreview} alt="Preview" className="w-full max-h-60 object-contain rounded-2xl bg-stone-100" />
            )}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-1.5">Caption <span className="font-normal text-stone-400">(optional)</span></label>
              <input value={newCaption} onChange={e => setNewCaption(e.target.value)} placeholder="What's happening here?"
                className="w-full px-4 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-1.5">Date taken</label>
                <input type="date" value={newTakenAt} onChange={e => setNewTakenAt(e.target.value)}
                  className="w-full px-3 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-1.5">Tags <span className="font-normal text-stone-400">(comma-sep)</span></label>
                <input value={newTags} onChange={e => setNewTags(e.target.value)} placeholder="birthday, school"
                  className="w-full px-3 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
              </div>
            </div>
            {uploadError && <p className="text-sm text-red-600 bg-red-50 rounded-xl px-3 py-2">{uploadError}</p>}
            <div className="flex gap-3">
              <button onClick={() => { setAddModal(false); setPendingPreview(null); setPendingFile(null); }}
                className="flex-1 py-3 bg-stone-100 text-stone-700 rounded-xl font-bold hover:bg-stone-200 transition-colors">
                Cancel
              </button>
              <button onClick={handleUploadConfirm} disabled={uploading || !pendingPreview}
                className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold hover:bg-indigo-700 transition-colors disabled:opacity-50 flex items-center justify-center gap-2">
                {uploading ? <><Sparkles size={16} className="animate-spin" />Uploading…</> : <><Upload size={16} />Save Photo</>}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Milestone Modal ── */}
      {milestoneModal && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/60 p-4">
          <div className="bg-white rounded-3xl w-full max-w-md p-6 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="text-xl font-bold text-stone-800">{editMilestoneId ? 'Edit Milestone' : 'Add Milestone'}</h2>
              <button onClick={() => setMilestoneModal(false)} className="p-2 hover:bg-stone-100 rounded-xl"><X size={20} /></button>
            </div>

            {/* For whom */}
            {familyMembers.length > 1 && (
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-2">For</label>
                <div className="flex flex-wrap gap-2">
                  {familyMembers.map(m => (
                    <button key={m.id} type="button" onClick={() => setMsChildId(m.id)}
                      className={`px-3 py-2 rounded-xl border-2 text-sm font-bold transition-all ${msChildId === m.id ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-stone-200 text-stone-500'}`}>
                      {m.name}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Category */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2">Category</label>
              <div className="grid grid-cols-2 gap-2">
                {(MILESTONE_CATEGORIES as readonly MilestoneCategory[]).map(c => (
                  <button key={c} type="button" onClick={() => { setMsCategory(c); setMsEmoji(CATEGORY_META[c].emoji); }}
                    className={`flex items-center gap-2 px-3 py-2 rounded-xl border-2 text-sm font-semibold transition-all ${msCategory === c ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-stone-200 text-stone-500'}`}>
                    <span>{CATEGORY_META[c].emoji}</span>{c}
                  </button>
                ))}
              </div>
            </div>

            {/* Title */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-1.5">Milestone</label>
              <input value={msTitle} onChange={e => setMsTitle(e.target.value)} placeholder="e.g. First steps, First word, Started school"
                className="w-full px-4 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-1.5">Date</label>
                <input type="date" value={msDate} onChange={e => setMsDate(e.target.value)}
                  className="w-full px-3 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
              </div>
              <div>
                <label className="block text-sm font-bold text-stone-700 mb-1.5">Age <span className="font-normal text-stone-400">(optional)</span></label>
                <input value={msAgeLabel} onChange={e => setMsAgeLabel(e.target.value)} placeholder="e.g. 10 months"
                  className="w-full px-3 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
              </div>
            </div>

            <div>
              <label className="block text-sm font-bold text-stone-700 mb-1.5">Notes <span className="font-normal text-stone-400">(optional)</span></label>
              <textarea value={msNotes} onChange={e => setMsNotes(e.target.value)} rows={2} placeholder="Describe the moment..."
                className="w-full px-4 py-2.5 border border-stone-200 rounded-xl text-sm resize-none focus:outline-none focus:ring-2 focus:ring-indigo-300" />
            </div>

            <div className="flex gap-3">
              <button onClick={() => setMilestoneModal(false)}
                className="flex-1 py-3 bg-stone-100 text-stone-700 rounded-xl font-bold hover:bg-stone-200 transition-colors">Cancel</button>
              <button onClick={handleSaveMilestone} disabled={!msTitle.trim()}
                className="flex-1 py-3 bg-amber-500 text-white rounded-xl font-bold hover:bg-amber-600 transition-colors disabled:opacity-40">
                {editMilestoneId ? 'Save Changes' : 'Add Milestone'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Lightbox ── */}
      {lightboxIndex !== null && lightboxPhoto && (
        <div className="fixed inset-0 z-[9000] flex items-center justify-center bg-black/90" onClick={() => setLightboxIndex(null)}>
          <button className="absolute top-4 right-4 text-white/70 hover:text-white p-2" onClick={() => setLightboxIndex(null)}><X size={28} /></button>

          {lightboxIndex > 0 && (
            <button className="absolute left-4 text-white/70 hover:text-white p-3 bg-black/30 rounded-full" onClick={e => { e.stopPropagation(); goLightboxPrev(); }}>
              <ChevronLeft size={28} />
            </button>
          )}
          {lightboxIndex < lightboxPhotos.length - 1 && (
            <button className="absolute right-4 text-white/70 hover:text-white p-3 bg-black/30 rounded-full" onClick={e => { e.stopPropagation(); goLightboxNext(); }}>
              <ChevronRight size={28} />
            </button>
          )}

          <div className="flex flex-col items-center gap-4 max-w-2xl w-full px-4" onClick={e => e.stopPropagation()}>
            <img src={lightboxPhoto.url} alt={lightboxPhoto.caption ?? ''} className="max-h-[70vh] max-w-full rounded-2xl object-contain" />

            <div className="bg-white/10 backdrop-blur rounded-2xl p-4 w-full space-y-3">
              {lightboxPhoto.caption && <p className="text-white font-medium text-center">{lightboxPhoto.caption}</p>}
              <p className="text-white/50 text-xs text-center">
                {format(parseISO(lightboxPhoto.takenAt), 'MMMM d, yyyy')} · Added by {uploaderName(lightboxPhoto.uploaderId)}
              </p>

              {/* Reactions */}
              <div className="flex items-center justify-center gap-2 flex-wrap">
                {REACTION_EMOJIS.map(emoji => {
                  const count = lightboxPhoto.reactions.filter(r => r.emoji === emoji).length;
                  const mine = lightboxPhoto.reactions.some(r => r.userId === user.id && r.emoji === emoji);
                  return (
                    <button key={emoji} onClick={() => handleReact(lightboxPhoto.id, emoji)}
                      className={`flex items-center gap-1 px-3 py-1.5 rounded-full text-sm font-bold transition-all ${mine ? 'bg-indigo-500 text-white' : 'bg-white/10 text-white hover:bg-white/20'}`}>
                      {emoji}{count > 0 && <span>{count}</span>}
                    </button>
                  );
                })}
              </div>

              {/* Tags */}
              {lightboxPhoto.tags.length > 0 && (
                <div className="flex flex-wrap gap-1.5 justify-center">
                  {lightboxPhoto.tags.map(tag => (
                    <span key={tag} className="flex items-center gap-1 text-xs text-white/60 bg-white/10 px-2 py-0.5 rounded-full">
                      <Tag size={10} />{tag}
                    </span>
                  ))}
                </div>
              )}

              {/* Delete (own photos only) */}
              {lightboxPhoto.uploaderId === user.id && (
                <div className="flex justify-center">
                  <button onClick={() => handleDeletePhoto(lightboxPhoto.id)}
                    className="flex items-center gap-2 text-xs text-red-400 hover:text-red-300 transition-colors px-3 py-1.5 rounded-full hover:bg-white/10">
                    <Trash2 size={13} />Delete photo
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Photos;
