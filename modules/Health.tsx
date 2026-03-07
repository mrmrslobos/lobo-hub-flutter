
import React, { useState, useMemo, useEffect } from 'react';
import {
  Plus,
  X,
  Trash2,
  Edit3,
  Heart,
  AlertTriangle,
  Pill,
  Activity,
  Shield,
  Phone,
  User as UserIcon,
  ChevronDown,
  ChevronUp,
  Syringe,
  FileText,
} from 'lucide-react';
import {
  User,
  Family,
  HealthRecord,
  HealthAllergy,
  HealthMedication,
  HealthCondition,
  HealthImmunization,
  EmergencyContact,
  BloodType,
  AllergySeverity,
} from '../types';
import { useRealtimeDB } from '../hooks/useRealtimeDB';

const BLOOD_TYPES: BloodType[] = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'];
const SEVERITY_COLORS: Record<AllergySeverity, string> = {
  MILD: 'bg-yellow-100 text-yellow-800',
  MODERATE: 'bg-orange-100 text-orange-800',
  SEVERE: 'bg-red-100 text-red-800',
};

function uid() { return Math.random().toString(36).substr(2, 9); }
function stableRecordId(familyId: string, memberId: string) { return `health_${familyId}_${memberId}`; }

type Section = 'allergies' | 'medications' | 'conditions' | 'immunizations' | 'emergency' | 'info';

