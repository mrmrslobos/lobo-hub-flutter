
import React, { useState, useEffect } from 'react';
import {
  LayoutDashboard,
  CheckSquare,
  Calendar,
  Utensils,
  ListTodo,
  BookOpen,
  Activity,
  Wallet,
  Settings,
  Menu,
  X,
  Sparkles,
  ChevronDown,
  User,
  LogOut,
  History,
  Copy,
  Check,
  Cloud,
  CloudOff,
  ClipboardList,
  Vote,
  ShieldCheck,
  Gift,
  Layers,
  Globe,
  HandHeart,
  Bell,
  BellOff,
  FlowerIcon,
  MessageSquare,
  Heart,
  Star,
  Camera,
  Navigation,
  Fingerprint,
  KeyRound,
} from 'lucide-react';
import { enableBiometricLock, disableLock, isLockEnabled } from './BiometricLock';
import { Link, useLocation } from 'react-router-dom';
import { isSupabaseConfigured } from '../services/supabase';
import { DB } from '../services/db';
import { APP_CONFIG } from '../appConfig';
import { COUNTRIES, getCountryDefaults } from '../services/locale';
import NotificationSettings from './NotificationSettings';
import SubscriptionModal from './SubscriptionModal';
import { NotificationPrefs } from '../types';

interface LayoutProps {
  children: React.ReactNode;
  user: any;
  family: any;
  onLogout: () => void;
  families: any[];
  onFamilySwitch: (id: string) => void;
  db: DB;
  onSaveDb: (newDb: DB, broadcast?: boolean) => void;
  unreadModules?: Set<string>;
  onClearUnread?: (path: string) => void;
}

