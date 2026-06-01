export default function RechargeLoading() {
  return (
    <div className="space-y-6 animate-pulse animate-fade-in">
      <div><div className="h-8 w-32 bg-[var(--surface-raised)] rounded-md" /><div className="h-4 w-56 bg-[var(--surface-raised)] rounded mt-2" /></div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {[...Array(3)].map((_, i) => (
          <div key={i} className={`bg-[var(--card-bg)] rounded-xl border p-6 ${i === 1 ? "border-brand-500/30" : "border-[var(--border-color)]"}`}>
            <div className="h-5 w-20 bg-[var(--surface-raised)] rounded" />
            <div className="h-10 w-16 bg-[var(--surface-raised)] rounded mt-3" />
            <div className="mt-4 space-y-2">
              {[...Array(3)].map((_, j) => (<div key={j} className="h-3 w-full bg-[var(--surface-raised)] rounded" />))}
            </div>
            <div className="mt-4 h-10 w-full bg-[var(--surface-raised)] rounded-lg" />
          </div>
        ))}
      </div>
    </div>
  );
}