const Health: React.FC<{ user: User; family: Family }> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);

  const familyMembers = useMemo(() => {
    const memberIds = (db.familyMembers || [])
      .filter(m => m.familyId === family.id)
      .map(m => m.userId);
    return (db.users || []).filter(u => memberIds.includes(u.id));
  }, [db.familyMembers, db.users, family.id]);

  const userMembership = (db.familyMembers || []).find(m => m.userId === user.id && m.familyId === family.id);
  const isAdmin = userMembership?.role === 'ADMIN' || userMembership?.role === 'PARENT';

  // Which member's record we're viewing
  const [selectedMemberId, setSelectedMemberId] = useState<string>(user.id);
  const [expandedSections, setExpandedSections] = useState<Set<Section>>(new Set(['allergies', 'emergency']));
  const [editMode, setEditMode] = useState(false);

  const canEdit = isAdmin || selectedMemberId === user.id;

  // Reset form state when switching members to prevent cross-contamination
  useEffect(() => {
    setEditMode(false);
    setAllergyName(''); setAllergyReaction(''); setAllergySeverity('MILD');
    setMedName(''); setMedDose(''); setMedFreq(''); setMedStart('');
    setCondName(''); setCondDate(''); setCondNotes('');
    setImmuName(''); setImmuDate(''); setImmuNext('');
    setEcName(''); setEcPhone(''); setEcRelation('');
  }, [selectedMemberId]);

  const getRecord = (memberId: string): HealthRecord => {
    const existing = (db.healthRecords || []).find(r => r.familyId === family.id && r.memberId === memberId);
    if (existing) return existing;
    return {
      id: stableRecordId(family.id, memberId),
      familyId: family.id,
      memberId,
      updatedBy: user.id,
      bloodType: 'Unknown',
      allergies: [],
      medications: [],
      conditions: [],
      immunizations: [],
      emergencyContacts: [],
      updatedAt: new Date().toISOString(),
    };
  };

  const record = useMemo(() => getRecord(selectedMemberId), [db.healthRecords, selectedMemberId, family.id]);

  const saveRecord = (updated: HealthRecord) => {
    const all = (db.healthRecords || []).filter(r => !(r.familyId === family.id && r.memberId === selectedMemberId));
    const memberName = familyMembers.find(m => m.id === selectedMemberId)?.name ?? 'member';
    save({ ...db, healthRecords: [...all, { ...updated, updatedBy: user.id, updatedAt: new Date().toISOString() }] }, 'updated health record', 'Health', memberName);
  };

  const toggleSection = (s: Section) => {
    setExpandedSections(prev => {
      const next = new Set(prev);
      next.has(s) ? next.delete(s) : next.add(s);
      return next;
    });
  };

  // ---- Allergy editing ----
  const [allergyName, setAllergyName] = useState('');
  const [allergySeverity, setAllergySeverity] = useState<AllergySeverity>('MILD');
  const [allergyReaction, setAllergyReaction] = useState('');

  const addAllergy = () => {
    if (!allergyName.trim()) return;
    const newA: HealthAllergy = { id: uid(), name: allergyName.trim(), severity: allergySeverity, reaction: allergyReaction.trim() || undefined };
    saveRecord({ ...record, allergies: [...record.allergies, newA] });
    setAllergyName(''); setAllergyReaction(''); setAllergySeverity('MILD');
  };
  const removeAllergy = (id: string) => {
    if (!window.confirm('Remove this allergy? This cannot be undone.')) return;
    saveRecord({ ...record, allergies: record.allergies.filter(a => a.id !== id) });
  };

  // ---- Medication editing ----
  const [medName, setMedName] = useState('');
  const [medDose, setMedDose] = useState('');
  const [medFreq, setMedFreq] = useState('');
  const [medStart, setMedStart] = useState('');

  const addMed = () => {
    if (!medName.trim()) return;
    const newM: HealthMedication = { id: uid(), name: medName.trim(), dose: medDose.trim() || undefined, frequency: medFreq.trim() || undefined, startDate: medStart || undefined };
    saveRecord({ ...record, medications: [...record.medications, newM] });
    setMedName(''); setMedDose(''); setMedFreq(''); setMedStart('');
  };
  const removeMed = (id: string) => {
    if (!window.confirm('Remove this medication? This cannot be undone.')) return;
    saveRecord({ ...record, medications: record.medications.filter(m => m.id !== id) });
  };

  // ---- Condition editing ----
  const [condName, setCondName] = useState('');
  const [condDate, setCondDate] = useState('');
  const [condNotes, setCondNotes] = useState('');

  const addCondition = () => {
    if (!condName.trim()) return;
    const newC: HealthCondition = { id: uid(), name: condName.trim(), diagnosedDate: condDate || undefined, notes: condNotes.trim() || undefined };
    saveRecord({ ...record, conditions: [...record.conditions, newC] });
    setCondName(''); setCondDate(''); setCondNotes('');
  };
  const removeCond = (id: string) => {
    if (!window.confirm('Remove this condition? This cannot be undone.')) return;
    saveRecord({ ...record, conditions: record.conditions.filter(c => c.id !== id) });
  };

  // ---- Immunization editing ----
  const [immuName, setImmuName] = useState('');
  const [immuDate, setImmuDate] = useState('');
  const [immuNext, setImmuNext] = useState('');

  const addImmu = () => {
    if (!immuName.trim()) return;
    const newI: HealthImmunization = { id: uid(), name: immuName.trim(), date: immuDate || undefined, nextDue: immuNext || undefined };
    saveRecord({ ...record, immunizations: [...record.immunizations, newI] });
    setImmuName(''); setImmuDate(''); setImmuNext('');
  };
  const removeImmu = (id: string) => {
    if (!window.confirm('Remove this immunization record? This cannot be undone.')) return;
    saveRecord({ ...record, immunizations: record.immunizations.filter(i => i.id !== id) });
  };

  // ---- Emergency contact editing ----
  const [ecName, setEcName] = useState('');
  const [ecPhone, setEcPhone] = useState('');
  const [ecRelation, setEcRelation] = useState('');

  const addEC = () => {
    if (!ecName.trim() || !ecPhone.trim()) return;
    const newEC: EmergencyContact = { id: uid(), name: ecName.trim(), phone: ecPhone.trim(), relation: ecRelation.trim() };
    saveRecord({ ...record, emergencyContacts: [...record.emergencyContacts, newEC] });
    setEcName(''); setEcPhone(''); setEcRelation('');
  };
  const removeEC = (id: string) => {
    if (!window.confirm('Remove this emergency contact? This cannot be undone.')) return;
    saveRecord({ ...record, emergencyContacts: record.emergencyContacts.filter(e => e.id !== id) });
  };

  // ---- Blood type + misc info ----
  const updateBloodType = (bt: BloodType) => saveRecord({ ...record, bloodType: bt });

  // Local state for text fields that should only save to DB on blur (not on every keystroke)
  const [infoFields, setInfoFields] = useState({
    doctorName: record.doctorName || '',
    doctorPhone: record.doctorPhone || '',
    insuranceProvider: record.insuranceProvider || '',
    insurancePolicyNumber: record.insurancePolicyNumber || '',
    notes: record.notes || '',
  });

  // Sync local fields when the selected member or their record changes
  useEffect(() => {
    setInfoFields({
      doctorName: record.doctorName || '',
      doctorPhone: record.doctorPhone || '',
      insuranceProvider: record.insuranceProvider || '',
      insurancePolicyNumber: record.insurancePolicyNumber || '',
      notes: record.notes || '',
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedMemberId, record.id]);

  const flushInfoField = (field: keyof typeof infoFields) => {
    const value = infoFields[field].trim() || undefined;
    if (value !== (record as any)[field]) {
      saveRecord({ ...record, [field]: value });
    }
  };

  const selectedMember = familyMembers.find(m => m.id === selectedMemberId);

  const SectionHeader: React.FC<{ section: Section; label: string; icon: React.ReactNode; count?: number }> = ({ section, label, icon, count }) => (
    <button
      onClick={() => toggleSection(section)}
      className="w-full flex items-center justify-between p-4 bg-white rounded-xl border border-gray-200 hover:border-indigo-300 transition-colors"
    >
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 rounded-lg bg-indigo-50 flex items-center justify-center text-indigo-600">{icon}</div>
        <span className="font-semibold text-gray-800">{label}</span>
        {count !== undefined && count > 0 && (
          <span className="bg-indigo-100 text-indigo-700 text-xs font-medium px-2 py-0.5 rounded-full">{count}</span>
        )}
      </div>
      {expandedSections.has(section) ? <ChevronUp size={18} className="text-gray-400" /> : <ChevronDown size={18} className="text-gray-400" />}
    </button>
  );

  return (
    <div className="p-4 max-w-2xl mx-auto space-y-4 pb-24">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Heart className="text-rose-500" size={24} /> Health Records
          </h1>
          <p className="text-sm text-gray-500 mt-0.5">Allergies, medications & emergency info</p>
        </div>
      </div>

      {/* Member selector */}
      {familyMembers.length > 1 && (
        <div className="flex gap-3 overflow-x-auto pb-2 no-scrollbar">
          {familyMembers.map(m => {
            const isSelected = selectedMemberId === m.id;
            return (
              <button
                key={m.id}
                onClick={() => { setSelectedMemberId(m.id); setEditMode(false); }}
                className={`flex flex-col items-center gap-1.5 px-4 py-3 rounded-2xl border-2 min-w-[72px] transition-all ${
                  isSelected
                    ? 'bg-indigo-600 border-indigo-600 shadow-lg shadow-indigo-100'
                    : 'bg-white border-gray-200 hover:border-indigo-300'
                }`}
              >
                {m.avatar
                  ? <img src={m.avatar} className="w-10 h-10 rounded-full object-cover" alt="" />
                  : <div className={`w-10 h-10 rounded-full flex items-center justify-center text-base font-bold ${isSelected ? 'bg-indigo-500 text-white' : 'bg-indigo-100 text-indigo-700'}`}>{m.name[0]}</div>
                }
                <span className={`text-xs font-semibold truncate max-w-[60px] ${isSelected ? 'text-white' : 'text-gray-700'}`}>
                  {m.name.split(' ')[0]}
                </span>
              </button>
            );
          })}
        </div>
      )}

      {/* Blood type quick chip */}
      <div className="bg-white rounded-xl border border-gray-200 p-4">
        <div className="flex items-center justify-between mb-3">
          <span className="text-sm font-semibold text-gray-700 flex items-center gap-1.5">
            <Activity size={15} className="text-rose-500" /> Blood Type
          </span>
          {!canEdit && <span className="text-xs text-gray-400">View only</span>}
        </div>
        <div className="flex flex-wrap gap-2">
          {BLOOD_TYPES.map(bt => (
            <button
              key={bt}
              onClick={() => canEdit && updateBloodType(bt)}
              disabled={!canEdit}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium border transition-all ${
                record.bloodType === bt
                  ? 'bg-rose-500 text-white border-rose-500'
                  : 'bg-gray-50 text-gray-600 border-gray-200 hover:border-rose-300'
              } disabled:cursor-default`}
            >
              {bt}
            </button>
          ))}
        </div>
      </div>

      {/* Emergency Contacts */}
      <div className="space-y-2">
        <SectionHeader section="emergency" label="Emergency Contacts" icon={<Phone size={16} />} count={record.emergencyContacts.length} />
        {expandedSections.has('emergency') && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
            {record.emergencyContacts.length === 0 && (
              <p className="text-sm text-gray-400 text-center py-2">No emergency contacts added</p>
            )}
            {record.emergencyContacts.map(ec => (
              <div key={ec.id} className="flex items-start justify-between p-3 bg-rose-50 rounded-lg border border-rose-100">
                <div>
                  <div className="font-semibold text-gray-800 text-sm">{ec.name}</div>
                  <div className="text-xs text-gray-500">{ec.relation}</div>
                  <a href={`tel:${ec.phone}`} className="text-rose-600 text-sm font-medium mt-0.5 block hover:underline">{ec.phone}</a>
                </div>
                {canEdit && (
                  <button onClick={() => removeEC(ec.id)} className="text-gray-400 hover:text-red-500 p-1"><Trash2 size={14} /></button>
                )}
              </div>
            ))}
            {canEdit && (
              <div className="border-t pt-3 space-y-2">
                <div className="grid grid-cols-2 gap-2">
                  <input value={ecName} onChange={e => setEcName(e.target.value)} placeholder="Name *" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-rose-300" />
                  <input value={ecPhone} onChange={e => setEcPhone(e.target.value)} placeholder="Phone *" type="tel" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-rose-300" />
                </div>
                <div className="flex gap-2">
                  <input value={ecRelation} onChange={e => setEcRelation(e.target.value)} placeholder="Relationship (e.g. Mum, Doctor)" className="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-rose-300" />
                  <button onClick={addEC} className="bg-rose-500 text-white px-3 py-2 rounded-lg text-sm hover:bg-rose-600 flex items-center gap-1"><Plus size={14} /> Add</button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Allergies */}
      <div className="space-y-2">
        <SectionHeader section="allergies" label="Allergies" icon={<AlertTriangle size={16} />} count={record.allergies.length} />
        {expandedSections.has('allergies') && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
            {record.allergies.length === 0 && (
              <p className="text-sm text-gray-400 text-center py-2">No allergies recorded</p>
            )}
            {record.allergies.map(a => (
              <div key={a.id} className="flex items-start justify-between p-3 bg-amber-50 rounded-lg border border-amber-100">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-gray-800 text-sm">{a.name}</span>
                    <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${SEVERITY_COLORS[a.severity]}`}>{a.severity}</span>
                  </div>
                  {a.reaction && <div className="text-xs text-gray-500 mt-0.5">Reaction: {a.reaction}</div>}
                </div>
                {canEdit && (
                  <button onClick={() => removeAllergy(a.id)} className="text-gray-400 hover:text-red-500 p-1"><Trash2 size={14} /></button>
                )}
              </div>
            ))}
            {canEdit && (
              <div className="border-t pt-3 space-y-2">
                <div className="flex gap-2">
                  <input value={allergyName} onChange={e => setAllergyName(e.target.value)} placeholder="Allergy name *" className="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-300" />
                  <select value={allergySeverity} onChange={e => setAllergySeverity(e.target.value as AllergySeverity)} className="border border-gray-200 rounded-lg px-2 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-300">
                    <option value="MILD">Mild</option>
                    <option value="MODERATE">Moderate</option>
                    <option value="SEVERE">Severe</option>
                  </select>
                </div>
                <div className="flex gap-2">
                  <input value={allergyReaction} onChange={e => setAllergyReaction(e.target.value)} placeholder="Reaction description (optional)" className="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-300" />
                  <button onClick={addAllergy} className="bg-amber-500 text-white px-3 py-2 rounded-lg text-sm hover:bg-amber-600 flex items-center gap-1 whitespace-nowrap"><Plus size={14} /> Add</button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Medications */}
      <div className="space-y-2">
        <SectionHeader section="medications" label="Medications" icon={<Pill size={16} />} count={record.medications.length} />
        {expandedSections.has('medications') && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
            {record.medications.length === 0 && (
              <p className="text-sm text-gray-400 text-center py-2">No medications recorded</p>
            )}
            {record.medications.map(m => (
              <div key={m.id} className="flex items-start justify-between p-3 bg-blue-50 rounded-lg border border-blue-100">
                <div>
                  <div className="font-semibold text-gray-800 text-sm">{m.name}</div>
                  <div className="text-xs text-gray-500 space-x-2">
                    {m.dose && <span>Dose: {m.dose}</span>}
                    {m.frequency && <span>· {m.frequency}</span>}
                    {m.startDate && <span>· Since {m.startDate}</span>}
                  </div>
                </div>
                {canEdit && (
                  <button onClick={() => removeMed(m.id)} className="text-gray-400 hover:text-red-500 p-1"><Trash2 size={14} /></button>
                )}
              </div>
            ))}
            {canEdit && (
              <div className="border-t pt-3 space-y-2">
                <input value={medName} onChange={e => setMedName(e.target.value)} placeholder="Medication name *" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300" />
                <div className="grid grid-cols-3 gap-2">
                  <input value={medDose} onChange={e => setMedDose(e.target.value)} placeholder="Dose (e.g. 10mg)" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300" />
                  <input value={medFreq} onChange={e => setMedFreq(e.target.value)} placeholder="Frequency" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300" />
                  <input value={medStart} onChange={e => setMedStart(e.target.value)} type="date" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300" />
                </div>
                <div className="flex justify-end">
                  <button onClick={addMed} className="bg-blue-500 text-white px-4 py-2 rounded-lg text-sm hover:bg-blue-600 flex items-center gap-1"><Plus size={14} /> Add Medication</button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Medical Conditions */}
      <div className="space-y-2">
        <SectionHeader section="conditions" label="Medical Conditions" icon={<Activity size={16} />} count={record.conditions.length} />
        {expandedSections.has('conditions') && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
            {record.conditions.length === 0 && (
              <p className="text-sm text-gray-400 text-center py-2">No conditions recorded</p>
            )}
            {record.conditions.map(c => (
              <div key={c.id} className="flex items-start justify-between p-3 bg-purple-50 rounded-lg border border-purple-100">
                <div>
                  <div className="font-semibold text-gray-800 text-sm">{c.name}</div>
                  <div className="text-xs text-gray-500">
                    {c.diagnosedDate && <span>Diagnosed: {c.diagnosedDate}</span>}
                    {c.notes && <div className="mt-0.5 italic">{c.notes}</div>}
                  </div>
                </div>
                {canEdit && (
                  <button onClick={() => removeCond(c.id)} className="text-gray-400 hover:text-red-500 p-1"><Trash2 size={14} /></button>
                )}
              </div>
            ))}
            {canEdit && (
              <div className="border-t pt-3 space-y-2">
                <input value={condName} onChange={e => setCondName(e.target.value)} placeholder="Condition name *" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-purple-300" />
                <div className="grid grid-cols-2 gap-2">
                  <input value={condDate} onChange={e => setCondDate(e.target.value)} type="date" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-purple-300" />
                  <input value={condNotes} onChange={e => setCondNotes(e.target.value)} placeholder="Notes" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-purple-300" />
                </div>
                <div className="flex justify-end">
                  <button onClick={addCondition} className="bg-purple-500 text-white px-4 py-2 rounded-lg text-sm hover:bg-purple-600 flex items-center gap-1"><Plus size={14} /> Add Condition</button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Immunizations */}
      <div className="space-y-2">
        <SectionHeader section="immunizations" label="Immunizations" icon={<Syringe size={16} />} count={record.immunizations.length} />
        {expandedSections.has('immunizations') && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
            {record.immunizations.length === 0 && (
              <p className="text-sm text-gray-400 text-center py-2">No immunizations recorded</p>
            )}
            {record.immunizations.map(i => (
              <div key={i.id} className="flex items-start justify-between p-3 bg-green-50 rounded-lg border border-green-100">
                <div>
                  <div className="font-semibold text-gray-800 text-sm">{i.name}</div>
                  <div className="text-xs text-gray-500 space-x-2">
                    {i.date && <span>Given: {i.date}</span>}
                    {i.nextDue && <span>· Next due: {i.nextDue}</span>}
                  </div>
                </div>
                {canEdit && (
                  <button onClick={() => removeImmu(i.id)} className="text-gray-400 hover:text-red-500 p-1"><Trash2 size={14} /></button>
                )}
              </div>
            ))}
            {canEdit && (
              <div className="border-t pt-3 space-y-2">
                <input value={immuName} onChange={e => setImmuName(e.target.value)} placeholder="Vaccine/immunization name *" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-300" />
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <label className="text-xs text-gray-500 mb-1 block">Date given</label>
                    <input value={immuDate} onChange={e => setImmuDate(e.target.value)} type="date" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-300" />
                  </div>
                  <div>
                    <label className="text-xs text-gray-500 mb-1 block">Next due</label>
                    <input value={immuNext} onChange={e => setImmuNext(e.target.value)} type="date" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-300" />
                  </div>
                </div>
                <div className="flex justify-end">
                  <button onClick={addImmu} className="bg-green-500 text-white px-4 py-2 rounded-lg text-sm hover:bg-green-600 flex items-center gap-1"><Plus size={14} /> Add</button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Doctor & Insurance Info */}
      <div className="space-y-2">
        <SectionHeader section="info" label="Doctor & Insurance" icon={<FileText size={16} />} />
        {expandedSections.has('info') && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-gray-500 mb-1 block">Doctor's Name</label>
                {canEdit
                  ? <input value={infoFields.doctorName} onChange={e => setInfoFields(f => ({ ...f, doctorName: e.target.value }))} onBlur={() => flushInfoField('doctorName')} placeholder="Dr. Smith" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
                  : <div className="text-sm text-gray-700">{record.doctorName || '—'}</div>
                }
              </div>
              <div>
                <label className="text-xs text-gray-500 mb-1 block">Doctor's Phone</label>
                {canEdit
                  ? <input value={infoFields.doctorPhone} onChange={e => setInfoFields(f => ({ ...f, doctorPhone: e.target.value }))} onBlur={() => flushInfoField('doctorPhone')} placeholder="02 1234 5678" type="tel" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
                  : record.doctorPhone ? <a href={`tel:${record.doctorPhone}`} className="text-sm text-indigo-600 hover:underline">{record.doctorPhone}</a> : <span className="text-sm text-gray-700">—</span>
                }
              </div>
              <div>
                <label className="text-xs text-gray-500 mb-1 block">Insurance Provider</label>
                {canEdit
                  ? <input value={infoFields.insuranceProvider} onChange={e => setInfoFields(f => ({ ...f, insuranceProvider: e.target.value }))} onBlur={() => flushInfoField('insuranceProvider')} placeholder="Medibank, Bupa…" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
                  : <div className="text-sm text-gray-700">{record.insuranceProvider || '—'}</div>
                }
              </div>
              <div>
                <label className="text-xs text-gray-500 mb-1 block">Policy Number</label>
                {canEdit
                  ? <input value={infoFields.insurancePolicyNumber} onChange={e => setInfoFields(f => ({ ...f, insurancePolicyNumber: e.target.value }))} onBlur={() => flushInfoField('insurancePolicyNumber')} placeholder="123 456 789" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
                  : <div className="text-sm text-gray-700">{record.insurancePolicyNumber || '—'}</div>
                }
              </div>
            </div>
            <div>
              <label className="text-xs text-gray-500 mb-1 block">Additional Notes</label>
              {canEdit
                ? <textarea value={infoFields.notes} onChange={e => setInfoFields(f => ({ ...f, notes: e.target.value }))} onBlur={() => flushInfoField('notes')} placeholder="Any other health notes…" rows={3} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300 resize-none" />
                : <div className="text-sm text-gray-700 whitespace-pre-wrap">{record.notes || '—'}</div>
              }
            </div>
          </div>
        )}
      </div>

      {/* Last updated */}
      <div className="text-xs text-gray-400 text-center pb-2">
        Last updated: {new Date(record.updatedAt).toLocaleDateString()}
        {record.updatedBy && (() => {
          const u = (db.users || []).find(u => u.id === record.updatedBy);
          return u ? ` by ${u.name}` : '';
        })()}
      </div>
    </div>
  );
};

export default Health;
