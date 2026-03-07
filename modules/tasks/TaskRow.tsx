import React from 'react';
import {
  CheckCircle2, Circle, Lock, Globe, Share2, Trash2,
  Calendar, RefreshCw, Pencil, Bell, Clock,
} from 'lucide-react';
import { format } from 'date-fns';
import { Task, Visibility } from '../../types';

interface TaskRowProps {
  task: Task;
  getUserName: (id: string) => string;
  getUserInitials: (id: string) => string;
  getAvatarColor: (id: string) => string;
  onToggle: (id: string) => void;
  onEdit: (task: Task) => void;
  onShare: (id: string) => void;
  onDelete: (id: string) => void;
  currentUserId: string;
}

const TaskRow: React.FC<TaskRowProps> = ({
  task, getUserName, getUserInitials, getAvatarColor,
  onToggle, onEdit, onShare, onDelete, currentUserId,
}) => {
  const assignees = Array.isArray(task.assignees) ? task.assignees : [];

  return (
    <div className={`group flex items-center p-4 hover:bg-stone-50 transition-colors ${task.completed ? 'opacity-60' : ''}`}>
      <button
        onClick={() => onToggle(task.id)}
        className={`p-2 rounded-full transition-colors shrink-0 ${task.completed ? 'text-indigo-600 bg-indigo-50' : 'text-stone-300 hover:text-indigo-600'}`}
      >
        {task.completed ? <CheckCircle2 size={24} /> : <Circle size={24} />}
      </button>
      <div className="flex-1 ml-4 min-w-0">
        <div className="flex items-center gap-2">
          <h4 className={`font-semibold text-stone-800 truncate ${task.completed ? 'line-through text-stone-400' : ''}`}>
            {task.title}
          </h4>
          {task.visibility === 'PRIVATE' && (
            <Lock size={12} className="text-stone-400 shrink-0" />
          )}
        </div>
        <div className="flex items-center gap-3 mt-1.5 flex-wrap">
          <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider ${
            task.priority === 'HIGH' ? 'bg-red-100 text-red-600'
            : task.priority === 'MEDIUM' ? 'bg-amber-100 text-amber-600'
            : 'bg-blue-100 text-blue-600'
          }`}>
            {task.priority}
          </span>
          {/* Date + time */}
          <div className="flex items-center text-xs gap-1">
            <Calendar size={12} className="text-stone-400" />
            <span className={task.dueDate ? 'text-stone-400' : 'text-stone-300 italic'}>
              {task.dueDate ? format(new Date(task.dueDate), 'MMM d') : 'No date'}
            </span>
            {task.dueTime && (
              <>
                <Clock size={10} className="text-stone-300 ml-1" />
                <span className="text-stone-400">{task.dueTime}</span>
              </>
            )}
          </div>
          {/* Reminder */}
          {task.reminderMinutes !== undefined && task.dueDate && (
            <span className="flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-100 text-amber-600">
              <Bell size={9} />
              {task.reminderMinutes === 0 ? 'At time' : `${task.reminderMinutes}m before`}
            </span>
          )}
          {task.recurrence && task.recurrence !== 'NONE' && (
            <span className="flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-violet-100 text-violet-600">
              <RefreshCw size={10} />
              {task.recurrence === 'DAILY' ? 'Daily' : task.recurrence === 'WEEKLY' ? 'Weekly' : 'Monthly'}
            </span>
          )}
          {task.tags?.map(tag => (
            <span key={tag} className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-stone-100 text-stone-500">
              {tag}
            </span>
          ))}
          {assignees.length > 0 && (
            <div className="flex items-center -space-x-1.5">
              {assignees.slice(0, 4).map(aId => (
                <div key={aId} title={getUserName(aId)}
                  className={`w-5 h-5 rounded-full flex items-center justify-center text-white text-[8px] font-black ring-2 ring-white ${getAvatarColor(aId)}`}>
                  {getUserInitials(aId)}
                </div>
              ))}
              {assignees.length > 4 && (
                <div className="w-5 h-5 rounded-full flex items-center justify-center bg-stone-300 text-white text-[8px] font-black ring-2 ring-white">
                  +{assignees.length - 4}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
      <div className="flex items-center space-x-1 shrink-0">
        <button onClick={() => onEdit(task)} title="Edit task"
          className="p-2 text-stone-300 hover:text-indigo-500 active:text-indigo-500 rounded-lg transition-colors">
          <Pencil size={16} />
        </button>
        {task.visibility === 'PRIVATE' && task.creatorId === currentUserId && (
          <button onClick={() => onShare(task.id)} title="Share with Family"
            className="p-2 text-stone-300 hover:text-indigo-500 active:text-indigo-500 rounded-lg transition-colors">
            <Share2 size={16} />
          </button>
        )}
        <button onClick={() => onDelete(task.id)}
          className="p-2 text-stone-300 hover:text-red-500 active:text-red-500 rounded-lg transition-colors">
          <Trash2 size={18} />
        </button>
      </div>
    </div>
  );
};

export default TaskRow;
