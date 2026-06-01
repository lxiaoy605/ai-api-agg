export default function ApiKeysLoading() {
  return (
    <div className="space-y-6 animate-pulse animate-fade-in">
      <div className="flex items-center justify-between">
        <div><div className="h-8 w-36 bg-[var(--surface-raised)] rounded-md" /><div className="h-4 w-56 bg-[var(--surface-raised)] rounded mt-2" /></div>
        <div className="h-10 w-32 bg-[var(--surface-raised)] rounded-lg" />
      </div>
      <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)]">
        <div className="p-4 border-b border-[var(--border-color)]">
          <div className="grid grid-cols-5 gap-4">
            {[...Array(5)].map((_, i) => (<div key={i} className="h-4 w-20 bg-[var(--surface-raised)] rounded" />))}
          </div>
        </div>
        <div className="divide-y divide-[var(--border-color)]">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="p-4 grid grid-cols-5 gap-4">
              <div className="h-4 w-24 bg-[var(--surface-raised)] rounded" />
              <div className="h-4 w-32 bg-[var(--surface-raised)] rounded" />
              <div className="h-4 w-20 bg-[var(--surface-raised)] rounded" />
              <div className="h-4 w-16 bg-[var(--surface-raised)] rounded" />
              <div className="flex gap-2"><div className="h-6 w-14 bg-[var(--surface-raised)] rounded" /><div className="h-6 w-14 bg-[var(--surface-raised)] rounded" /></div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
