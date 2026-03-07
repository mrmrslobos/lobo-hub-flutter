import React, { useState } from 'react';
import { X, Bell, BellOff, Globe, Smartphone } from 'lucide-react';
import { NotificationPrefs, DEFAULT_NOTIFICATION_PREFS } from '../types';
import { subscribeWebPush, unsubscribeWebPush } from '../services/pushNotifications';
import { Capacitor } from '@capacitor/core';

interface Props {
  prefs: NotificationPrefs;
  userId: string;
  familyId: string;
  onSave: (prefs: NotificationPrefs) => void;
  onClose: () => void;
}

const CATEGORIES: { key: keyof NotificationPrefs; label: string; desc: string }[] = [
  { key: 'chat',        label: 'Chat',         desc: 'New messages from family members' },
  { key: 'tasks',       label: 'Tasks',        desc: 'Task assignments and completions' },
  { key: 'calendar',    label: 'Calendar',     desc: 'Upcoming events (15 min reminder)' },
  { key: 'chores',      label: 'Chores',       desc: 'Chore assignments and completions' },
  { key: 'lists',       label: 'Lists',        desc: 'List updates and new items' },
  { key: 'polls',       label: 'Polls',        desc: 'New polls and results' },
  { key: 'meals',       label: 'Meals',        desc: 'Meal plan updates' },
  { key: 'birthdays',   label: 'Occasions',    desc: 'Birthdays, anniversaries & special dates' },
  { key: 'photos',      label: 'Photos',       desc: 'New family photos and milestones' },
  { key: 'location',    label: 'Location',     desc: 'Family member arrivals at saved places' },
  { key: 'weeklyDigest',label: 'Weekly Digest',desc: 'Sunday family summary digest' },
];

