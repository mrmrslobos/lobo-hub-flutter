import React from 'react';
import {
  Globe, Lock, X, RefreshCw, CheckCircle2, Bell, Clock,
} from 'lucide-react';
import { Visibility, Recurrence, User } from '../../types';

interface AssigneePickerProps {
  selected: string[];
  setSelected: React.Dispatch<React.SetStateAction<string[]>>;
  familyMembers: User[];
  getAvatarColor: (id: string) => string;
  getUserInitials: (id: string) => string;
}

export const AssigneePicker: React.FC<AssigneePickerProps> = ({
  selected, setSelected, familyMembers, getAvatarColor, getUserInitials,
}) => {
  const toggle = (userId: string) => {
    if (selected.includes(userId)) {
      if (selected.length > 1) setSelected(selected.filter(id => id !== userId));
    } else {
      setSelected([...selected, userId]);
    }
  };

  return (
    <div>
      <label className="block text-sm font-bold text-stone-700 mb-2">Assign To</label>
      <div className="flex flex-wrap gap-2">
        {familyMembers.map(member => {
          const isSelected = selected.includes(member.id);
          return (
            <button key={member.id} type="button" onClick={() => toggle(member.id)}
              className={`flex items-center gap-2 px-3 py-2 rounded-xl text-sm font-bold border-2 transition-all ${
                isSelected ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-stone-200 bg-white text-stone-500 hover:border-stone-300'
              }`}>
              <div className={`w-6 h-6 rounded-full flex items-center justify-center text-white text-[10px] font-black ${getAvatarColor(member.id)}`}>
                {getUserInitials(member.id)}
              </div>
              {member.name}
              {isSelected && <CheckCircle2 size={14} className="text-indigo-500" />}
            </button>
          );
        })}
      </div>
      {familyMembers.length <= 1 && (
        <p className="text-xs text-stone-400 mt-2">Invite family members to assign tasks to them.</p>
      )}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Shared task form fields
// ---------------------------------------------------------------------------

interface TaskFormFieldsProps {
  dueDate: string;
  setDueDate: (v: string) => void;
  dueTime: string;
  setDueTime: (v: string) => void;
  reminderMinutes: number | undefined;
  setReminderMinutes: (v: number | undefined) => void;
  folder: string;
  setFolder: (v: string) => void;
  priority: 'LOW' | 'MEDIUM' | 'HIGH';
  setPriority: (v: 'LOW' | 'MEDIUM' | 'HIGH') => void;
  visibility: Visibility;
  setVisibility: (v: Visibility) => void;
  recurrence: Recurrence;
  setRecurrence: (v: Recurrence) => void;
  allFolders: string[];
  assignees: string[];
  setAssignees: React.Dispatch<React.SetStateAction<string[]>>;
  familyMembers: User[];
  getAvatarColor: (id: string) => string;
  getUserInitials: (id: string) => string;
}

const REMINDER_OPTIONS = [
  { label: 'At time', value: 0 },
  { label: '5 min', value: 5 },
  { label: '15 min', value: 15 },
  { label: '30 min', value: 30 },
  { label: '1 hour', value: 60 },
  { label: '1 day', value: 1440 },
];

export const TaskFormFields: React.FC<TaskFormFieldsProps> = ({
  dueDate, setDueDate, dueTime, setDueTime, reminderMinutes, setReminderMinutes,
  folder, setFolder, priority, setPriority, visibility, setVisibility,
  recurrence, setRecurrence, allFolders, assignees, setAssignees,
  familyMembers, getAvatarColor, getUserInitials,
}) => (
  <div className="space-y-4">
    {/* Date + Time row */}
    <div className="grid grid-cols-2 gap-3">
      <div>
        <div className="flex items-center justify-between mb-2">
          <label className="text-sm font-bold text-stone-700">Due Date <span className="text-stone-400 font-normal">(opt.)</span></label>
          {dueDate && (
            <button type="button" onClick={() => { setDueDate(''); setDueTime(''); setReminderMinutes(undefined); }}
              className="text-[10px] text-stone-400 hover:text-red-500 font-bold">Clear</button>
          )}
        </div>
        <input type="date" value={dueDate} onChange={e => setDueDate(e.target.value)}
          className="w-full px-3 py-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900 text-sm" />
      </div>
      <div>
        <label className="block text-sm font-bold text-stone-700 mb-2">
          <span className="flex items-center gap-1"><Clock size={13} />Time <span className="text-stone-400 font-normal">(opt.)</span></span>
        </label>
        <input type="time" value={dueTime} onChange={e => setDueTime(e.target.value)}
          disabled={!dueDate}
          className="w-full px-3 py-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900 text-sm disabled:opacity-40" />
      </div>
    </div>

    {/* Reminder */}
    {dueDate && dueTime && (
      <div>
        <label className="block text-sm font-bold text-stone-700 mb-2">
          <span className="flex items-center gap-1"><Bell size={13} />Reminder</span>
        </label>
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={() => setReminderMinutes(undefined)}
            className={`px-3 py-1.5 rounded-xl text-xs font-bold border transition-all ${reminderMinutes === undefined ? 'bg-stone-800 text-white border-stone-800' : 'border-stone-200 text-stone-500 hover:border-stone-400'}`}>
            None
          </button>
          {REMINDER_OPTIONS.map(opt => (
            <button key={opt.value} type="button" onClick={() => setReminderMinutes(opt.value)}
              className={`px-3 py-1.5 rounded-xl text-xs font-bold border transition-all ${reminderMinutes === opt.value ? 'bg-amber-500 text-white border-amber-500' : 'border-stone-200 text-stone-500 hover:border-stone-400'}`}>
              {opt.label}
            </button>
          ))}
        </div>
      </div>
    )}

    {/* Folder */}
    <div>
      <label className="block text-sm font-bold text-stone-700 mb-2">Folder</label>
      <select value={folder} onChange={e => setFolder(e.target.value)}
        className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none text-stone-900 text-sm">
        {allFolders.filter(f => f !== 'All Tasks').map(f => (
          <option key={f} value={f}>{f}</option>
        ))}
      </select>
    </div>

    {/* Priority */}
    <div>
      <label className="block text-sm font-bold text-stone-700 mb-2">Priority</label>
      <div className="flex gap-2">
        {(['LOW', 'MEDIUM', 'HIGH'] as const).map(p => (
          <button key={p} type="button" onClick={() => setPriority(p)}
            className={`flex-1 py-2 rounded-xl text-xs font-bold border transition-all ${priority === p ? 'bg-stone-800 border-stone-800 text-white' : 'bg-white border-stone-200 text-stone-500 hover:border-stone-400'}`}>
            {p}
          </button>
        ))}
      </div>
    </div>

    {/* Assignees */}
    <AssigneePicker selected={assignees} setSelected={setAssignees}
      familyMembers={familyMembers} getAvatarColor={getAvatarColor} getUserInitials={getUserInitials} />

    {/* Recurrence */}
    <div>
      <label className="block text-sm font-bold text-stone-700 mb-2">Repeat</label>
      <div className="flex gap-2">
        {(['NONE', 'DAILY', 'WEEKLY', 'MONTHLY'] as const).map(r => (
          <button key={r} type="button" onClick={() => setRecurrence(r)}
            className={`flex-1 py-2 rounded-xl text-xs font-bold border transition-all flex items-center justify-center gap-1 ${recurrence === r ? 'bg-violet-600 border-violet-600 text-white' : 'bg-white border-stone-200 text-stone-500 hover:border-stone-400'}`}>
            {r !== 'NONE' && <RefreshCw size={10} />}
            {r === 'NONE' ? 'None' : r === 'DAILY' ? 'Daily' : r === 'WEEKLY' ? 'Weekly' : 'Monthly'}
          </button>
        ))}
      </div>
    </div>

    {/* Visibility */}
    <div>
      <label className="block text-sm font-bold text-stone-700 mb-2">Visibility</label>
      <div className="flex bg-stone-100 p-1 rounded-xl">
        <button type="button" onClick={() => setVisibility('FAMILY')}
          className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${visibility === 'FAMILY' ? 'bg-white text-indigo-600 shadow-sm' : 'text-stone-500'}`}>
          <Globe size={14} /> Shared
        </button>
        <button type="button" onClick={() => setVisibility('PRIVATE')}
          className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-bold transition-all ${visibility === 'PRIVATE' ? 'bg-white text-stone-800 shadow-sm' : 'text-stone-500'}`}>
          <Lock size={14} /> Private
        </button>
      </div>
    </div>
  </div>
);

// ---------------------------------------------------------------------------
// New Task Modal
// ---------------------------------------------------------------------------

interface NewTaskModalProps {
  title: string;
  setTitle: (v: string) => void;
  dueDate: string;
  setDueDate: (v: string) => void;
  dueTime: string;
  setDueTime: (v: string) => void;
  reminderMinutes: number | undefined;
  setReminderMinutes: (v: number | undefined) => void;
  folder: string;
  setFolder: (v: string) => void;
  priority: 'LOW' | 'MEDIUM' | 'HIGH';
  setPriority: (v: 'LOW' | 'MEDIUM' | 'HIGH') => void;
  visibility: Visibility;
  setVisibility: (v: Visibility) => void;
  recurrence: Recurrence;
  setRecurrence: (v: Recurrence) => void;
  allFolders: string[];
  assignees: string[];
  setAssignees: React.Dispatch<React.SetStateAction<string[]>>;
  familyMembers: User[];
  getAvatarColor: (id: string) => string;
  getUserInitials: (id: string) => string;
  onCancel: () => void;
  onSubmit: () => void;
}

export const NewTaskModal: React.FC<NewTaskModalProps> = ({
  title, setTitle, onCancel, onSubmit, ...rest
}) => (
  <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
    <div className="bg-white w-full max-w-md rounded-3xl p-8 shadow-2xl max-h-[90vh] overflow-y-auto">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-2xl font-bold">Create New Task</h2>
        <button onClick={onCancel} className="p-2 text-stone-400 hover:bg-stone-100 rounded-xl transition-colors">
          <X size={18} />
        </button>
      </div>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-bold text-stone-700 mb-2">Title</label>
          <input type="text" value={title} onChange={e => setTitle(e.target.value)} autoFocus
            className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900"
            placeholder="Task name…" />
        </div>
        <TaskFormFields {...rest} />
        <div className="pt-4 flex gap-3">
          <button onClick={onCancel} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold hover:bg-stone-200">
            Cancel
          </button>
          <button onClick={onSubmit} disabled={!title.trim()}
            className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold hover:bg-indigo-700 disabled:opacity-50 shadow-lg shadow-indigo-100">
            Create
          </button>
        </div>
      </div>
    </div>
  </div>
);

// ---------------------------------------------------------------------------
// Edit Task Modal
// ---------------------------------------------------------------------------

interface EditTaskModalProps {
  title: string;
  setTitle: (v: string) => void;
  dueDate: string;
  setDueDate: (v: string) => void;
  dueTime: string;
  setDueTime: (v: string) => void;
  reminderMinutes: number | undefined;
  setReminderMinutes: (v: number | undefined) => void;
  folder: string;
  setFolder: (v: string) => void;
  priority: 'LOW' | 'MEDIUM' | 'HIGH';
  setPriority: (v: 'LOW' | 'MEDIUM' | 'HIGH') => void;
  visibility: Visibility;
  setVisibility: (v: Visibility) => void;
  recurrence: Recurrence;
  setRecurrence: (v: Recurrence) => void;
  allFolders: string[];
  assignees: string[];
  setAssignees: React.Dispatch<React.SetStateAction<string[]>>;
  familyMembers: User[];
  getAvatarColor: (id: string) => string;
  getUserInitials: (id: string) => string;
  onCancel: () => void;
  onSubmit: () => void;
}

export const EditTaskModal: React.FC<EditTaskModalProps> = ({
  title, setTitle, onCancel, onSubmit, ...rest
}) => (
  <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
    <div className="bg-white w-full max-w-md rounded-3xl p-8 shadow-2xl max-h-[90vh] overflow-y-auto">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-2xl font-bold">Edit Task</h2>
        <button onClick={onCancel} className="p-2 text-stone-400 hover:bg-stone-100 rounded-xl transition-colors">
          <X size={18} />
        </button>
      </div>
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-bold text-stone-700 mb-2">Title</label>
          <input type="text" value={title} onChange={e => setTitle(e.target.value)} autoFocus
            className="w-full px-4 py-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20 text-stone-900" />
        </div>
        <TaskFormFields {...rest} />
        <div className="pt-4 flex gap-3">
          <button onClick={onCancel} className="flex-1 py-3 bg-stone-100 text-stone-600 rounded-xl font-bold hover:bg-stone-200">
            Cancel
          </button>
          <button onClick={onSubmit} disabled={!title.trim()}
            className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold hover:bg-indigo-700 disabled:opacity-50 shadow-lg shadow-indigo-100">
            Save Changes
          </button>
        </div>
      </div>
    </div>
  </div>
);
