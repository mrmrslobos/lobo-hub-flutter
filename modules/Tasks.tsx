
import React, { useState, useMemo, useEffect } from 'react';
import { createId } from '../services/id';
import {
  Plus, Sparkles, Filter, ChevronDown, FolderOpen,
  FolderPlus, X, Users, Loader2, CheckCircle2, RefreshCw,
} from 'lucide-react';
import { Task, Visibility, Recurrence, User, Family } from '../types';
import { generateTaskBreakdown } from '../services/gemini';
import { format, addDays, addWeeks, addMonths } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import TaskRow from './tasks/TaskRow';
import { NewTaskModal, EditTaskModal } from './tasks/TaskModal';

const DEFAULT_FOLDERS = ['All Tasks', 'Home', 'Work', 'Personal', 'Shopping', 'AI Generated', 'Event'];

const AVATAR_COLORS = [
  'bg-indigo-500', 'bg-violet-500', 'bg-pink-500', 'bg-teal-500',
  'bg-amber-500', 'bg-emerald-500', 'bg-sky-500', 'bg-rose-500',
];

const Tasks: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isAiLoading, setIsAiLoading] = useState(false);
  const [aiGoal, setAiGoal] = useState('');
  const [aiError, setAiError] = useState('');
  const [filter, setFilter] = useState<'ALL' | 'TODAY' | 'HIGH' | 'MINE' | 'ASSIGNED'>('ALL');
  const [activeFolder, setActiveFolder] = useState('All Tasks');
  const [isAddingFolder, setIsAddingFolder] = useState(false);
  const [completedOpen, setCompletedOpen] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');

  // New task form state
  const [title, setTitle] = useState('');
  const [priority, setPriority] = useState<'LOW' | 'MEDIUM' | 'HIGH'>('MEDIUM');
  const [visibility, setVisibility] = useState<Visibility>('FAMILY');
  const [taskDueDate, setTaskDueDate] = useState('');
  const [taskDueTime, setTaskDueTime] = useState('');
  const [taskReminderMinutes, setTaskReminderMinutes] = useState<number | undefined>(undefined);
  const [taskFolder, setTaskFolder] = useState('Home');
  const [taskAssignees, setTaskAssignees] = useState<string[]>([user.id]);
  const [taskRecurrence, setTaskRecurrence] = useState<Recurrence>('NONE');

  // Edit task form state
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [editPriority, setEditPriority] = useState<'LOW' | 'MEDIUM' | 'HIGH'>('MEDIUM');
  const [editVisibility, setEditVisibility] = useState<Visibility>('FAMILY');
  const [editDueDate, setEditDueDate] = useState('');
  const [editDueTime, setEditDueTime] = useState('');
  const [editReminderMinutes, setEditReminderMinutes] = useState<number | undefined>(undefined);
  const [editFolder, setEditFolder] = useState('Home');
  const [editAssignees, setEditAssignees] = useState<string[]>([]);
  const [editRecurrence, setEditRecurrence] = useState<Recurrence>('NONE');

  // Re-schedule any pending task reminders that survived a page reload
  useEffect(() => {
    if (!('Notification' in window) || Notification.permission !== 'granted') return;
    const tasks: Task[] = Array.isArray(db.tasks) ? db.tasks : [];
    tasks
      .filter(t => t.familyId === family.id && !t.completed && t.dueDate && t.dueTime && t.reminderMinutes !== undefined)
      .forEach(scheduleTaskReminder);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Run once on mount only

  // Family members
  const familyMembers = useMemo(() => {
    const memberIds = (Array.isArray(db.familyMembers) ? db.familyMembers : [])
      .filter(m => m.familyId === family.id)
      .map(m => m.userId);
    return (Array.isArray(db.users) ? db.users : []).filter(u => memberIds.includes(u.id));
  }, [db.familyMembers, db.users, family.id]);

  const getUserName = (userId: string) => familyMembers.find(m => m.id === userId)?.name || 'Unknown';
  const getUserInitials = (userId: string) => { const n = getUserName(userId); if (!n?.trim()) return '?'; return n.split(' ').map(w => w[0]).filter(Boolean).join('').toUpperCase().slice(0, 2) || '?'; };
  const getAvatarColor = (userId: string) => {
    let hash = 0;
    for (let i = 0; i < userId.length; i++) hash = userId.charCodeAt(i) + ((hash << 5) - hash);
    return AVATAR_COLORS[Math.abs(hash) % AVATAR_COLORS.length];
  };

  const visibleTasks = useMemo(() => {
    return (Array.isArray(db.tasks) ? db.tasks : []).filter(t =>
      t.familyId === family.id &&
      (t.visibility === 'FAMILY' || t.creatorId === user.id)
    );
  }, [db.tasks, family.id, user.id]);

  const allFolders = useMemo(() => {
    const tagSet = new Set<string>(DEFAULT_FOLDERS);
    visibleTasks.forEach(t => t.tags?.forEach(tag => tagSet.add(tag)));
    return Array.from(tagSet);
  }, [visibleTasks]);

  const folderCounts = useMemo(() => {
    const counts: Record<string, number> = { 'All Tasks': visibleTasks.filter(t => !t.completed).length };
    allFolders.forEach(f => {
      if (f === 'All Tasks') return;
      counts[f] = visibleTasks.filter(t => !t.completed && t.tags?.includes(f)).length;
    });
    return counts;
  }, [visibleTasks, allFolders]);

  const filteredTasks = useMemo(() => {
    let tasks = visibleTasks;
    if (activeFolder !== 'All Tasks') tasks = tasks.filter(t => t.tags?.includes(activeFolder));
    if (filter === 'TODAY') {
      tasks = tasks.filter(t => t.dueDate && format(new Date(t.dueDate), 'yyyy-MM-dd') === format(new Date(), 'yyyy-MM-dd'));
    } else if (filter === 'HIGH') {
      tasks = tasks.filter(t => t.priority === 'HIGH');
    } else if (filter === 'MINE') {
      tasks = tasks.filter(t => (Array.isArray(t.assignees) ? t.assignees : []).includes(user.id) || t.creatorId === user.id);
    } else if (filter === 'ASSIGNED') {
      tasks = tasks.filter(t => { const a = Array.isArray(t.assignees) ? t.assignees : []; return a.length > 0 && !a.includes(user.id); });
    }
    return tasks.sort((a, b) => {
      if (a.completed !== b.completed) return Number(a.completed) - Number(b.completed);
      const prio = { HIGH: 0, MEDIUM: 1, LOW: 2 };
      return (prio[a.priority] || 2) - (prio[b.priority] || 2);
    });
  }, [visibleTasks, filter, user.id, activeFolder]);

  const activeTasks = filteredTasks.filter(t => !t.completed);
  const completedTasks = filteredTasks.filter(t => t.completed);

  const getNextDueDate = (currentDue: string | undefined, recurrence: Recurrence) => {
    if (!currentDue) return undefined;
    const date = new Date(currentDue);
    switch (recurrence) {
      case 'DAILY': return addDays(date, 1).toISOString();
      case 'WEEKLY': return addWeeks(date, 1).toISOString();
      case 'MONTHLY': return addMonths(date, 1).toISOString();
      default: return currentDue;
    }
  };

  const toggleTask = (id: string) => {
    const task = (Array.isArray(db.tasks) ? db.tasks : []).find(t => t.id === id);
    const nowCompleted = !task?.completed;
    // Include completedBy so the notify-family edge function can correctly
    // attribute the completion and exclude the right person from notifications.
    let newTasks = (Array.isArray(db.tasks) ? db.tasks : []).map(t =>
      t.id === id ? { ...t, completed: nowCompleted, completedBy: nowCompleted ? user.id : undefined } : t
    );
    if (task && !task.completed && task.recurrence && task.recurrence !== 'NONE' && task.dueDate) {
      const nextTask: Task = { ...task, id: createId(), completed: false, dueDate: getNextDueDate(task.dueDate, task.recurrence) };
      newTasks = [...newTasks, nextTask];
    }
    save({ ...db, tasks: newTasks }, task?.completed ? 'unchecked a task' : 'completed a task', 'Tasks', task?.title || '');
  };

  const deleteTask = (id: string) => {
    save({ ...db, tasks: (Array.isArray(db.tasks) ? db.tasks : []).filter(t => t.id !== id) }, 'deleted a task', 'Tasks', '');
  };

  const shareTask = (id: string) => {
    save({ ...db, tasks: (Array.isArray(db.tasks) ? db.tasks : []).map(t => t.id === id ? { ...t, visibility: 'FAMILY' as Visibility } : t) }, 'shared a task', 'Tasks', '');
  };

  const addTask = (customTask?: Partial<Task>) => {
    const folder = customTask?.tags?.[0] || taskFolder;
    const rawDueDate = customTask?.dueDate ?? (taskDueDate ? taskDueDate + 'T12:00:00.000Z' : undefined);
    const newTask: Task = {
      id: createId(),
      familyId: family.id,
      creatorId: user.id,
      title: customTask?.title || title,
      dueDate: rawDueDate,
      dueTime: customTask?.dueTime ?? (taskDueTime || undefined),
      reminderMinutes: customTask?.reminderMinutes ?? taskReminderMinutes,
      priority: (customTask?.priority as any) || priority,
      completed: false,
      visibility: customTask?.visibility || visibility,
      assignees: customTask?.assignees || taskAssignees,
      tags: [folder],
      recurrence: customTask?.recurrence || taskRecurrence,
    };
    save({ ...db, tasks: [...(Array.isArray(db.tasks) ? db.tasks : []), newTask] }, 'added a task', 'Tasks', customTask?.title || title);
    setTitle('');
    setTaskDueDate('');
    setTaskDueTime('');
    setTaskReminderMinutes(undefined);
    setTaskAssignees([user.id]);
    setTaskRecurrence('NONE');
    setIsModalOpen(false);

    // Schedule browser notification if reminder is set
    if (newTask.dueDate && newTask.dueTime && newTask.reminderMinutes !== undefined) {
      scheduleTaskReminder(newTask);
    }
  };

  const openEditModal = (task: Task) => {
    setEditingTask(task);
    setEditTitle(task.title);
    setEditPriority(task.priority);
    setEditVisibility(task.visibility);
    setEditDueDate(task.dueDate ? format(new Date(task.dueDate), 'yyyy-MM-dd') : '');
    setEditDueTime(task.dueTime || '');
    setEditReminderMinutes(task.reminderMinutes);
    setEditFolder(task.tags?.[0] || 'Home');
    setEditAssignees(Array.isArray(task.assignees) ? [...task.assignees] : [user.id]);
    setEditRecurrence(task.recurrence || 'NONE');
  };

  const saveEdit = () => {
    if (!editingTask || !editTitle.trim()) return;
    const newTasks = (Array.isArray(db.tasks) ? db.tasks : []).map(t =>
      t.id === editingTask.id ? {
        ...t,
        title: editTitle.trim(),
        priority: editPriority,
        visibility: editVisibility,
        dueDate: editDueDate ? editDueDate + 'T12:00:00.000Z' : undefined,
        dueTime: editDueTime || undefined,
        reminderMinutes: editReminderMinutes,
        tags: [editFolder],
        assignees: editAssignees,
        recurrence: editRecurrence,
        updatedBy: user.id,
      } : t
    );
    save({ ...db, tasks: newTasks }, 'edited a task', 'Tasks', editTitle.trim());
    setEditingTask(null);
  };

  const addFolder = () => {
    if (!newFolderName.trim() || allFolders.includes(newFolderName.trim())) return;
    setActiveFolder(newFolderName.trim());
    setTaskFolder(newFolderName.trim());
    setNewFolderName('');
    setIsAddingFolder(false);
    setIsModalOpen(true);
  };

  const handleAiBreakdown = async () => {
    if (!aiGoal) return;
    setIsAiLoading(true);
    setAiError('');
    try {
      const breakdown = await generateTaskBreakdown(aiGoal);
      const newTasks: Task[] = breakdown.map((item: any) => ({
        id: createId(), familyId: family.id, creatorId: user.id,
        title: item.title, dueDate: undefined, priority: item.priority || 'MEDIUM',
        completed: false, visibility: 'FAMILY' as Visibility, assignees: [user.id], tags: ['AI Generated'],
      }));
      save({ ...db, tasks: [...(Array.isArray(db.tasks) ? db.tasks : []), ...newTasks] }, 'generated AI tasks', 'Tasks', aiGoal);
      setAiGoal('');
      setActiveFolder('AI Generated');
    } catch (e: any) {
      setAiError(e?.message || 'AI failed to generate tasks. Check your API key.');
    } finally {
      setIsAiLoading(false);
    }
  };

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Task Management</h1>
          <p className="text-stone-500">Collaborate on chores, projects, and reminders.</p>
        </div>
        <button onClick={() => setIsModalOpen(true)}
          className="bg-indigo-600 text-white px-6 py-3 rounded-2xl font-bold flex items-center justify-center space-x-2 shadow-xl shadow-indigo-100">
          <Plus size={20} /><span>Add New Task</span>
        </button>
      </header>

      {/* AI Assistant */}
      <div className="bg-gradient-to-r from-indigo-600 to-violet-600 rounded-3xl p-6 text-white relative overflow-hidden">
        <Sparkles className="absolute right-[-20px] top-[-20px] w-48 h-48 opacity-10" />
        <div className="relative z-10">
          <h3 className="text-xl font-bold mb-2 flex items-center"><Sparkles size={20} className="mr-2" />AI Project Planner</h3>
          <p className="text-indigo-100 text-sm mb-4">Tell me your big goal and I'll break it down into small tasks for the family.</p>
          <div className="flex flex-col sm:flex-row gap-3">
            <input type="text" placeholder="e.g., Plan a backyard summer party…" value={aiGoal} onChange={e => setAiGoal(e.target.value)}
              className="flex-1 px-4 py-2 bg-white/10 backdrop-blur-md border border-white/20 rounded-xl text-white placeholder:text-white/50 focus:outline-none focus:ring-2 focus:ring-white/50" />
            <button onClick={handleAiBreakdown} disabled={isAiLoading || !aiGoal}
              className="bg-white text-indigo-600 px-6 py-2 rounded-xl font-bold hover:bg-stone-50 disabled:opacity-50 transition-colors flex items-center justify-center min-w-[120px]">
              {isAiLoading ? <Loader2 size={18} className="animate-spin" /> : 'Generate'}
            </button>
          </div>
          {aiError && <p className="mt-3 text-sm text-red-200 bg-red-500/20 px-4 py-2 rounded-xl">{aiError}</p>}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        {/* Sidebar */}
        <div className="space-y-4">
          <div className="flex items-center justify-between px-2">
            <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest">Folders</h3>
            <button onClick={() => setIsAddingFolder(true)}
              className="p-1.5 text-stone-400 hover:text-indigo-600 hover:bg-indigo-50 rounded-lg transition-colors" title="New Folder">
              <FolderPlus size={16} />
            </button>
          </div>
          {isAddingFolder && (
            <div className="flex items-center gap-2 px-2">
              <input type="text" placeholder="Folder name…" autoFocus value={newFolderName}
                onChange={e => setNewFolderName(e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter') addFolder(); if (e.key === 'Escape') setIsAddingFolder(false); }}
                className="flex-1 px-3 py-2 text-sm border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-600/20" />
              <button onClick={addFolder} className="p-2 text-indigo-600 hover:bg-indigo-50 rounded-lg"><Plus size={16} /></button>
              <button onClick={() => { setIsAddingFolder(false); setNewFolderName(''); }} className="p-2 text-stone-400 hover:bg-stone-100 rounded-lg"><X size={16} /></button>
            </div>
          )}
          <div className="space-y-1">
            {allFolders.map(folder => (
              <button key={folder} onClick={() => setActiveFolder(folder)}
                className={`w-full flex items-center justify-between p-3 rounded-2xl transition-all ${activeFolder === folder ? 'bg-indigo-600 text-white shadow-lg' : 'text-stone-600 hover:bg-white hover:shadow-sm'}`}>
                <div className="flex items-center gap-2.5 truncate">
                  <FolderOpen size={16} className={activeFolder === folder ? 'text-white' : 'text-stone-400'} />
                  <span className="font-bold text-sm truncate">{folder}</span>
                </div>
                <span className={`text-[10px] font-black px-2 py-0.5 rounded-full ${activeFolder === folder ? 'bg-indigo-500 text-white' : 'bg-stone-100 text-stone-500'}`}>
                  {folderCounts[folder] || 0}
                </span>
              </button>
            ))}
          </div>
          {familyMembers.length > 1 && (
            <div className="mt-6">
              <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest px-2 mb-3">Team</h3>
              <div className="space-y-1">
                {familyMembers.map(member => {
                  const memberTaskCount = visibleTasks.filter(t => !t.completed && (Array.isArray(t.assignees) ? t.assignees : []).includes(member.id)).length;
                  return (
                    <div key={member.id} className="flex items-center gap-3 px-3 py-2 rounded-xl hover:bg-white transition-colors">
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-black ${getAvatarColor(member.id)}`}>
                        {getUserInitials(member.id)}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-bold text-stone-700 truncate">
                          {member.name}{member.id === user.id && <span className="text-stone-400 font-normal"> (you)</span>}
                        </p>
                        <p className="text-[10px] text-stone-400">{memberTaskCount} task{memberTaskCount !== 1 ? 's' : ''}</p>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Main area */}
        <div className="lg:col-span-3 space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="flex items-center space-x-2 overflow-x-auto pb-1 scrollbar-hide">
              {(['ALL', 'MINE', 'ASSIGNED', 'TODAY', 'HIGH'] as const).map(f => (
                <button key={f} onClick={() => setFilter(f)}
                  className={`px-3 py-1.5 rounded-xl text-xs font-bold whitespace-nowrap transition-colors ${filter === f ? 'bg-stone-800 text-white' : 'bg-white text-stone-500 border border-stone-200 hover:border-stone-300'}`}>
                  {f === 'ALL' ? 'All' : f === 'MINE' ? 'My Tasks' : f === 'ASSIGNED' ? 'Others' : f === 'TODAY' ? 'Due Today' : 'High Priority'}
                </button>
              ))}
            </div>
            {filteredTasks.length > 0 && (
              <div className="flex items-center gap-3 text-sm text-stone-400 shrink-0">
                <span className="font-bold">{completedTasks.length}/{filteredTasks.length} done</span>
                <div className="w-24 h-2 bg-stone-100 rounded-full overflow-hidden">
                  <div className="h-full bg-indigo-500 rounded-full transition-all duration-500"
                    style={{ width: `${(completedTasks.length / filteredTasks.length) * 100}%` }} />
                </div>
              </div>
            )}
          </div>

          <div className="bg-white rounded-3xl border border-stone-200 shadow-sm overflow-hidden">
            {filteredTasks.length === 0 ? (
              <div className="text-center py-20">
                <div className="bg-stone-50 w-20 h-20 rounded-full flex items-center justify-center mx-auto mb-4 text-stone-200">
                  <FolderOpen size={40} />
                </div>
                <p className="text-stone-400 font-medium">
                  {activeFolder === 'All Tasks' ? 'No tasks found. Try adding one!' : `No tasks in "${activeFolder}". Add one!`}
                </p>
              </div>
            ) : (
              <>
                {activeTasks.length > 0 ? (
                  <div className="divide-y divide-stone-100">
                    {activeTasks.map(task => (
                      <TaskRow key={task.id} task={task}
                        getUserName={getUserName} getUserInitials={getUserInitials} getAvatarColor={getAvatarColor}
                        onToggle={toggleTask} onEdit={openEditModal} onShare={shareTask} onDelete={deleteTask}
                        currentUserId={user.id} />
                    ))}
                  </div>
                ) : (
                  <div className="flex flex-col items-center py-12 text-stone-400">
                    <CheckCircle2 size={32} className="mb-3 text-indigo-300" />
                    <p className="font-medium">All tasks completed!</p>
                  </div>
                )}
                {completedTasks.length > 0 && (
                  <div className={activeTasks.length > 0 ? 'border-t border-stone-100' : ''}>
                    <button onClick={() => setCompletedOpen(!completedOpen)}
                      className="w-full flex items-center justify-between px-5 py-4 hover:bg-stone-50 active:bg-stone-100 transition-colors">
                      <div className="flex items-center gap-2.5">
                        <CheckCircle2 size={16} className="text-indigo-400" />
                        <span className="text-sm font-bold text-stone-500">Completed</span>
                        <span className="text-[11px] font-black bg-stone-100 text-stone-500 px-2 py-0.5 rounded-full">{completedTasks.length}</span>
                      </div>
                      <ChevronDown size={16} className={`text-stone-400 transition-transform duration-200 ${completedOpen ? 'rotate-180' : ''}`} />
                    </button>
                    {completedOpen && (
                      <div className="divide-y divide-stone-100 border-t border-stone-100">
                        {completedTasks.map(task => (
                          <TaskRow key={task.id} task={task}
                            getUserName={getUserName} getUserInitials={getUserInitials} getAvatarColor={getAvatarColor}
                            onToggle={toggleTask} onEdit={openEditModal} onShare={shareTask} onDelete={deleteTask}
                            currentUserId={user.id} />
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      </div>

      {/* New Task Modal */}
      {isModalOpen && (
        <NewTaskModal
          title={title} setTitle={setTitle}
          dueDate={taskDueDate} setDueDate={setTaskDueDate}
          dueTime={taskDueTime} setDueTime={setTaskDueTime}
          reminderMinutes={taskReminderMinutes} setReminderMinutes={setTaskReminderMinutes}
          folder={taskFolder} setFolder={setTaskFolder}
          priority={priority} setPriority={setPriority}
          visibility={visibility} setVisibility={setVisibility}
          recurrence={taskRecurrence} setRecurrence={setTaskRecurrence}
          allFolders={allFolders}
          assignees={taskAssignees} setAssignees={setTaskAssignees}
          familyMembers={familyMembers}
          getAvatarColor={getAvatarColor} getUserInitials={getUserInitials}
          onCancel={() => { setIsModalOpen(false); setTaskAssignees([user.id]); setTaskRecurrence('NONE'); setTaskDueTime(''); setTaskReminderMinutes(undefined); }}
          onSubmit={addTask}
        />
      )}

      {/* Edit Task Modal */}
      {editingTask && (
        <EditTaskModal
          title={editTitle} setTitle={setEditTitle}
          dueDate={editDueDate} setDueDate={setEditDueDate}
          dueTime={editDueTime} setDueTime={setEditDueTime}
          reminderMinutes={editReminderMinutes} setReminderMinutes={setEditReminderMinutes}
          folder={editFolder} setFolder={setEditFolder}
          priority={editPriority} setPriority={setEditPriority}
          visibility={editVisibility} setVisibility={setEditVisibility}
          recurrence={editRecurrence} setRecurrence={setEditRecurrence}
          allFolders={allFolders}
          assignees={editAssignees} setAssignees={setEditAssignees}
          familyMembers={familyMembers}
          getAvatarColor={getAvatarColor} getUserInitials={getUserInitials}
          onCancel={() => setEditingTask(null)}
          onSubmit={saveEdit}
        />
      )}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Browser notification scheduler for task reminders
// ---------------------------------------------------------------------------
function scheduleTaskReminder(task: Task) {
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  if (!task.dueDate || !task.dueTime || task.reminderMinutes === undefined) return;

  const dueDateStr = task.dueDate.split('T')[0];
  const dueMs = new Date(`${dueDateStr}T${task.dueTime}`).getTime();
  const notifyMs = dueMs - task.reminderMinutes * 60 * 1000;
  const delay = notifyMs - Date.now();
  if (delay <= 0) return; // already passed

  setTimeout(() => {
    new Notification('Task Reminder', {
      body: task.title + (task.reminderMinutes === 0 ? ' — due now!' : ` — due in ${task.reminderMinutes} minutes`),
      icon: '/icons/icon-192.svg',
    });
  }, delay);
}

export default Tasks;
