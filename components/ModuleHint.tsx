/**
 * ModuleHint — a contextual empty-state card shown when a module has no data.
 *
 * It auto-disappears once the user adds their first item, so no dismiss button
 * is needed. Designed to be dropped into an existing `{array.length === 0 && …}`
 * conditional already present in each module.
 */
import React from 'react';

interface ModuleHintProps {
  emoji: string;
  title: string;
  tips: readonly string[];
  /** Optional extra class names on the outer wrapper (e.g. custom padding). */
  className?: string;
}

const ModuleHint: React.FC<ModuleHintProps> = ({ emoji, title, tips, className = '' }) => (
  <div className={`bg-stone-50 border border-dashed border-stone-200 rounded-3xl p-8 ${className}`}>
    <div className="text-center mb-5">
      <p className="text-4xl mb-3">{emoji}</p>
      <p className="font-bold text-stone-700">{title}</p>
    </div>
    <ul className="space-y-2 max-w-xs mx-auto">
      {tips.map((tip) => (
        <li key={tip} className="flex items-start gap-2 text-sm text-stone-500">
          <span className="text-stone-300 shrink-0 mt-0.5">›</span>
          <span>{tip}</span>
        </li>
      ))}
    </ul>
  </div>
);

export default ModuleHint;