const Layout: React.FC<LayoutProps> = ({ children, user, family, onLogout, families, onFamilySwitch, db, onSaveDb, unreadModules, onClearUnread }) => {
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [isProfileMenuOpen, setIsProfileMenuOpen] = useState(false);
  const [isFamilyMenuOpen, setIsFamilyMenuOpen] = useState(false);
  const [hasCopied, setHasCopied] = useState(false);
  const [isMembersModalOpen, setIsMembersModalOpen] = useState(false);
  const [editingMemberId, setEditingMemberId] = useState<string | null>(null);
  const [draftAccess, setDraftAccess] = useState<string[]>([]);
  const [isModulesModalOpen, setIsModulesModalOpen] = useState(false);
  const [draftModules, setDraftModules] = useState<string[]>([]);
  const [isRegionModalOpen, setIsRegionModalOpen] = useState(false);
  const [isDigestModalOpen, setIsDigestModalOpen] = useState(false);
  const [isNotifSettingsOpen, setIsNotifSettingsOpen] = useState(false);
  const [isSubscriptionOpen, setIsSubscriptionOpen] = useState(false);
  const [draftDigestEnabled, setDraftDigestEnabled] = useState(true);
  const [draftDigestDay, setDraftDigestDay] = useState(0);   // local day 0=Sun
  const [draftDigestHour, setDraftDigestHour] = useState(8); // local hour
  const [lockEnabled, setLockEnabled] = useState(isLockEnabled);
  const [pinModalInfo, setPinModalInfo] = useState<{ pin: string; biometricUnavailable?: boolean } | null>(null);
  const location = useLocation();
  const isCloudEnabled = isSupabaseConfigured();

  // Clear the unread badge when the user navigates to a module
  useEffect(() => {
    onClearUnread?.(location.pathname);
  }, [location.pathname, onClearUnread]);

  // Grouped nav — drives sidebar rendering and module settings modal
  const navGroups = [
    {
      label: 'Family',
      items: [
        { name: 'Chat',     icon: MessageSquare, path: '/chat' },
        { name: 'Tasks',    icon: CheckSquare,   path: '/tasks' },
        { name: 'Calendar', icon: Calendar,      path: '/calendar' },
        { name: 'Chores',    icon: ClipboardList, path: '/chores' },
        { name: 'Lists',     icon: ListTodo,      path: '/lists' },
        { name: 'Polls',     icon: Vote,          path: '/polls' },
        { name: 'Occasions', icon: Star,           path: '/birthdays' },
        { name: 'Photos',    icon: Camera,        path: '/photos' },
        { name: 'Location',  icon: Navigation,    path: '/location' },
        { name: 'Health',    icon: Heart,         path: '/health' },
      ],
    },
    {
      label: 'Lifestyle',
      items: [
        { name: 'Meals',      icon: Utensils, path: '/meals' },
        { name: 'Fitness',    icon: Activity, path: '/fitness' },
        { name: 'Devotional', icon: BookOpen, path: '/devotional' },
        { name: 'Prayer Wall', icon: HandHeart, path: '/prayer-wall' },
        { name: 'Period Tracker', icon: FlowerIcon, path: '/period-tracker' },
      ],
    },
    {
      label: 'Money',
      items: [
        { name: 'Budget',  icon: Wallet, path: '/budget' },
        { name: 'Rewards', icon: Gift,   path: '/rewards' },
      ],
    },
  ];

  const dashboardItem = { name: 'Dashboard', icon: LayoutDashboard, path: '/' };
  const aiHistoryItem = { name: 'AI History', icon: History, path: '/ai/history' };

  // Flat list kept for Manage Access modal compatibility
  const allNavItems = [
    dashboardItem,
    ...navGroups.flatMap(g => g.items),
    aiHistoryItem,
  ];

  // Access control helpers
  const userMembership = (db.familyMembers || []).find((m: any) => m.userId === user.id && m.familyId === family.id);
  const userRole: string = userMembership?.role || 'MEMBER';
  const canManageMembers = userRole === 'OWNER' || userRole === 'ADMIN';

  const handleToggleLock = async () => {
    if (lockEnabled) {
      disableLock();
      setLockEnabled(false);
      setIsProfileMenuOpen(false);
    } else {
      setIsProfileMenuOpen(false);
      try {
        const result = await enableBiometricLock(user.id, user.name);
        setLockEnabled(true);
        if (result.method === 'pin' && result.pin) {
          setPinModalInfo({ pin: result.pin, biometricUnavailable: result.biometricUnavailable });
        }
      } catch {
        // User cancelled or device unsupported — lock stays off
      }
    }
  };

  // Paths enabled at the family level (owner setting); undefined = all enabled
  const familyEnabledModules: string[] | undefined = family?.enabledModules;

  const isItemVisible = (path: string): boolean => {
    // Dashboard always visible
    if (path === '/') return true;
    // AI History always visible (it's a utility, not a toggled module)
    if (path === '/ai/history') return true;
    // Family-level toggle: [] means "all enabled" (same as undefined); only
    // restrict when the list is non-empty and the path isn't in it.
    if (familyEnabledModules && familyEnabledModules.length > 0 && !familyEnabledModules.includes(path)) return false;
    // User-level kid restriction
    const access = userMembership?.moduleAccess as string[] | undefined;
    if (access && access.length > 0 && !access.includes(path)) return false;
    return true;
  };

  const familyMembersList = (db.familyMembers || [])
    .filter((m: any) => m.familyId === family.id)
    .map((m: any) => ({
      member: m,
      memberUser: ((db.users || []).find((u: any) => u.id === m.userId) as any) || { id: m.userId, name: 'Unknown', email: '', avatar: '' },
    }))
    .sort((a: any, b: any) => {
      const order: Record<string, number> = { OWNER: 0, ADMIN: 1, MEMBER: 2 };
      return (order[a.member.role] || 2) - (order[b.member.role] || 2);
    });

  const closeMembersModal = () => {
    setIsMembersModalOpen(false);
    setEditingMemberId(null);
  };

  const saveMemberAccess = () => {
    const allPaths = allNavItems.map(n => n.path);
    const isFullAccess = allPaths.every(p => draftAccess.includes(p));
    const updatedMembers = (db.familyMembers || []).map((m: any) =>
      m.userId === editingMemberId && m.familyId === family.id
        ? { ...m, moduleAccess: isFullAccess ? undefined : draftAccess }
        : m
    );
    onSaveDb({ ...db, familyMembers: updatedMembers }, true);
    setEditingMemberId(null);
  };

  const saveMemberRole = (targetUserId: string, newRole: 'ADMIN' | 'MEMBER') => {
    const updatedMembers = (db.familyMembers || []).map((m: any) =>
      m.userId === targetUserId && m.familyId === family.id
        ? { ...m, role: newRole }
        : m
    );
    onSaveDb({ ...db, familyMembers: updatedMembers }, true);
  };

  const copyJoinCode = () => {
    if (family?.joinCode) {
      navigator.clipboard.writeText(family.joinCode).then(() => {
        setHasCopied(true);
        setTimeout(() => setHasCopied(false), 2000);
      }).catch(() => {
        // Fallback for non-HTTPS or restricted contexts (e.g. Capacitor WebView)
        try {
          const ta = document.createElement('textarea');
          ta.value = family.joinCode;
          ta.style.position = 'fixed';
          ta.style.opacity = '0';
          document.body.appendChild(ta);
          ta.select();
          document.execCommand('copy');
          document.body.removeChild(ta);
          setHasCopied(true);
          setTimeout(() => setHasCopied(false), 2000);
        } catch {
          alert(`Join code: ${family.joinCode}`);
        }
      });
    }
  };

  const openModulesModal = () => {
    const toggleablePaths = navGroups.flatMap(g => g.items.map(i => i.path));
    setDraftModules(familyEnabledModules ?? toggleablePaths);
    setIsModulesModalOpen(true);
    setIsProfileMenuOpen(false);
  };

  const saveEnabledModules = () => {
    const toggleablePaths = navGroups.flatMap(g => g.items.map(i => i.path));
    const allEnabled = toggleablePaths.every(p => draftModules.includes(p));
    const updatedFamilies = (db.families || []).map((f: any) =>
      f.id === family.id
        ? { ...f, enabledModules: allEnabled ? undefined : draftModules }
        : f
    );
    onSaveDb({ ...db, families: updatedFamilies });
    setIsModulesModalOpen(false);
  };

  // Convert a local day-of-week + hour to UTC equivalents using the
  // device's current timezone offset (works for any fixed-offset zone).
  const localToUtcDayHour = (localDay: number, localHour: number) => {
    const d = new Date();
    d.setDate(d.getDate() - d.getDay() + localDay);
    d.setHours(localHour, 0, 0, 0);
    return { day: d.getUTCDay(), hour: d.getUTCHours() };
  };

  const utcToLocalDayHour = (utcDay: number, utcHour: number) => {
    const d = new Date();
    d.setUTCDate(d.getUTCDate() - d.getUTCDay() + utcDay);
    d.setUTCHours(utcHour, 0, 0, 0);
    return { day: d.getDay(), hour: d.getHours() };
  };

  const openDigestModal = () => {
    const enabled = (family as any).weeklyDigest !== false;
    const { day: localDay, hour: localHour } = utcToLocalDayHour(
      (family as any).weeklyDigestDay ?? 0,
      (family as any).weeklyDigestHour ?? 8,
    );
    setDraftDigestEnabled(enabled);
    setDraftDigestDay(localDay);
    setDraftDigestHour(localHour);
    setIsDigestModalOpen(true);
    setIsProfileMenuOpen(false);
  };

  const saveDigestSettings = () => {
    const { day: utcDay, hour: utcHour } = localToUtcDayHour(draftDigestDay, draftDigestHour);
    const updatedFamilies = (db.families || []).map((f: any) =>
      f.id === family.id
        ? { ...f, weeklyDigest: draftDigestEnabled, weeklyDigestDay: utcDay, weeklyDigestHour: utcHour }
        : f
    );
    onSaveDb({ ...db, families: updatedFamilies });
    setIsDigestModalOpen(false);
  };

  const saveRegionSettings = (countryCode: string) => {
    const settings = getCountryDefaults(countryCode);
    const updatedFamilies = (db.families || []).map((f: any) =>
      f.id === family.id ? { ...f, settings } : f
    );
    onSaveDb({ ...db, families: updatedFamilies });
    setIsRegionModalOpen(false);
  };

  return (
    <div className="min-h-screen flex bg-[#fcfcf9]">
      {/* Sidebar */}
      {/* Backdrop — blocks background scroll/interaction on mobile */}
      {isSidebarOpen && (
        <div
          className="fixed inset-0 z-40 bg-stone-900/50 lg:hidden"
          onClick={() => setIsSidebarOpen(false)}
        />
      )}

      <aside className={`fixed inset-y-0 left-0 z-50 w-64 bg-white border-r border-stone-200 transform transition-transform duration-300 lg:relative lg:translate-x-0 ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full'}`}>
        <div className="flex flex-col h-full overflow-hidden">
          <div className="flex-1 overflow-y-auto p-6" style={{ paddingTop: 'calc(env(safe-area-inset-top) + 1.5rem)' }}>
            <div className="flex items-center justify-between mb-8">
              <div className="flex items-center space-x-2 text-indigo-600">
                <div className="bg-indigo-600 p-2 rounded-xl text-white">
                  <Sparkles size={24} />
                </div>
                <span className="text-2xl font-bold brand-font tracking-tight text-stone-800">{APP_CONFIG.appName}</span>
              </div>
              <div className="flex-shrink-0">
                {isCloudEnabled ? (
                  <Cloud size={16} className="text-emerald-500" />
                ) : (
                  <CloudOff size={16} className="text-stone-300" />
                )}
              </div>
            </div>

            {/* Family Switcher */}
            <div className="relative mb-6">
              <button 
                onClick={() => setIsFamilyMenuOpen(!isFamilyMenuOpen)}
                className="w-full flex items-center justify-between p-3 bg-stone-50 rounded-xl border border-stone-200 hover:bg-stone-100 transition-colors"
              >
                <div className="flex items-center space-x-3">
                  <div className="w-8 h-8 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-bold text-sm">
                    {family?.name?.[0] || 'L'}
                  </div>
                  <span className="font-medium text-stone-700 truncate">{family?.name || 'My Home'}</span>
                </div>
                <ChevronDown size={16} className={`text-stone-400 transform transition-transform ${isFamilyMenuOpen ? 'rotate-180' : ''}`} />
              </button>
              
              {isFamilyMenuOpen && (
                <div className="absolute top-full left-0 right-0 mt-2 bg-white border border-stone-200 rounded-xl shadow-xl z-50 overflow-hidden">
                  {families.length > 0 ? families.map(f => (
                    <button
                      key={f.id}
                      onClick={() => { onFamilySwitch(f.id); setIsFamilyMenuOpen(false); }}
                      className="w-full text-left p-3 hover:bg-stone-50 text-stone-700 transition-colors"
                    >
                      {f.name}
                    </button>
                  )) : (
                    <div className="p-3 text-sm text-stone-400">No other homes</div>
                  )}
                  <div className="border-t border-stone-100 p-2">
                    <button
                      onClick={() => alert('Creating multiple homes is coming in a future update!')}
                      className="w-full text-left p-2 text-sm text-indigo-600 font-medium hover:bg-indigo-50 rounded-lg"
                    >
                      + Create Home
                    </button>
                  </div>
                </div>
              )}

              {/* Join Code Display */}
              {family?.joinCode && (
                <div className="mt-2 flex items-center justify-between px-3 py-2 bg-indigo-50/50 rounded-lg border border-indigo-100/50">
                  <div className="flex flex-col">
                    <span className="text-[10px] font-black text-indigo-400 uppercase tracking-widest">Join Code</span>
                    <span className="text-xs font-bold text-indigo-700 tracking-wider uppercase">{family.joinCode}</span>
                  </div>
                  <button 
                    onClick={copyJoinCode}
                    className="p-1.5 text-indigo-400 hover:text-indigo-600 hover:bg-indigo-100 rounded-md transition-all"
                    title="Copy Join Code"
                  >
                    {hasCopied ? <Check size={14} /> : <Copy size={14} />}
                  </button>
                </div>
              )}
            </div>

            <nav className="space-y-0.5">
              {/* Dashboard — always first, no group label */}
              {isItemVisible('/') && (() => {
                const isActive = location.pathname === '/';
                return (
                  <Link
                    to="/"
                    onClick={() => setIsSidebarOpen(false)}
                    className={`flex items-center space-x-3 p-3 rounded-xl transition-all duration-200 ${
                      isActive ? 'bg-indigo-50 text-indigo-700 font-semibold' : 'text-stone-500 hover:bg-stone-50 hover:text-stone-800'
                    }`}
                  >
                    <LayoutDashboard size={20} />
                    <span>Dashboard</span>
                  </Link>
                );
              })()}

              {/* Module groups */}
              {navGroups.map(group => {
                const visibleItems = group.items.filter(item => isItemVisible(item.path));
                if (visibleItems.length === 0) return null;
                return (
                  <div key={group.label} className="pt-3">
                    <p className="text-[10px] font-black text-stone-400 uppercase tracking-widest px-3 mb-1">{group.label}</p>
                    {visibleItems.map(item => {
                      const isActive = location.pathname === item.path;
                      const hasUnread = !isActive && unreadModules?.has(item.path);
                      return (
                        <Link
                          key={item.path}
                          to={item.path}
                          onClick={() => { setIsSidebarOpen(false); onClearUnread?.(item.path); }}
                          className={`flex items-center space-x-3 p-3 rounded-xl transition-all duration-200 ${
                            isActive ? 'bg-indigo-50 text-indigo-700 font-semibold' : 'text-stone-500 hover:bg-stone-50 hover:text-stone-800'
                          }`}
                        >
                          <item.icon size={20} />
                          <span className="flex-1">{item.name}</span>
                          {hasUnread && (
                            <span className="w-2 h-2 rounded-full bg-indigo-500 shrink-0" />
                          )}
                        </Link>
                      );
                    })}
                  </div>
                );
              })}

              {/* AI History — always at bottom */}
              {isItemVisible('/ai/history') && (() => {
                const isActive = location.pathname === '/ai/history';
                return (
                  <div className="pt-3 border-t border-stone-100 mt-3">
                    <Link
                      to="/ai/history"
                      onClick={() => setIsSidebarOpen(false)}
                      className={`flex items-center space-x-3 p-3 rounded-xl transition-all duration-200 ${
                        isActive ? 'bg-indigo-50 text-indigo-700 font-semibold' : 'text-stone-400 hover:bg-stone-50 hover:text-stone-700'
                      }`}
                    >
                      <History size={18} />
                      <span className="text-sm">AI History</span>
                    </Link>
                  </div>
                );
              })()}
            </nav>
          </div>

          <div className="shrink-0 p-4 border-t border-stone-100">
            <div className="relative">
              <button 
                onClick={() => setIsProfileMenuOpen(!isProfileMenuOpen)}
                className="flex items-center space-x-3 w-full p-2 rounded-xl hover:bg-stone-50 transition-colors"
              >
                <img src={user?.avatar || 'https://picsum.photos/seed/user/100'} className="w-10 h-10 rounded-full border-2 border-white shadow-sm" alt="" />
                <div className="flex-1 text-left overflow-hidden">
                  <p className="text-sm font-semibold text-stone-800 truncate">{user?.name || APP_CONFIG.defaultUserName}</p>
                  <p className="text-xs text-stone-500 truncate">{user?.email || ''}</p>
                </div>
                <Settings size={18} className="text-stone-400" />
              </button>
              
              {isProfileMenuOpen && (
                <div className="absolute bottom-full left-0 right-0 mb-2 bg-white border border-stone-200 rounded-xl shadow-xl z-50 p-2">
                  {canManageMembers && (
                    <>
                      <button
                        onClick={openModulesModal}
                        className="flex items-center space-x-3 w-full p-2 text-stone-600 hover:bg-stone-50 rounded-lg transition-colors"
                      >
                        <Layers size={16} className="text-indigo-500" />
                        <span className="text-sm">Modules</span>
                      </button>
                      <button
                        onClick={() => { setIsRegionModalOpen(true); setIsProfileMenuOpen(false); }}
                        className="flex items-center space-x-3 w-full p-2 text-stone-600 hover:bg-stone-50 rounded-lg transition-colors"
                      >
                        <Globe size={16} className="text-indigo-500" />
                        <span className="text-sm">Region & Units</span>
                      </button>
                      <button
                        onClick={openDigestModal}
                        className="flex items-center space-x-3 w-full p-2 text-stone-600 hover:bg-stone-50 rounded-lg transition-colors"
                      >
                        {(family as any).weeklyDigest === false
                          ? <BellOff size={16} className="text-stone-400" />
                          : <Bell size={16} className="text-indigo-500" />
                        }
                        <span className="text-sm flex-1">Weekly Digest</span>
                        <span className={`text-[10px] font-black uppercase tracking-widest px-2 py-0.5 rounded-full ${
                          (family as any).weeklyDigest === false
                            ? 'bg-stone-100 text-stone-400'
                            : 'bg-indigo-100 text-indigo-600'
                        }`}>
                          {(family as any).weeklyDigest === false ? 'Off' : 'On'}
                        </span>
                      </button>
                      <button
                        onClick={() => { setIsMembersModalOpen(true); setIsProfileMenuOpen(false); }}
                        className="flex items-center space-x-3 w-full p-2 text-stone-600 hover:bg-stone-50 rounded-lg transition-colors"
                      >
                        <ShieldCheck size={16} className="text-indigo-500" />
                        <span className="text-sm">Manage Access</span>
                      </button>
                    </>
                  )}
                  <button
                    onClick={() => { setIsSubscriptionOpen(true); setIsProfileMenuOpen(false); }}
                    className="flex items-center space-x-3 w-full p-2 text-stone-600 hover:bg-stone-50 rounded-lg transition-colors"
                  >
                    <Sparkles size={16} className="text-indigo-500" />
                    <span className="text-sm flex-1">Subscription</span>
                  </button>
                  <button
                    onClick={() => { setIsNotifSettingsOpen(true); setIsProfileMenuOpen(false); }}
                    className="flex items-center space-x-3 w-full p-2 text-stone-600 hover:bg-stone-50 rounded-lg transition-colors"
                  >
                    <Bell size={16} className="text-indigo-500" />
                    <span className="text-sm">Notifications</span>
                  </button>
                  <button
                    onClick={handleToggleLock}
                    className="flex items-center space-x-3 w-full p-2 text-stone-600 hover:bg-stone-50 rounded-lg transition-colors"
                  >
                    <Fingerprint size={16} className={lockEnabled ? 'text-indigo-500' : 'text-stone-400'} />
                    <span className="text-sm flex-1">App Lock</span>
                    <span className={`text-[10px] font-black uppercase tracking-widest px-2 py-0.5 rounded-full ${
                      lockEnabled ? 'bg-indigo-100 text-indigo-600' : 'bg-stone-100 text-stone-400'
                    }`}>
                      {lockEnabled ? 'On' : 'Off'}
                    </span>
                  </button>
                  <button
                    onClick={onLogout}
                    className="flex items-center space-x-3 w-full p-2 text-red-600 hover:bg-red-50 rounded-lg transition-colors mt-1"
                  >
                    <LogOut size={16} />
                    <span className="text-sm">Sign Out</span>
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      </aside>

      {/* Manage Access Modal */}
      {isMembersModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-lg rounded-3xl shadow-2xl overflow-hidden max-h-[85vh] flex flex-col">
            {/* Header */}
            <div className="p-6 border-b border-stone-100 flex items-center justify-between shrink-0">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-indigo-100 rounded-xl">
                  <ShieldCheck size={20} className="text-indigo-600" />
                </div>
                <div>
                  <h2 className="text-xl font-bold text-stone-800">Manage Member Access</h2>
                  <p className="text-xs text-stone-500">Control which modules each member can see.</p>
                </div>
              </div>
              <button onClick={closeMembersModal} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100">
                <X size={20} />
              </button>
            </div>

            {/* Member list */}
            <div className="flex-1 overflow-y-auto p-4 space-y-3">
              {familyMembersList.map(({ member, memberUser }: any) => {
                const isEditing = editingMemberId === member.userId;
                const isOwner = member.role === 'OWNER';
                const isSelf = member.userId === user.id;
                const canEdit = !isOwner && !isSelf;
                const currentAccess: string[] | undefined = member.moduleAccess;
                const accessSummary = !currentAccess
                  ? 'Full access'
                  : allNavItems.filter(n => currentAccess.includes(n.path)).map(n => n.name).join(', ') || 'No access';

                return (
                  <div key={member.userId} className={`border rounded-2xl overflow-hidden transition-all ${isEditing ? 'border-indigo-200 bg-indigo-50/30' : 'border-stone-200 bg-white'}`}>
                    {/* Member row */}
                    <div className="p-4 flex items-center gap-3">
                      <img
                        src={memberUser.avatar || `https://picsum.photos/seed/${memberUser.name}/100`}
                        className="w-10 h-10 rounded-full border-2 border-white shadow-sm shrink-0"
                        alt=""
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-bold text-stone-800 text-sm">{memberUser.name}</p>
                          <span className={`text-[10px] font-black uppercase tracking-widest px-2 py-0.5 rounded-full ${
                            member.role === 'OWNER' ? 'bg-amber-100 text-amber-700' :
                            member.role === 'ADMIN' ? 'bg-indigo-100 text-indigo-700' :
                            'bg-stone-100 text-stone-500'
                          }`}>{member.role}</span>
                          {isSelf && <span className="text-[10px] text-stone-400 font-semibold">(you)</span>}
                        </div>
                        <p className="text-xs text-stone-400 truncate">{accessSummary}</p>
                      </div>
                      {canEdit && (
                        <button
                          onClick={() => {
                            if (isEditing) {
                              setEditingMemberId(null);
                            } else {
                              setEditingMemberId(member.userId);
                              setDraftAccess(member.moduleAccess ? [...member.moduleAccess] : allNavItems.map(n => n.path));
                            }
                          }}
                          className={`text-xs font-bold px-3 py-1.5 rounded-lg transition-colors shrink-0 ${
                            isEditing ? 'bg-stone-200 text-stone-600 hover:bg-stone-300' : 'bg-indigo-100 text-indigo-700 hover:bg-indigo-200'
                          }`}
                        >
                          {isEditing ? 'Cancel' : 'Edit'}
                        </button>
                      )}
                    </div>

                    {/* Edit panel */}
                    {isEditing && (
                      <div className="border-t border-indigo-100 p-4 space-y-4">
                        {/* Presets */}
                        <div className="flex gap-2">
                          <button
                            onClick={() => setDraftAccess(['/', '/calendar', '/meals', '/chores', '/rewards'])}
                            className="px-3 py-1.5 bg-amber-100 text-amber-700 rounded-lg text-xs font-bold hover:bg-amber-200 transition-colors"
                          >
                            Kids Preset
                          </button>
                          <button
                            onClick={() => setDraftAccess(allNavItems.map(n => n.path))}
                            className="px-3 py-1.5 bg-emerald-100 text-emerald-700 rounded-lg text-xs font-bold hover:bg-emerald-200 transition-colors"
                          >
                            Full Access
                          </button>
                        </div>

                        {/* Module toggles */}
                        <div className="grid grid-cols-2 gap-2">
                          {allNavItems.map(navItem => {
                            const checked = draftAccess.includes(navItem.path);
                            return (
                              <button
                                key={navItem.path}
                                onClick={() => setDraftAccess(prev =>
                                  checked ? prev.filter(p => p !== navItem.path) : [...prev, navItem.path]
                                )}
                                className={`flex items-center gap-2 p-2.5 rounded-xl text-sm font-medium transition-all text-left ${
                                  checked ? 'bg-indigo-600 text-white shadow-sm' : 'bg-stone-100 text-stone-500 hover:bg-stone-200'
                                }`}
                              >
                                <navItem.icon size={15} className="shrink-0" />
                                <span className="truncate">{navItem.name}</span>
                              </button>
                            );
                          })}
                        </div>

                        {/* Role management — OWNER only */}
                        {userRole === 'OWNER' && (
                          <div className="border-t border-indigo-100 pt-3">
                            <p className="text-xs font-bold text-stone-500 uppercase tracking-wider mb-2">Role</p>
                            <div className="flex gap-2">
                              <button
                                onClick={() => saveMemberRole(member.userId, 'ADMIN')}
                                disabled={member.role === 'ADMIN'}
                                className={`flex-1 py-2 rounded-xl text-xs font-bold transition-colors ${
                                  member.role === 'ADMIN'
                                    ? 'bg-indigo-600 text-white cursor-default'
                                    : 'bg-indigo-100 text-indigo-700 hover:bg-indigo-200'
                                }`}
                              >
                                Admin
                              </button>
                              <button
                                onClick={() => saveMemberRole(member.userId, 'MEMBER')}
                                disabled={member.role === 'MEMBER'}
                                className={`flex-1 py-2 rounded-xl text-xs font-bold transition-colors ${
                                  member.role === 'MEMBER'
                                    ? 'bg-stone-600 text-white cursor-default'
                                    : 'bg-stone-100 text-stone-600 hover:bg-stone-200'
                                }`}
                              >
                                Member
                              </button>
                            </div>
                          </div>
                        )}

                        <button
                          onClick={saveMemberAccess}
                          className="w-full bg-indigo-600 text-white py-2.5 rounded-xl font-bold text-sm hover:bg-indigo-700 transition-colors"
                        >
                          Save Access
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* Modules Settings Modal */}
      {isModulesModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl shadow-2xl overflow-hidden max-h-[85vh] flex flex-col">
            {/* Header */}
            <div className="p-6 border-b border-stone-100 flex items-center justify-between shrink-0">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-indigo-100 rounded-xl">
                  <Layers size={20} className="text-indigo-600" />
                </div>
                <div>
                  <h2 className="text-xl font-bold text-stone-800">Modules</h2>
                  <p className="text-xs text-stone-500">Choose what appears in the nav for everyone.</p>
                </div>
              </div>
              <button onClick={() => setIsModulesModalOpen(false)} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100">
                <X size={20} />
              </button>
            </div>

            {/* Module groups */}
            <div className="flex-1 overflow-y-auto p-5 space-y-5">
              {/* Quick presets */}
              <div className="flex gap-2">
                <button
                  onClick={() => {
                    const toggleable = navGroups.flatMap(g => g.items.map(i => i.path));
                    setDraftModules(['/tasks', '/calendar', '/chores', '/rewards', '/meals']);
                  }}
                  className="flex-1 py-2 bg-stone-100 text-stone-600 rounded-xl text-xs font-bold hover:bg-stone-200 transition-colors"
                >
                  ⚡ Essentials
                </button>
                <button
                  onClick={() => setDraftModules(navGroups.flatMap(g => g.items.map(i => i.path)))}
                  className="flex-1 py-2 bg-stone-100 text-stone-600 rounded-xl text-xs font-bold hover:bg-stone-200 transition-colors"
                >
                  ✨ Everything
                </button>
              </div>

              {navGroups.map(group => (
                <div key={group.label}>
                  <p className="text-[10px] font-black text-stone-400 uppercase tracking-widest mb-2">{group.label}</p>
                  <div className="grid grid-cols-2 gap-2">
                    {group.items.map(item => {
                      const enabled = draftModules.includes(item.path);
                      return (
                        <button
                          key={item.path}
                          onClick={() => setDraftModules(prev =>
                            enabled ? prev.filter(p => p !== item.path) : [...prev, item.path]
                          )}
                          className={`flex items-center gap-2.5 p-3 rounded-2xl text-left transition-all ${
                            enabled
                              ? 'bg-indigo-600 text-white shadow-sm shadow-indigo-100'
                              : 'bg-stone-100 text-stone-500 hover:bg-stone-200'
                          }`}
                        >
                          <item.icon size={17} className="shrink-0" />
                          <span className="font-semibold text-sm truncate">{item.name}</span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              ))}

              <p className="text-xs text-stone-400 text-center">
                Dashboard and AI History are always visible.
              </p>
            </div>

            {/* Footer */}
            <div className="p-4 border-t border-stone-100 shrink-0">
              <button
                onClick={saveEnabledModules}
                className="w-full bg-indigo-600 text-white py-3 rounded-2xl font-bold text-sm hover:bg-indigo-700 transition-colors shadow-sm shadow-indigo-100"
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Region & Units Modal */}
      {isRegionModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-md rounded-3xl shadow-2xl overflow-hidden max-h-[85vh] flex flex-col">
            <div className="p-6 border-b border-stone-100 flex items-center justify-between shrink-0">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-indigo-100 rounded-xl">
                  <Globe size={20} className="text-indigo-600" />
                </div>
                <div>
                  <h2 className="text-xl font-bold text-stone-800">Region & Units</h2>
                  <p className="text-xs text-stone-500">Set your country to auto-configure dates, units & currency.</p>
                </div>
              </div>
              <button onClick={() => setIsRegionModalOpen(false)} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100">
                <X size={20} />
              </button>
            </div>
            <div className="flex-1 overflow-y-auto p-4">
              <div className="grid grid-cols-1 gap-2">
                {COUNTRIES.map(c => {
                  const isCurrent = family?.settings?.country === c.code;
                  return (
                    <button
                      key={c.code}
                      onClick={() => saveRegionSettings(c.code)}
                      className={`flex items-center gap-3 p-3 rounded-2xl text-left transition-all ${
                        isCurrent
                          ? 'bg-indigo-600 text-white shadow-sm'
                          : 'bg-stone-50 hover:bg-stone-100 text-stone-700'
                      }`}
                    >
                      <span className="text-2xl shrink-0">{c.flag}</span>
                      <div className="min-w-0 flex-1">
                        <p className="font-bold text-sm">{c.name}</p>
                        <p className={`text-xs ${isCurrent ? 'text-indigo-200' : 'text-stone-400'}`}>
                          {c.units === 'imperial' ? 'Imperial' : 'Metric'} · {c.currencyCode} · {c.timeFormat}
                        </p>
                      </div>
                      {isCurrent && <Check size={16} className="text-white shrink-0" />}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Weekly Digest Modal */}
      {isDigestModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/60 backdrop-blur-sm">
          <div className="bg-white w-full max-w-sm rounded-3xl shadow-2xl overflow-hidden">
            {/* Header */}
            <div className="p-6 border-b border-stone-100 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-indigo-100 rounded-xl">
                  <Bell size={20} className="text-indigo-600" />
                </div>
                <div>
                  <h2 className="text-xl font-bold text-stone-800">Weekly Digest</h2>
                  <p className="text-xs text-stone-500">Weekly activity summary notification</p>
                </div>
              </div>
              <button onClick={() => setIsDigestModalOpen(false)} className="p-2 text-stone-400 hover:text-stone-600 rounded-xl hover:bg-stone-100">
                <X size={20} />
              </button>
            </div>

            {/* Body */}
            <div className="p-6 space-y-6">
              {/* Enable toggle */}
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-semibold text-stone-800 text-sm">Enable Weekly Digest</p>
                  <p className="text-xs text-stone-400">Send a summary to all members</p>
                </div>
                <button
                  onClick={() => setDraftDigestEnabled(!draftDigestEnabled)}
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${draftDigestEnabled ? 'bg-indigo-600' : 'bg-stone-300'}`}
                >
                  <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${draftDigestEnabled ? 'translate-x-6' : 'translate-x-1'}`} />
                </button>
              </div>

              {draftDigestEnabled && (
                <>
                  {/* Day picker */}
                  <div className="space-y-2">
                    <p className="text-xs font-bold text-stone-500 uppercase tracking-wider">Day</p>
                    <div className="grid grid-cols-7 gap-1">
                      {['S','M','T','W','T','F','S'].map((label, idx) => (
                        <button
                          key={idx}
                          onClick={() => setDraftDigestDay(idx)}
                          className={`py-2 rounded-xl text-xs font-bold transition-colors ${
                            draftDigestDay === idx
                              ? 'bg-indigo-600 text-white shadow-sm'
                              : 'bg-stone-100 text-stone-500 hover:bg-stone-200'
                          }`}
                        >
                          {label}
                        </button>
                      ))}
                    </div>
                    <p className="text-xs text-center text-stone-400">
                      {['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][draftDigestDay]}
                    </p>
                  </div>

                  {/* Time picker */}
                  <div className="space-y-2">
                    <p className="text-xs font-bold text-stone-500 uppercase tracking-wider">Time</p>
                    <select
                      value={draftDigestHour}
                      onChange={e => setDraftDigestHour(Number(e.target.value))}
                      className="w-full p-3 rounded-xl border border-stone-200 bg-stone-50 text-stone-800 text-sm focus:outline-none focus:border-indigo-400"
                    >
                      {Array.from({ length: 24 }, (_, h) => {
                        const label = h === 0 ? '12:00 AM' : h < 12 ? `${h}:00 AM` : h === 12 ? '12:00 PM' : `${h - 12}:00 PM`;
                        return <option key={h} value={h}>{label}</option>;
                      })}
                    </select>
                    <p className="text-xs text-stone-400">Your device's local timezone</p>
                  </div>
                </>
              )}
            </div>

            {/* Footer */}
            <div className="p-6 border-t border-stone-100">
              <button
                onClick={saveDigestSettings}
                className="w-full bg-indigo-600 text-white py-3 rounded-xl font-bold text-sm hover:bg-indigo-700 transition-colors"
              >
                Save Changes
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Main Content */}
      <main className="flex-1 min-w-0 flex flex-col">
        {/* Header */}
        <header className="sticky top-0 z-40 bg-white/80 backdrop-blur-md border-b border-stone-200 lg:hidden" style={{ paddingTop: 'env(safe-area-inset-top)' }}>
          <div className="flex items-center justify-between p-4">
            <div className="flex items-center space-x-2 text-indigo-600">
              <Sparkles size={24} />
              <span className="text-xl font-bold brand-font">{APP_CONFIG.appName}</span>
            </div>
            <button 
              onClick={() => setIsSidebarOpen(!isSidebarOpen)}
              className="p-2 text-stone-500"
            >
              {isSidebarOpen ? <X size={24} /> : <Menu size={24} />}
            </button>
          </div>
        </header>

        <div className="flex-1 p-4 lg:p-8 max-w-7xl mx-auto w-full custom-scrollbar overflow-y-auto">
          {children}
        </div>
      </main>

      {/* Notification Settings panel */}
      {isNotifSettingsOpen && (
        <NotificationSettings
          prefs={db.notificationPrefs}
          userId={user?.id ?? ''}
          familyId={family?.id ?? ''}
          onSave={(prefs: NotificationPrefs) => { onSaveDb({ ...db, notificationPrefs: prefs }); }}
          onClose={() => setIsNotifSettingsOpen(false)}
        />
      )}

      {isSubscriptionOpen && (
        <SubscriptionModal onClose={() => setIsSubscriptionOpen(false)} />
      )}

      {/* PIN reveal modal — shown when biometric isn't available and a PIN was generated */}
      {pinModalInfo && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/60 px-6">
          <div className="bg-white rounded-3xl p-6 w-full max-w-xs text-center space-y-4 shadow-2xl">
            <div className="w-12 h-12 bg-indigo-100 rounded-2xl flex items-center justify-center mx-auto">
              <KeyRound size={24} className="text-indigo-600" />
            </div>
            <div>
              <p className="font-bold text-stone-800 text-lg">Your App Lock PIN</p>
              <p className="text-stone-500 text-sm mt-1">
                {pinModalInfo?.biometricUnavailable
                  ? 'Your device has no biometrics enrolled. Write this PIN down — you\'ll need it to unlock the app.'
                  : 'Biometric registration was cancelled or failed. Use this PIN to unlock the app instead.'}
              </p>
            </div>
            <div className="bg-indigo-50 rounded-2xl py-4 px-6">
              <p className="text-4xl font-black tracking-[0.4em] text-indigo-700">{pinModalInfo.pin}</p>
            </div>
            <button
              onClick={() => setPinModalInfo(null)}
              className="w-full py-3 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 transition-colors"
            >
              I've saved my PIN
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default Layout;
