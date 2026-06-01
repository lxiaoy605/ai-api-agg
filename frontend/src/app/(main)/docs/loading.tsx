export default function DocsLoading() {
  return (
    <div className="flex gap-8 animate-pulse animate-fade-in">
      <div className="w-48 shrink-0 hidden lg:block space-y-2">
        {[...Array(8)].map((_, i) => (<div key={i} className={`h-4 bg-[var(--surface-raised)] rounded ${i === 0 ? "w-20" : "w-full"}`} style={{ marginLeft: i > 0 ? 16 : 0 }} />))}
      </div>
      <div className="flex-1 space-y-4">
        <div className="h-8 w-64 bg-[var(--surface-raised)] rounded-lg" />
        <div className="space-y-2">
          <div className="h-4 w-full bg-[var(--surface-raised)] rounded" />
          <div className="h-4 w-5/6 bg-[var(--surface-raised)] rounded" />
          <div className="h-4 w-4/6 bg-[var(--surface-raised)] rounded" />
        </div>
        <div className="h-48 bg-[var(--surface-raised)] rounded-lg" />
        <div className="space-y-2">
          <div className="h-4 w-full bg-[var(--surface-raised)] rounded" />
          <div className="h-4 w-3/4 bg-[var(--surface-raised)] rounded" />
          <div className="h-4 w-5/6 bg-[var(--surface-raised)] rounded" />
        </div>
      </div>
    </div>
  );
}