const NotificationSettings: React.FC<Props> = ({ prefs, userId, familyId, onSave, onClose }) => {
  const [local, setLocal] = useState<NotificationPrefs>({ ...prefs });
  const [webPushLoading, setWebPushLoading] = useState(false);
  const [webPushStatus, setWebPushStatus] = useState<string | null>(null);

  const toggle = (key: keyof NotificationPrefs) => {
    setLocal(p => ({ ...p, [key]: !p[key] }));
  };

  const handleWebPushToggle = async () => {
    setWebPushLoading(true);
    setWebPushStatus(null);
    try {
      if (local.webPushEnabled) {
        await unsubscribeWebPush(userId);
        setLocal(p => ({ ...p, webPushEnabled: false }));
        setWebPushStatus('Browser push notifications disabled.');
      } else {
        if (!('Notification' in window)) {
          setWebPushStatus('Browser notifications are not supported on this device.');
          setWebPushLoading(false);
          return;
        }
        const granted = await Notification.requestPermission();
        if (granted !== 'granted') {
          setWebPushStatus('Permission denied. Enable notifications in browser settings.');
          setWebPushLoading(false);
          return;
        }
        const ok = await subscribeWebPush(userId, familyId);
        if (ok) {
          setLocal(p => ({ ...p, webPushEnabled: true }));
          setWebPushStatus('Browser push notifications enabled!');
        } else {
          setWebPushStatus('Failed to enable. Ensure VAPID key is configured.');
        }
      }
    } finally {
      setWebPushLoading(false);
    }
  };

  const handleSave = () => {
    onSave(local);
    onClose();
  };

  const isNative = Capacitor.isNativePlatform();

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 backdrop-blur-sm p-4" onClick={onClose}>
      <div
        className="bg-white dark:bg-gray-900 rounded-2xl shadow-2xl w-full max-w-md max-h-[85vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100 dark:border-gray-800">
          <div className="flex items-center gap-2">
            <Bell className="w-5 h-5 text-indigo-500" />
            <h2 className="text-base font-semibold text-gray-900 dark:text-white">Notification Settings</h2>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-full hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-400">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="px-5 py-4 space-y-5">
          {/* Per-category toggles */}
          <div>
            <p className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
              Notify me about
            </p>
            <div className="space-y-1">
              {CATEGORIES.map(({ key, label, desc }) => (
                <label
                  key={key}
                  className="flex items-center justify-between py-2.5 px-3 rounded-xl cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                >
                  <div>
                    <p className="text-sm font-medium text-gray-800 dark:text-gray-200">{label}</p>
                    <p className="text-xs text-gray-400">{desc}</p>
                  </div>
                  <button
                    role="switch"
                    aria-checked={local[key] as boolean}
                    onClick={() => toggle(key)}
                    className={`relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent transition-colors
                      ${local[key] ? 'bg-indigo-500' : 'bg-gray-200 dark:bg-gray-700'}`}
                  >
                    <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform
                      ${local[key] ? 'translate-x-5' : 'translate-x-0'}`} />
                  </button>
                </label>
              ))}
            </div>
          </div>

          {/* Delivery channel */}
          <div className="border-t border-gray-100 dark:border-gray-800 pt-4">
            <p className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
              Delivery
            </p>

            {isNative ? (
              <div className="flex items-center gap-3 px-3 py-2.5 bg-gray-50 dark:bg-gray-800 rounded-xl">
                <Smartphone className="w-4 h-4 text-indigo-500 shrink-0" />
                <div>
                  <p className="text-sm font-medium text-gray-800 dark:text-gray-200">Native Push (FCM/APNs)</p>
                  <p className="text-xs text-gray-400">Managed by the app — always active when installed</p>
                </div>
                <span className="ml-auto text-xs font-medium text-green-600 bg-green-50 dark:bg-green-900/30 px-2 py-0.5 rounded-full">Active</span>
              </div>
            ) : (
              <div className="px-3 py-3 bg-gray-50 dark:bg-gray-800 rounded-xl space-y-2">
                <div className="flex items-center gap-3">
                  <Globe className="w-4 h-4 text-indigo-500 shrink-0" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-gray-800 dark:text-gray-200">Browser Push (PWA)</p>
                    <p className="text-xs text-gray-400">Receive notifications even when the tab is closed</p>
                  </div>
                  <button
                    onClick={handleWebPushToggle}
                    disabled={webPushLoading}
                    className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors
                      ${local.webPushEnabled
                        ? 'bg-red-50 dark:bg-red-900/20 text-red-600 hover:bg-red-100'
                        : 'bg-indigo-500 text-white hover:bg-indigo-600'
                      } disabled:opacity-50`}
                  >
                    {webPushLoading
                      ? <span className="animate-spin w-3 h-3 border border-current border-t-transparent rounded-full" />
                      : local.webPushEnabled ? <BellOff className="w-3 h-3" /> : <Bell className="w-3 h-3" />
                    }
                    {local.webPushEnabled ? 'Disable' : 'Enable'}
                  </button>
                </div>
                {webPushStatus && (
                  <p className={`text-xs px-1 ${webPushStatus.includes('!') ? 'text-green-600' : 'text-amber-600'}`}>
                    {webPushStatus}
                  </p>
                )}
                {!local.webPushEnabled && (
                  <p className="text-[11px] text-gray-400 px-1">
                    Requires VAPID keys to be configured. In-app toasts always work.
                  </p>
                )}
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="flex gap-2 px-5 py-4 border-t border-gray-100 dark:border-gray-800">
          <button
            onClick={() => setLocal({ ...DEFAULT_NOTIFICATION_PREFS })}
            className="text-xs text-gray-500 hover:text-gray-700 px-3 py-2"
          >
            Reset defaults
          </button>
          <div className="flex-1" />
          <button onClick={onClose} className="px-4 py-2 text-sm text-gray-500 hover:text-gray-700">
            Cancel
          </button>
          <button
            onClick={handleSave}
            className="px-4 py-2 text-sm font-medium bg-indigo-500 text-white rounded-lg hover:bg-indigo-600"
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
};

export default NotificationSettings;
