export default function NotFound() {
  return (
    <div className="min-h-[calc(100vh-3.5rem)] flex items-center justify-center">
      <div className="text-center px-4">
        <h1 className="text-8xl font-extrabold bg-gradient-to-br from-brand-500 to-brand-600 bg-clip-text text-transparent select-none">
          404
        </h1>

        <h2 className="mt-6 text-xl font-semibold text-[var(--body-text)]">
          This page could not be found.
        </h2>
        <p className="mt-2 text-sm text-[var(--muted-text)] max-w-md mx-auto">
          The page you&apos;re looking for doesn&apos;t exist or has been moved.
        </p>
      </div>
    </div>
  );
}
